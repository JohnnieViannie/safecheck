import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safecheck/screens/sos_sent_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/biometric_service.dart';
import 'package:safecheck/services/safety_service.dart';

class EmergencySosScreen extends StatefulWidget {
  const EmergencySosScreen({super.key});

  @override
  State<EmergencySosScreen> createState() => _EmergencySosScreenState();
}

class _EmergencySosScreenState extends State<EmergencySosScreen>
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _danger = Color(0xFFEF4444);

  static const Duration _holdDuration = Duration(seconds: 3);

  Timer? _holdTimer;
  double _holdProgress = 0;
  bool _firing = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    BiometricLockSession.suppressPrompts();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    BiometricLockSession.releasePrompts();
    _holdTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_firing || _holdProgress > 0) return;
    _holdTimer?.cancel();
    final DateTime started = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
      final double elapsedMs =
          DateTime.now().difference(started).inMilliseconds.toDouble();
      final double progress =
          (elapsedMs / _holdDuration.inMilliseconds).clamp(0.0, 1.0);
      if (!mounted) return;
      setState(() => _holdProgress = progress);
      if (progress >= 1.0) {
        timer.cancel();
        unawaited(_fireSos(discreet: false));
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (_firing) return;
    setState(() => _holdProgress = 0);
  }

  Future<void> _fireSos({required bool discreet}) async {
    if (_firing) return;
    setState(() {
      _firing = true;
      _holdProgress = 1;
    });
    HapticFeedback.heavyImpact();

    final String? uid = AuthService.instance.currentUser?.uid;
    final DateTime firedAt = DateTime.now();
    double? latitude;
    double? longitude;

    if (uid != null && uid.isNotEmpty) {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          final Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 8));
          latitude = position.latitude;
          longitude = position.longitude;
          await SafetyService.instance.updateLocation(
            uid: uid,
            latitude: latitude,
            longitude: longitude,
          );
        }
      } catch (_) {
        // Continue with escalation even if GPS fails.
      }

      await SafetyService.instance.escalateMissedOrDeclined(
        uid: uid,
        reason: discreet ? 'sos_discreet' : 'sos_panic',
      );
      await SafetyService.instance.logTimelineEvent(
        uid: uid,
        eventType: 'sos_fired',
        status: 'escalated',
        payload: <String, dynamic>{
          'discreet': discreet,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SosSentScreen(
          firedAt: firedAt,
          latitude: latitude,
          longitude: longitude,
          discreet: discreet,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text(
          'Emergency SOS',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: <Widget>[
                  Text(
                    'Hold the button for 3 seconds to send an immediate alert — no grace period, no wait.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildSosButton(),
                  const SizedBox(height: 32),
                  _buildInfoCard(
                    emoji: '📍',
                    title: 'Live GPS shared immediately',
                    subtitle:
                        'No grace period. Fires the moment you release the button.',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    emoji: '📱',
                    title: 'SMS to all your contacts',
                    subtitle: 'Even offline — queued for when signal returns.',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    emoji: '🎙️',
                    title: 'Audio recording starts',
                    subtitle:
                        'Sent to your contacts as evidence. Saved to vault.',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    emoji: '📄',
                    title: 'Document vault released',
                    subtitle:
                        'Next-of-kin and medical info sent automatically.',
                  ),
                  const SizedBox(height: 20),
                  _buildDiscreetModeCard(),
                ],
              ),
            ),
          ),
          if (_firing) _buildSendingOverlay(),
        ],
      ),
    );
  }

  Widget _buildSendingOverlay() {
    return Positioned.fill(
      child: Material(
        color: _background.withValues(alpha: 0.96),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: <Widget>[
                const Spacer(flex: 2),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _danger.withValues(alpha: 0.85),
                          backgroundColor: _danger.withValues(alpha: 0.12),
                        ),
                      ),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _danger.withValues(alpha: 0.16),
                          border: Border.all(
                            color: _danger.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Icon(
                          Icons.sos_rounded,
                          color: _danger,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Sending SOS…',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Georgia',
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Alerting contacts and sharing your location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
                const SizedBox(height: 28),
                _sendingStep('Capturing GPS location'),
                const SizedBox(height: 10),
                _sendingStep('Notifying emergency contacts'),
                const SizedBox(height: 10),
                _sendingStep('Starting audio recording'),
                const SizedBox(height: 10),
                _sendingStep('Releasing document vault'),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendingStep(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _danger.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (BuildContext context, Widget? child) {
        final double pulse = 0.08 + (_pulseController.value * 0.06);
        return Listener(
          onPointerDown: (_) => _startHold(),
          onPointerUp: (_) => _cancelHold(),
          onPointerCancel: (_) => _cancelHold(),
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  width: 220 * (1 + pulse),
                  height: 220 * (1 + pulse),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _danger.withValues(alpha: 0.08),
                  ),
                ),
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _danger.withValues(alpha: 0.16),
                  ),
                ),
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: _holdProgress > 0 ? _holdProgress : null,
                        strokeWidth: 4,
                        color: Colors.white.withValues(alpha: 0.85),
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                      Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: <Color>[
                              _danger,
                              _danger.withValues(alpha: 0.82),
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: _danger.withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              _firing ? 'Sending…' : 'sos',
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _holdProgress > 0 && !_firing
                                  ? 'Keep holding…'
                                  : 'Hold 3s',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscreetModeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.volume_off_rounded,
            size: 22,
            color: Colors.white.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
                children: const <TextSpan>[
                  TextSpan(
                    text: 'Discreet mode: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Shake your phone 3 times to fire SOS silently — no sound, no screen flash. Safe to use when you cannot be seen pressing a button.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
