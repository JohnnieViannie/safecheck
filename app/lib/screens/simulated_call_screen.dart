import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/safety_service.dart';

class SimulatedCallContext {
  const SimulatedCallContext({
    required this.callerName,
    required this.userDisplayName,
    required this.scheduledFor,
    required this.frequency,
    required this.reason,
    this.isSnoozedRetry = false,
  });

  final String callerName;
  final String userDisplayName;
  final DateTime scheduledFor;
  final String frequency;
  final String reason;
  final bool isSnoozedRetry;
}

enum SimulatedCallAction { safeConfirmed, remindMe, declined, messageSent }

class SimulatedCallResult {
  const SimulatedCallResult({
    required this.action,
    this.snoozedUntil,
    this.note,
  });

  final SimulatedCallAction action;
  final DateTime? snoozedUntil;
  final String? note;
}

class SimulatedCallScreen extends StatefulWidget {
  const SimulatedCallScreen({super.key, required this.contextData});

  final SimulatedCallContext contextData;

  @override
  State<SimulatedCallScreen> createState() => _SimulatedCallScreenState();
}

class _SimulatedCallScreenState extends State<SimulatedCallScreen>
    with SingleTickerProviderStateMixin {
  bool _accepted = false;
  double _slideValue = 0.0;
  Timer? _ringTimer;
  Timer? _incomingTimeoutTimer;
  Timer? _clockTimer;
  late final AnimationController _pulseController;
  late final SpeechToText _speechToText;
  late final FlutterTts _tts;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _ttsPluginAvailable = true;
  bool _ttsSpeaking = false;
  Future<void>? _ttsInitFuture;
  bool _isListening = false;
  bool _endingCall = false;
  String _listeningHint = 'Waiting to connect...';
  String _displayTime = '';
  _CallPhase _phase = _CallPhase.incoming;
  int _retryCount = 0;
  static const int _maxRetries = 1;
  Timer? _listenTimeoutTimer;
  static const Duration _maxRingDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _speechToText = SpeechToText();
    _tts = FlutterTts();
    _ttsInitFuture = _initTts();
    _initSpeech();
    _displayTime = _formatClock(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _displayTime = _formatClock(DateTime.now()));
    });
    _startRinging();

    // Best-effort: upload one location snapshot so backend can include a
    // Maps link when escalating a missed/unsafe check-in.
    unawaited(_captureAndUploadLocation());
  }

  Future<void> _captureAndUploadLocation() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));

      await SafetyService.instance.updateLocation(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Ignore location failures; safety escalation should still work.
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() {
        if (!mounted) return;
        setState(() => _ttsSpeaking = true);
      });
      _tts.setCompletionHandler(() {
        if (!mounted) return;
        setState(() => _ttsSpeaking = false);
        if (_accepted &&
            _phase == _CallPhase.connectedPrompting &&
            !_isListening) {
          unawaited(_startListening());
        }
      });
      _tts.setErrorHandler((errorMessage) {
        debugPrint('[SimulatedCallScreen][TTS] Runtime error: $errorMessage');
        if (!mounted) return;
        setState(() => _ttsSpeaking = false);
      });
      _ttsReady = true;
    } catch (e, st) {
      debugPrint('[SimulatedCallScreen][TTS] Init failed: $e');
      debugPrint('[SimulatedCallScreen][TTS] Init stack: $st');
      _ttsReady = false;
      if (e is MissingPluginException) {
        _ttsPluginAvailable = false;
      }
    }
  }

  Future<void> _safeStopTts({required String location}) async {
    if (!_ttsPluginAvailable) return;
    try {
      await _tts.stop();
    } catch (e) {
      if (e is MissingPluginException) {
        _ttsPluginAvailable = false;
      }
    }
  }

  Future<void> _ensureTtsReady() async {
    if (_ttsReady) return;
    await (_ttsInitFuture ?? Future<void>.value());
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speechToText.initialize(
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _listeningHint =
              'Microphone error. Please allow mic access and try again.';
        });
      },
    );
    if (mounted) {
      setState(() {});
      if (_accepted &&
          _phase == _CallPhase.connectedPrompting &&
          !_isListening) {
        unawaited(_startListening());
      }
    }
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    await _initSpeech();
    return _speechReady;
  }

  void _startRinging() {
    _ringTimer?.cancel();
    _incomingTimeoutTimer?.cancel();
    try {
      FlutterRingtonePlayer().playRingtone(
        volume: 1.0,
        looping: true,
        asAlarm: true,
      );
    } catch (_) {
      // Keep haptic/system alert fallback if plugin is unavailable on device.
    }
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_accepted) return;
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
    });
    _incomingTimeoutTimer = Timer(_maxRingDuration, () {
      if (!mounted || _accepted) return;
      _stopRinging();
      setState(() {
        _phase = _CallPhase.missed;
        _listeningHint = 'Missed call. No answer in 30 seconds.';
      });
      Navigator.of(
        context,
      ).pop(
        const SimulatedCallResult(
          action: SimulatedCallAction.declined,
          note: 'no_answer',
        ),
      );
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _incomingTimeoutTimer?.cancel();
    _incomingTimeoutTimer = null;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {
      // Ignore stop failures silently.
    }
  }

  void _acceptCall() {
    _stopRinging();
    setState(() {
      _accepted = true;
      _phase = _CallPhase.connectedPrompting;
      _listeningHint = 'Connected. Preparing check-in prompt...';
    });
    HapticFeedback.heavyImpact();
    _runVoiceFlow();
  }

  Future<bool> _speakPrompt(String text) async {
    setState(() {
      _phase = _CallPhase.connectedPrompting;
      _listeningHint = text;
    });
    await _ensureTtsReady();
    if (!_ttsReady) {
      setState(() {
        _listeningHint = _ttsPluginAvailable
            ? 'Voice prompt unavailable. Listening now...'
            : 'Voice plugin not loaded. Do full app restart. Listening now...';
      });
      return false;
    }
    try {
      await _safeStopTts(location: '_speakPrompt:beforeSpeakStop');
      await _tts.speak(text);
      return true;
    } catch (e, st) {
      debugPrint('[SimulatedCallScreen][TTS] Speak failed: $e');
      debugPrint('[SimulatedCallScreen][TTS] Speak stack: $st');
      if (e is MissingPluginException) {
        _ttsPluginAvailable = false;
      }
      if (mounted) {
        setState(() {
          _listeningHint = _ttsPluginAvailable
              ? 'Unable to play voice prompt. Listening now...'
              : 'Voice plugin missing in current run. Do full app restart.';
        });
      }
      return false;
    }
  }

  Future<void> _runVoiceFlow() async {
    await _speakPrompt('Hey, how are you doing');
    if (!mounted || _phase == _CallPhase.confirmedSafe) return;
    await _startListening();
  }

  Future<void> _startListening({bool fromRetry = false}) async {
    if (_isListening || _endingCall) {
      return;
    }
    if (_ttsSpeaking) {
      setState(() {
        _listeningHint = 'Finishing prompt...';
      });
      return;
    }
    final bool ready = await _ensureSpeechReady();
    if (!ready) {
      if (!mounted) return;
      setState(() {
        _listeningHint =
            'Microphone unavailable. Enable mic permission, then retry voice check.';
      });
      return;
    }
    _listenTimeoutTimer?.cancel();
    setState(() {
      _isListening = true;
      _phase = _CallPhase.listening;
      _listeningHint = fromRetry
          ? 'I am listening again. Please say you are safe.'
          : 'I am listening. Tell me if you are safe.';
    });
    final Completer<void> done = Completer<void>();
    bool completed = false;
    void complete() {
      if (!completed) {
        completed = true;
        if (!done.isCompleted) done.complete();
      }
    }

    _listenTimeoutTimer = Timer(const Duration(seconds: 8), () {
      _speechToText.stop();
      setState(() {
        _isListening = false;
        _listeningHint = 'No response detected.';
      });
      complete();
    });
    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
      ),
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
      onResult: (SpeechRecognitionResult result) {
        final phrase = result.recognizedWords.toLowerCase();
        if (_isSafeIntent(phrase)) {
          _listenTimeoutTimer?.cancel();
          unawaited(_completeSafe());
          complete();
          return;
        }
        if (result.finalResult) {
          _listenTimeoutTimer?.cancel();
          setState(() {
            _isListening = false;
            _listeningHint =
                'I heard "${result.recognizedWords}", but I could not confirm safety.';
          });
          complete();
        }
      },
      onSoundLevelChange: (_) {},
    );
    await done.future;
    _stopListening();
    if (!mounted || _phase == _CallPhase.confirmedSafe) return;
    await _handleNoSafeResponse();
  }

  void _stopListening() {
    _listenTimeoutTimer?.cancel();
    _listenTimeoutTimer = null;
    if (_isListening) {
      _speechToText.stop();
      setState(() => _isListening = false);
    }
  }

  Future<void> _handleNoSafeResponse() async {
    if (_retryCount < _maxRetries) {
      _retryCount += 1;
      await _speakPrompt("I didn't catch that. Are you safe right now?");
      if (!mounted || _phase == _CallPhase.confirmedSafe) return;
      await _startListening(fromRetry: true);
      return;
    }

    // After we've exhausted the in-call voice retries, decide whether to
    // snooze-and-retry once, or escalate immediately.
    final bool shouldSnoozeRetry = !widget.contextData.isSnoozedRetry;

    setState(() {
      _phase = _CallPhase.missed;
      _listeningHint = 'No response detected. Marking this call as missed.';
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    if (shouldSnoozeRetry) {
      await _remindInTenMinutes();
      return;
    }

    Navigator.of(context).pop(
      const SimulatedCallResult(
        action: SimulatedCallAction.declined,
        note: 'no_safe_response',
      ),
    );
  }

  bool _isSafeIntent(String phrase) {
    final normalized = phrase.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const negatives = <String>[
      'not',
      'no',
      'help',
      'danger',
      'pain',
      'unsafe',
      'problem',
      'emergency',
      'bad',
      'hurt',
      'trouble',
    ];
    if (negatives.any(normalized.contains)) {
      return false;
    }
    const positivePhrases = <String>[
      "i'm safe",
      'i am safe',
      'im safe',
      'am safe',
      "i'm safer",
      'i am safer',
      'im safer',
      'all good',
      "i'm fine",
      'i am fine',
      'im fine',
      'am fine',
      'doing good',
      'doing okay',
      "i'm okay",
      'i am okay',
      'im okay',
    ];
    if (positivePhrases.any(normalized.contains)) {
      return true;
    }
    const positives = <String>[
      'fine',
      'okay',
      'ok',
      'good',
      'safe',
      'safer',
      'alright',
      'great',
      'well',
      'better',
    ];
    return positives.any(normalized.contains);
  }

  Future<void> _completeSafe() async {
    if (_endingCall) return;
    _endingCall = true;
    _stopListening();
    setState(() {
      _phase = _CallPhase.confirmedSafe;
      _listeningHint = 'Got that. Hanging up now...';
    });
    await _speakAcknowledgement();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(SimulatedCallResult(action: SimulatedCallAction.safeConfirmed));
  }

  Future<void> _speakAcknowledgement() async {
    await _ensureTtsReady();
    if (!_ttsReady) return;
    try {
      await _safeStopTts(location: '_speakAcknowledgement:beforeSpeakStop');
      await _tts.speak('Got that.');
    } catch (_) {
      // If acknowledgement TTS fails, end the call immediately.
    }
  }

  Widget _buildCallWave(bool isCompact) {
    final double baseHeight = isCompact ? 12 : 15;
    final double activeBoost = (_ttsSpeaking || _isListening) ? 20 : 8;
    return SizedBox(
      height: isCompact ? 56 : 68,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final double t = _pulseController.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(5, (int index) {
              final double phaseOffset = index * 0.18;
              final double normalized = (t + phaseOffset) % 1.0;
              final double wave =
                  (normalized < 0.5 ? normalized : 1 - normalized) * 2;
              final double height = baseHeight + (wave * activeBoost);
              return Container(
                width: 6,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: (_ttsSpeaking || _isListening)
                      ? Colors.greenAccent.withValues(alpha: 0.95)
                      : Colors.white38,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Future<void> _remindInTenMinutes() async {
    _stopRinging();
    _stopListening();
    await _safeStopTts(location: '_remindInTenMinutes');
    final DateTime snooze = DateTime.now().add(const Duration(minutes: 10));
    if (!mounted) return;
    Navigator.of(context).pop(
      SimulatedCallResult(
        action: SimulatedCallAction.remindMe,
        snoozedUntil: snooze,
      ),
    );
  }

  @override
  void dispose() {
    _stopRinging();
    _stopListening();
    unawaited(_safeStopTts(location: 'dispose'));
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isCompact = screenHeight < 760;
    final double topGap = isCompact ? 14 : 40;
    final double avatarSize = isCompact ? 112 : 140;
    final double titleSize = isCompact ? 26 : 32;
    final double midGap = isCompact ? 20 : 32;
    final double preAnswerGap = isCompact ? 24 : 48;
    final double actionBottomGap = isCompact ? 24 : 40;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0F1E), Color(0xFF1C2538)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView(
              children: [
                SizedBox(height: topGap),
                Text(
                  _displayTime,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isCompact ? 18 : 28),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.08);
                    return Transform.scale(
                      scale: scale,
                      child: Center(
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.75),
                              width: 5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.35),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 65,
                            backgroundColor: Color(0xFF1E2A44),
                            child: Icon(
                              Icons.shield,
                              size: 72,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: midGap),
                Text(
                  widget.contextData.callerName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _accepted
                      ? _phaseLabel(_phase)
                      : 'Incoming ${widget.contextData.frequency} check-in',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 17),
                ),
                const SizedBox(height: 6),

                SizedBox(height: isCompact ? 28 : 48),
                if (!_accepted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(
                        icon: Icons.alarm,
                        label: 'Remind Me',
                        onTap: _remindInTenMinutes,
                      ),
                    ],
                  ),
                  SizedBox(height: preAnswerGap),
                  GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _slideValue = (_slideValue + details.delta.dx / 180)
                            .clamp(0.0, 1.0);
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      if (_slideValue >= 0.82) {
                        _acceptCall();
                      } else {
                        setState(() => _slideValue = 0.0);
                      }
                    },
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width:
                                  MediaQuery.of(context).size.width *
                                  0.78 *
                                  _slideValue,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                          ),
                          const Text(
                            'slide to answer',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Positioned(
                            left:
                                6 +
                                (MediaQuery.of(context).size.width *
                                    0.68 *
                                    _slideValue),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.phone,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: actionBottomGap),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      onPressed: () {
                        _stopRinging();
                        Navigator.of(context).pop(
                          const SimulatedCallResult(
                            action: SimulatedCallAction.declined,
                            note: 'declined',
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFCC2E2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  _buildCallWave(isCompact),
                  const SizedBox(height: 10),
                  Text(
                    _listeningHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _speechReady
                          ? (_isListening
                                ? _stopListening
                                : () => _startListening(fromRetry: true))
                          : null,
                      icon: Icon(
                        _isListening ? Icons.hearing_disabled : Icons.mic,
                      ),
                      label: Text(
                        _isListening ? 'Stop Listening' : 'Retry Voice Check',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      onPressed: () => unawaited(_completeSafe()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.green.shade500),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Text(
                        "Tap for I'm Fine",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: actionBottomGap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CallPhase {
  incoming,
  connectedPrompting,
  listening,
  confirmedSafe,
  missed,
}

String _phaseLabel(_CallPhase phase) {
  switch (phase) {
    case _CallPhase.incoming:
      return 'Incoming';
    case _CallPhase.connectedPrompting:
      return 'Asking check-in question';
    case _CallPhase.listening:
      return 'Listening';
    case _CallPhase.confirmedSafe:
      return 'Confirmed safe';
    case _CallPhase.missed:
      return 'No response';
  }
}

String _formatClock(DateTime date) {
  final int hour12 = (date.hour % 12 == 0) ? 12 : date.hour % 12;
  final String minute = date.minute.toString().padLeft(2, '0');
  final String period = date.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $period';
}

// Reusable small button for Remind Me / Message
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
