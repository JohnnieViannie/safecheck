import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/screens/settings_screen.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/reliable_alarm_permissions.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/widgets/app_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  String _checkinTime = '18:00';
  String _frequency = 'Daily';
  String _callStatus = 'Scheduled';
  DateTime _nextCallAt = DateTime.now();
  bool _callLaunchInProgress = false;
  Duration _gracePeriod = const Duration(hours: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeTimer();
  }

  Future<void> _initializeTimer() async {
    await _reloadSchedule();
    await _hydrateStatusFromServer();
    _gracePeriod = await StorageService.instance.getGracePeriod();

    final DateTime now = DateTime.now();
    final DateTime? snoozed = await StorageService.instance.getSnoozedUntil();

    if (snoozed != null) {
      if (snoozed.isAfter(now)) {
        _nextCallAt = snoozed;
      } else if (now.difference(snoozed) <= _gracePeriod) {
        // If we reopened shortly after a scheduled snooze, treat it as due.
        _nextCallAt = snoozed;
      } else {
        _nextCallAt = _computeNextCallAt(now);
      }
    } else {
      _nextCallAt = _computeDueCallAt(now);
    }

    // Ensure background alarms are scheduled (even if the UI timer is paused).
    unawaited(AlarmScheduler.instance.ensureAlarmsScheduled());
    if (mounted) {
      unawaited(ReliableAlarmPermissions.ensureAndroidAlarmReliability(context: context));
    }
    if (snoozed != null && snoozed.isAfter(now)) {
      unawaited(AlarmScheduler.instance.scheduleSnoozeAlarm(snoozed));
    }
    _updateRemaining();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  Future<void> _reloadSchedule() async {
    final localTime = await StorageService.instance.getCheckinTime();
    final localFrequency = await StorageService.instance.getCheckinFrequency();
    if (localTime != null && localTime.trim().isNotEmpty) {
      _checkinTime = localTime.trim();
    }
    _frequency = localFrequency;

    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      final profile = await AuthService.instance.getUserProfile(uid);
      if (profile != null) {
        if ((profile.checkinTime ?? '').trim().isNotEmpty) {
          _checkinTime = profile.checkinTime!.trim();
        }
        if ((profile.checkinFrequency ?? '').trim().isNotEmpty) {
          _frequency = profile.checkinFrequency!.trim();
        }
      }
    }
  }

  Future<void> _markSafe() async {
    final DateTime now = DateTime.now();
    await StorageService.instance.saveLastCheckIn(now);
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await SafetyService.instance.createCheckin(
        uid: uid,
        status: 'safe_confirmed',
      );
      await SafetyService.instance.logTimelineEvent(
        uid: uid,
        eventType: 'safe_button_tapped',
        status: 'safe_confirmed',
        payload: <String, dynamic>{'at': now.toIso8601String()},
      );
    }
    setState(() {
      _callStatus = 'Safe confirmed';
      _nextCallAt = _computeNextCallAt(now);
      _remaining = _nextCallAt.difference(now);
    });
    await StorageService.instance.clearSnoozedUntil();
    unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You\'re safe. Check-in recorded.')),
    );
  }

  void _updateRemaining() {
    final Duration diff = _nextCallAt.difference(DateTime.now());

    if (!mounted) return;

    setState(() {
      if (diff.isNegative) {
        _remaining = Duration.zero;
        _callStatus = 'Incoming call';
      } else {
        _remaining = diff;
      }
    });
  }

  Future<void> _autoLaunchCallIfDue() async {
    if (_callLaunchInProgress || !mounted) {
      return;
    }
    _callLaunchInProgress = true;
    await _simulateCallNow();
    if (!mounted) return;
    setState(() {
      _nextCallAt = _computeNextCallAt(DateTime.now());
      _remaining = _nextCallAt.difference(DateTime.now());
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
      }
    });
    _callLaunchInProgress = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateRemaining();
      if (_nextCallAt.isBefore(DateTime.now())) {
        // Call UI is driven by CallKit; avoid auto-navigating here to
        // prevent duplicate screens.
      }
    }
  }

  DateTime _computeNextCallAt(DateTime now) {
    final parts = _checkinTime.split(':');
    final hour = int.tryParse(parts.first) ?? 18;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(
        _frequency == 'Weekly'
            ? const Duration(days: 7)
            : const Duration(days: 1),
      );
    }
    return candidate;
  }

  /// Computes the scheduled check-in time, but allows returning a time in
  /// the recent past when we're within the configured grace window.
  DateTime _computeDueCallAt(DateTime now) {
    final parts = _checkinTime.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);

    // Future today.
    if (candidate.isAfter(now)) {
      return candidate;
    }

    // Within grace -> treat as due now.
    if (now.difference(candidate) <= _gracePeriod) {
      return candidate;
    }

    final Duration increment =
        _frequency == 'Weekly' ? const Duration(days: 7) : const Duration(days: 1);

    // Past beyond grace -> move to the next cycle.
    while (true) {
      candidate = candidate.add(increment);
      if (candidate.isAfter(now)) {
        return candidate;
      }
    }
  }

  Future<void> _simulateCallNow() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await SafetyService.instance.logTimelineEvent(
        uid: uid,
        eventType: 'call_simulation_started',
        status: 'in_progress',
        payload: <String, dynamic>{'scheduled_for': _nextCallAt.toIso8601String()},
      );
    }
    final contextData = SimulatedCallContext(
      callerName: 'SafeCheck',
      userDisplayName:
          AuthService.instance.currentUser?.displayIdentifier ?? 'User',
      scheduledFor: _nextCallAt,
      frequency: _frequency,
      reason: 'Routine safety check-in call',
    );
    final SimulatedCallResult? result = await Navigator.of(context)
        .push<SimulatedCallResult>(
          MaterialPageRoute<SimulatedCallResult>(
            builder: (_) => SimulatedCallScreen(contextData: contextData),
          ),
        );
    if (!mounted) return;
    switch (result?.action) {
      case SimulatedCallAction.safeConfirmed:
        await _markSafe();
        break;
      case SimulatedCallAction.remindMe:
        if (result?.snoozedUntil != null) {
          await StorageService.instance.saveSnoozedUntil(result!.snoozedUntil!);
          setState(() {
            _nextCallAt = result.snoozedUntil!;
            _remaining = _nextCallAt.difference(DateTime.now());
            _callStatus = 'Snoozed for 10 minutes';
          });
          await AlarmScheduler.instance.scheduleSnoozeAlarm(
            result.snoozedUntil!,
          );
          final String? uid = AuthService.instance.currentUser?.uid;
          if (uid != null && uid.isNotEmpty) {
            await SafetyService.instance.logTimelineEvent(
              uid: uid,
              eventType: 'checkin_snoozed',
              status: 'snoozed',
              payload: <String, dynamic>{
                'until': result.snoozedUntil!.toIso8601String(),
              },
            );
          }
        }
        break;
      case SimulatedCallAction.declined:
        await StorageService.instance.clearSnoozedUntil();
        unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
        final String? uid = AuthService.instance.currentUser?.uid;
        final String reason = result?.note?.toString() ?? 'declined';
        bool escalated = false;
        if (uid != null && uid.isNotEmpty) {
          escalated = await SafetyService.instance.escalateMissedOrDeclined(
            uid: uid,
            reason: reason,
          );
        }
        setState(
          () => _callStatus = escalated
              ? 'Missed check-in: alert sent to next of kin'
              : 'Missed check-in: alert failed',
        );
        if (uid != null && uid.isNotEmpty) {
          await SafetyService.instance.logTimelineEvent(
            uid: uid,
            eventType: 'checkin_declined',
            status: escalated ? 'escalated' : 'failed',
            payload: <String, dynamic>{'reason': reason},
          );
        }
        break;
      case SimulatedCallAction.messageSent:
        await StorageService.instance.clearSnoozedUntil();
        unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
        setState(() => _callStatus = 'Message sent');
        final String? uid = AuthService.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await SafetyService.instance.logTimelineEvent(
            uid: uid,
            eventType: 'message_sent',
            status: 'success',
          );
        }
        break;
      case null:
        await StorageService.instance.clearSnoozedUntil();
        unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
        setState(() => _callStatus = 'Call dismissed');
        final String? uid = AuthService.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await SafetyService.instance.logTimelineEvent(
            uid: uid,
            eventType: 'call_dismissed',
            status: 'dismissed',
          );
        }
        break;
    }
  }

  Future<void> _hydrateStatusFromServer() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    final List<Map<String, dynamic>> checkins = await SafetyService.instance
        .fetchCheckins(uid);
    final List<Map<String, dynamic>> attempts = await SafetyService.instance
        .fetchCallAttempts(uid);

    if (!mounted) return;
    if (checkins.isNotEmpty) {
      final latestCheckin = checkins.first;
      final String latestStatus = (latestCheckin['status'] as String? ?? 'ok')
          .replaceAll('_', ' ');
      setState(() {
        _callStatus = 'Last check-in: $latestStatus';
      });
    } else if (attempts.isNotEmpty) {
      final String latestAttempt = (attempts.first['status'] as String? ?? '')
          .replaceAll('_', ' ');
      if (latestAttempt.isNotEmpty) {
        setState(() {
          _callStatus = 'Last call: $latestAttempt';
        });
      }
    }
  }

  String _formatDuration(Duration value) {
    final String hh = value.inHours.toString().padLeft(2, '0');
    final String mm = (value.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Future<void> _logout() async {
    unawaited(AlarmScheduler.instance.cancelAllAlarms());
    await AuthService.instance.signOut();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int totalSeconds = _frequency == 'Weekly'
        ? const Duration(days: 7).inSeconds
        : const Duration(days: 1).inSeconds;
    final double progress = totalSeconds > 0
        ? (_remaining.inSeconds / totalSeconds).clamp(0.0, 1.0)
        : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: const Color(
          0xFF0A0A0A,
        ), // Also make the bottom nav bar dark!
        statusBarColor: Colors.transparent,
      ),
      child: Theme(
        data: AppTheme.darkTheme,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A), // Deep dark modern base
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const AppLogo(height: 32),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 26,
                  color: Colors.white,
                ),
                tooltip: 'Menu',
                color: const Color(0xFF1F1F1F), // Dark background for the popup
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                onSelected: (value) {
                  if (value == 'logout') {
                    _logout();
                  } else if (value == 'settings') {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        )
                        .then((_) async {
                          await _reloadSchedule();
                          if (!mounted) return;
                          setState(() {
                            _nextCallAt = _computeDueCallAt(DateTime.now());
                            _remaining = _nextCallAt.difference(DateTime.now());
                            _callStatus = 'Scheduled';
                          });
                          unawaited(
                            AlarmScheduler.instance.ensureAlarmsScheduled(),
                          );
                        });
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings, color: Colors.white),
                      title: Text(
                        'Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout, color: Colors.redAccent),
                      title: Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Status header with safety dot
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'You are protected',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Text(
                          'Next scheduled call in',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Glassmorphic Countdown Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                              BoxShadow(
                                color: Colors.white.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(-8, -8),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Circular progress ring
                              SizedBox(
                                width: 210,
                                height: 210,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 13,
                                  backgroundColor: Colors.white.withOpacity(
                                    0.08,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF4ADE80),
                                      ),
                                ),
                              ),

                              // Countdown Text (reduced size)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatDuration(_remaining),
                                    style: const TextStyle(
                                      fontSize: 40, // ← Reduced from 56
                                      fontWeight: FontWeight.w900,
                                      height: 1.0,
                                      color: Colors.white,
                                      letterSpacing: -1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _simulateCallNow,
                            child: const Text('Simulate Call Now'),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Call status',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _callStatus,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Frequency: $_frequency • Time: ${_displayTime(_checkinTime)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Modern "I'm Safe" Button
                        GestureDetector(
                          onTap: _markSafe,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 22),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFF4ADE80).withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                const BoxShadow(
                                  color: Colors.black,
                                  blurRadius: 10,
                                  offset: Offset(4, 4),
                                ),
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(-4, -4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "I'M SAFE",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4ADE80),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _displayTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 18;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }
}
