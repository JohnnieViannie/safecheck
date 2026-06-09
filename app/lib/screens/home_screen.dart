import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/screens/settings_screen.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/app_logo.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/alarm_watchdog.dart';
import 'package:safecheck/services/reliable_alarm_permissions.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';

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

    await _advanceIfAlreadySafeForCurrentSlot(now);

    // Ensure background alarms are scheduled (even if the UI timer is paused).
    unawaited(AlarmScheduler.instance.ensureAlarmsScheduled());
    AlarmWatchdog.instance.attach();
    if (mounted) {
      unawaited(ReliableAlarmPermissions.ensureAndroidAlarmReliability(context: context));
      if (await _shouldAutoLaunchCall()) {
        unawaited(_autoLaunchCallIfDue());
      }
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
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Future<void> _markSafe() async {
    final DateTime now = DateTime.now();
    await StorageService.instance.saveLastCheckIn(now);
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await SafetyService.instance.confirmSafe(uid: uid);
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
    unawaited(AlarmScheduler.instance.cancelRetryAlarms());

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

  /// Skip ringing if the user already confirmed safe for this scheduled slot.
  Future<void> _advanceIfAlreadySafeForCurrentSlot(DateTime now) async {
    final DateTime? lastSafe = await StorageService.instance.getLastCheckIn();
    if (lastSafe == null) {
      return;
    }
    if (!lastSafe.isBefore(_nextCallAt)) {
      _nextCallAt = _computeNextCallAt(now);
    }
  }

  Future<bool> _shouldAutoLaunchCall() async {
    final DateTime now = DateTime.now();
    if (_nextCallAt.isAfter(now)) {
      return false;
    }

    final DateTime? lastSafe = await StorageService.instance.getLastCheckIn();
    if (lastSafe != null && !lastSafe.isBefore(_nextCallAt)) {
      return false;
    }

    if (now.difference(_nextCallAt) > _gracePeriod) {
      return false;
    }

    return true;
  }

  Future<void> _autoLaunchCallIfDue() async {
    if (_callLaunchInProgress || !mounted) {
      return;
    }
    if (!await _shouldAutoLaunchCall()) {
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
      unawaited(AlarmWatchdog.instance.refresh());
      unawaited(_autoLaunchCallIfDue());
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
            await SafetyService.instance.syncSnooze(
              uid: uid,
              snoozedUntil: result.snoozedUntil!,
            );
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

  bool get _isCallDue => _remaining <= Duration.zero;

  String get _greeting {
    final int hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  String get _firstName {
    final String? fullName =
        AuthService.instance.currentUser?.fullName?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return fullName.split(RegExp(r'\s+')).first;
    }
    return 'there';
  }

  double _countdownProgress() {
    final int totalSeconds = _frequency == 'Weekly'
        ? const Duration(days: 7).inSeconds
        : const Duration(days: 1).inSeconds;
    if (totalSeconds <= 0) {
      return 0;
    }
    final double remainingFraction =
        (_remaining.inSeconds / totalSeconds).clamp(0.0, 1.0);
    return 1.0 - remainingFraction;
  }

  Color _statusAccent() {
    if (_isCallDue) {
      return const Color(0xFFFFB74D);
    }
    if (_callStatus.toLowerCase().contains('safe')) {
      return const Color(0xFF4ADE80);
    }
    if (_callStatus.toLowerCase().contains('missed') ||
        _callStatus.toLowerCase().contains('alert')) {
      return AppTheme.secondary;
    }
    return AppTheme.primary;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    await _reloadSchedule();
    if (!mounted) {
      return;
    }
    setState(() {
      _nextCallAt = _computeDueCallAt(DateTime.now());
      _remaining = _nextCallAt.difference(DateTime.now());
      _callStatus = 'Scheduled';
    });
    unawaited(AlarmScheduler.instance.ensureAlarmsScheduled());
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
    final double progress = _countdownProgress();
    final Color accent = _statusAccent();
    final String? kinName =
        AuthService.instance.currentUser?.emergencyContactName;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0A0F14),
      ),
      child: Theme(
        data: AppTheme.darkTheme,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0F14),
          body: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildTopBar(),
                        const SizedBox(height: 20),
                        _buildWelcomeCard(accent),
                        const SizedBox(height: 24),
                        _buildCountdownCard(progress, accent),
                        const SizedBox(height: 20),
                        _buildScheduleRow(),
                        const SizedBox(height: 24),
                        _buildSafeButton(),
                        const SizedBox(height: 12),
                        _buildTestCallButton(),
                        const SizedBox(height: 20),
                        _buildStatusCard(kinName, accent),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: <Widget>[
        const AppLogo(height: 34),
        const Spacer(),
        IconButton(
          onPressed: _openSettings,
          tooltip: 'Settings',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.settings_rounded, size: 22),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _logout,
          tooltip: 'Log out',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            foregroundColor: Colors.white70,
          ),
          icon: const Icon(Icons.logout_rounded, size: 22),
        ),
      ],
    );
  }

  Widget _buildWelcomeCard(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppTheme.primary.withValues(alpha: 0.45),
            const Color(0xFF152028),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _greeting,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hey, $_firstName',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: accent.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isCallDue ? 'Check-in due' : 'Protected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _isCallDue
                ? 'Your safety call is ready. Answer or tap I\'m Safe.'
                : 'We\'ll call you at ${_displayTime(_checkinTime)} for your check-in.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownCard(double progress, Color accent) {
    final List<String> parts = _formatDuration(_remaining).split(':');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF141A22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Text(
            _isCallDue ? 'Check-in window open' : 'Next call in',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _timeUnit(parts[0], 'hrs'),
                        _timeColon(),
                        _timeUnit(parts[1], 'min'),
                        _timeColon(),
                        _timeUnit(parts[2], 'sec'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeUnit(String value, String label) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: Colors.white,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _timeColon() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: Colors.white.withValues(alpha: 0.35),
          height: 1,
        ),
      ),
    );
  }

  Widget _buildScheduleRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _infoChip(
            icon: Icons.schedule_rounded,
            label: 'Call time',
            value: _displayTime(_checkinTime),
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _infoChip(
            icon: Icons.repeat_rounded,
            label: 'Frequency',
            value: _frequency,
            color: const Color(0xFF5C9CE6),
          ),
        ),
      ],
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSafeButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _markSafe,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF2E9E5A), Color(0xFF4ADE80)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF4ADE80).withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.verified_user_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text(
                "I'm Safe",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestCallButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _simulateCallNow,
        icon: Icon(
          Icons.phone_in_talk_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        label: Text(
          'Test safety call',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(String? kinName, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141A22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shield_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              const Text(
                'Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _callStatus,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (kinName != null && kinName.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.family_restroom_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Emergency contact: $kinName',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
