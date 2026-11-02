import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safecheck/screens/alert_triggered_screen.dart';
import 'package:safecheck/screens/checkin_flow.dart';
import 'package:safecheck/screens/contacts_screen.dart';
import 'package:safecheck/screens/document_vault_screen.dart';
import 'package:safecheck/screens/emergency_sos_screen.dart';
import 'package:safecheck/screens/history_screen.dart';
import 'package:safecheck/screens/journey_mode_screen.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/screens/settings_screen.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/safecheck_nav_icon.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/alarm_watchdog.dart';
import 'package:safecheck/services/reliable_alarm_permissions.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Color _background = Color(0xFF0A192F);
  static const Color _cardBackground = Color(0xFF112240);
  static const Color _accent = Color(0xFF14B8A6);
  static const Color _checkinGreen = Color(0xFF2F5D4E);

  Timer? _timer;
  Duration _remaining = Duration.zero;
  String _checkinTime = '18:00';
  String _frequency = 'Daily';
  String _callStatus = 'Scheduled';
  DateTime _nextCallAt = DateTime.now();
  bool _callLaunchInProgress = false;
  Duration _gracePeriod = const Duration(hours: 2);
  DateTime? _lastCheckIn;
  int _dayStreak = 0;
  int _alertsTriggered = 0;
  List<Map<String, dynamic>> _checkins = <Map<String, dynamic>>[];
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.onJourneyNotificationOpened =
        (String type, String? journeyId) {
      if (!mounted) return;
      setState(() => _selectedNavIndex = 2);
    };
    _initializeTimer();
  }

  Future<void> _initializeTimer() async {
    await _reloadSchedule();
    _lastCheckIn = await StorageService.instance.getLastCheckIn();
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
        if (profile.lastCheckInAt != null) {
          _lastCheckIn = profile.lastCheckInAt;
        }
        if (mounted) {
          setState(() {});
        }
      }
    } else {
      final localTime = await StorageService.instance.getCheckinTime();
      final localFrequency = await StorageService.instance.getCheckinFrequency();
      if (localTime != null && localTime.trim().isNotEmpty) {
        _checkinTime = localTime.trim();
      }
      _frequency = localFrequency;
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
      await AuthService.instance.getUserProfile(uid);
      await SafetyService.instance.logTimelineEvent(
        uid: uid,
        eventType: 'safe_button_tapped',
        status: 'safe_confirmed',
        payload: <String, dynamic>{'at': now.toIso8601String()},
      );
    }
    setState(() {
      _callStatus = 'Safe confirmed';
      _lastCheckIn = now;
      _nextCallAt = _computeNextCallAt(now);
      _remaining = _nextCallAt.difference(now);
    });
    await StorageService.instance.clearSnoozedUntil();
    unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
    unawaited(AlarmScheduler.instance.cancelRetryAlarms());

    if (!mounted) return;

    final bool pendingSync = await OfflineSyncService.instance.hasPending();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pendingSync
              ? 'You\'re safe. Will sync to server when back online.'
              : 'You\'re safe. Check-in recorded.',
        ),
      ),
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

  DateTime _scheduledCheckinToday() {
    final List<String> parts = _checkinTime.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
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
    final SimulatedCallResult? result = await pushCheckinFlow(
      context,
      contextData: contextData,
      gracePeriod: _gracePeriod,
    );
    if (!mounted) return;
    await _handleCheckinResult(result);
  }

  Future<void> _openFakeCall() async {
    final SimulatedCallResult? result = await Navigator.of(context)
        .push<SimulatedCallResult>(
      MaterialPageRoute<SimulatedCallResult>(
        builder: (_) => SimulatedCallScreen(
          contextData: SimulatedCallContext(
            callerName: 'Mom',
            userDisplayName:
                AuthService.instance.currentUser?.displayIdentifier ?? 'User',
            scheduledFor: DateTime.now(),
            frequency: _frequency,
            reason: 'Fake call — discreet exit',
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (result?.action == SimulatedCallAction.declined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fake call ended')),
      );
    }
  }

  void _openSosPanic() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const EmergencySosScreen(),
      ),
    );
  }

  void _openJourneyMode() {
    setState(() => _selectedNavIndex = 2);
  }

  Future<void> _openCheckInScreen() async {
    final SimulatedCallContext contextData = SimulatedCallContext(
      callerName: 'SafeCheck',
      userDisplayName:
          AuthService.instance.currentUser?.displayIdentifier ?? 'User',
      scheduledFor: _isCallDue ? _nextCallAt : _scheduledCheckinToday(),
      frequency: _frequency,
      reason: 'Manual safety check-in',
    );
    final SimulatedCallResult? result = await pushCheckinFlow(
      context,
      contextData: contextData,
      gracePeriod: _gracePeriod,
    );
    if (!mounted) return;
    await _handleCheckinResult(result);
  }

  Future<void> _handleCheckinResult(SimulatedCallResult? result) async {
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
            _callStatus = 'Snoozed for 30 minutes';
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
        if (reason == 'cancelled_by_pin') {
          setState(() => _callStatus = 'Alert cancelled with PIN');
          if (uid != null && uid.isNotEmpty) {
            await SafetyService.instance.logTimelineEvent(
              uid: uid,
              eventType: 'alert_cancelled_by_pin',
              status: 'cancelled',
            );
          }
          break;
        }
        bool escalated = false;
        if (uid != null && uid.isNotEmpty) {
          escalated = await SafetyService.instance.escalateMissedOrDeclined(
            uid: uid,
            reason: reason == 'grace_expired' ? 'no_answer' : reason,
          );
        }
        setState(
          () => _callStatus = reason == 'need_help'
              ? 'Help request sent to contacts'
              : escalated
                  ? 'Missed check-in: alert sent to next of kin'
                  : 'Missed check-in: alert failed',
        );
        if (escalated && mounted) {
          final bool pendingSync =
              await OfflineSyncService.instance.hasPending();
          if (pendingSync) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Offline — alert queued and will send when back online.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        if (uid != null && uid.isNotEmpty) {
          await SafetyService.instance.logTimelineEvent(
            uid: uid,
            eventType: reason == 'need_help'
                ? 'help_requested'
                : 'checkin_declined',
            status: escalated ? 'escalated' : 'failed',
            payload: <String, dynamic>{'reason': reason},
          );
        }
        if (escalated && mounted) {
          await AlertTriggeredScreen.show(
            context,
            missedCheckinAt: _nextCallAt,
          );
          await _hydrateStatusFromServer();
          if (mounted) {
            setState(() {});
          }
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
    unawaited(_hydrateStatusFromServer());
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
    final List<Map<String, dynamic>> alerts =
        await SafetyService.instance.fetchAlerts(uid);

    if (!mounted) return;
    setState(() {
      _dayStreak = _computeStreak(checkins);
      _alertsTriggered = alerts.length;
      _checkins = checkins;
      if (checkins.isNotEmpty) {
        final Map<String, dynamic> latestCheckin = checkins.first;
        final String latestStatus =
            (latestCheckin['status'] as String? ?? 'ok').replaceAll('_', ' ');
        _callStatus = 'Last check-in: $latestStatus';
      } else if (attempts.isNotEmpty) {
        final String latestAttempt =
            (attempts.first['status'] as String? ?? '').replaceAll('_', ' ');
        if (latestAttempt.isNotEmpty) {
          _callStatus = 'Last call: $latestAttempt';
        }
      }
    });
  }

  int _computeStreak(List<Map<String, dynamic>> checkins) {
    final Set<String> safeDays = <String>{};
    for (final Map<String, dynamic> checkin in checkins) {
      final String status = checkin['status'] as String? ?? '';
      if (status != 'safe_confirmed' && status != 'ok') {
        continue;
      }
      final DateTime? when = _parseEventTime(checkin);
      if (when == null) {
        continue;
      }
      safeDays.add('${when.year}-${when.month}-${when.day}');
    }

    int streak = 0;
    DateTime day = DateTime.now();
    while (safeDays.contains('${day.year}-${day.month}-${day.day}')) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  DateTime? _parseEventTime(Map<String, dynamic> item) {
    final dynamic raw = item['created_at'] ??
        item['createdAt'] ??
        item['timestamp'] ??
        item['at'];
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  bool get _isCallDue => _remaining <= Duration.zero;

  bool get _checkedInToday {
    final DateTime? last = _lastCheckIn;
    if (last == null) {
      return false;
    }
    final DateTime now = DateTime.now();
    return last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
  }

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
    return AuthService.instance.currentUser?.firstName ?? 'there';
  }

  String _personaEmoji(String? userType) {
    switch (userType) {
      case 'Field Worker':
        return '🏕️';
      case 'Living Alone':
        return '👴';
      case 'Lone Worker':
        return '🏗️';
      case 'Traveller':
        return '✈️';
      case 'Journalist':
        return '📰';
      default:
        return '👤';
    }
  }

  String get _profileBadgeText {
    final String? userType = AuthService.instance.currentUser?.userType;
    final String typeLabel =
        (userType == null || userType.trim().isEmpty) ? 'SafeCheck user' : userType;
    return '$typeLabel · Check-in: ${_displayTime(_checkinTime)}';
  }

  String get _gracePeriodLabel {
    final int hours = _gracePeriod.inHours;
    final int minutes = _gracePeriod.inMinutes % 60;
    if (hours > 0 && minutes == 0) {
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    if (hours > 0) {
      return '$hours h $minutes m';
    }
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  String get _checkinHeadline {
    if (_checkedInToday) {
      return 'Checked in today';
    }
    if (_isCallDue) {
      return 'Check-in due now';
    }
    return 'Not checked in yet';
  }

  String get _checkinSubtext {
    return 'Due at ${_displayTime(_checkinTime)} · Grace period: $_gracePeriodLabel';
  }

  Future<void> _onCheckinCardTap() async {
    if (_isCallDue && !_checkedInToday) {
      await _simulateCallNow();
      return;
    }
    await _markSafe();
    if (mounted) {
      setState(() => _dayStreak += 1);
      unawaited(_hydrateStatusFromServer());
    }
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

  int get _shellBodyIndex {
    switch (_selectedNavIndex) {
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      default:
        return 0;
    }
  }

  @override
  void dispose() {
    if (NotificationService.onJourneyNotificationOpened != null) {
      NotificationService.onJourneyNotificationOpened = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? userType = AuthService.instance.currentUser?.userType;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _background,
      ),
      child: Theme(
        data: AppTheme.darkTheme.copyWith(
          scaffoldBackgroundColor: _background,
        ),
        child: Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: IndexedStack(
              index: _shellBodyIndex,
              children: <Widget>[
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildHeader(),
                            const SizedBox(height: 18),
                            _buildProfileBadge(userType),
                            const SizedBox(height: 24),
                            _buildCheckinCard(),
                            const SizedBox(height: 16),
                            _buildStatsRow(),
                            const SizedBox(height: 28),
                            _buildSectionLabel('QUICK ACTIONS'),
                            const SizedBox(height: 14),
                            _buildQuickActionsGrid(),
                            const SizedBox(height: 28),
                            _buildSectionLabel('RECENT ACTIVITY'),
                            const SizedBox(height: 14),
                            _buildRecentActivity(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const JourneyModeScreen(),
                HistoryScreen(onGoCheckIn: () => unawaited(_openCheckInScreen())),
                const ContactsScreen(),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomNav(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$_greeting,',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      _firstName,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Georgia',
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Settings',
          color: _cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (String value) {
            if (value == 'settings') {
              unawaited(_openSettings());
            } else if (value == 'logout') {
              unawaited(_logout());
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'settings',
              child: Text('Settings'),
            ),
            const PopupMenuItem<String>(
              value: 'logout',
              child: Text('Log out'),
            ),
          ],
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.settings_rounded, color: Colors.white70, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileBadge(String? userType) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            _personaEmoji(userType),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _profileBadgeText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onCheckinCardTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _checkinGreen,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'TODAY\'S CHECK-IN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: _accent.withValues(alpha: 0.95),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _checkinHeadline,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _checkinSubtext,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Text(
                      'Tap to confirm you\'re okay  →',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildStatCard(
            value: '$_dayStreak',
            label: 'day streak 🔥',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            value: '$_alertsTriggered',
            label: 'alerts triggered',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
        color: _accent.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: <Widget>[
        _buildQuickActionTile(
          icon: Icons.sos_rounded,
          label: 'SOS Panic',
          iconColor: const Color(0xFFEF4444),
          iconBackground: const Color(0xFFEF4444).withValues(alpha: 0.14),
          onTap: _openSosPanic,
        ),
        _buildQuickActionTile(
          icon: Icons.route_rounded,
          label: 'Journey mode',
          onTap: _openJourneyMode,
        ),
        _buildQuickActionTile(
          icon: Icons.phone_in_talk_outlined,
          label: 'Fake call',
          onTap: () => unawaited(_openFakeCall()),
        ),
        _buildQuickActionTile(
          icon: Icons.check_circle_outline_rounded,
          label: 'Check in',
          onTap: () => unawaited(_openCheckInScreen()),
        ),
        _buildQuickActionTile(
          icon: Icons.monitor_heart_outlined,
          label: 'View History',
          onTap: () => setState(() => _selectedNavIndex = 3),
        ),
        _buildQuickActionTile(
          icon: Icons.contact_emergency_outlined,
          label: 'My Contacts',
          onTap: () => setState(() => _selectedNavIndex = 4),
        ),
        _buildQuickActionTile(
          icon: Icons.description_outlined,
          label: 'Document Vault',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DocumentVaultScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? iconBackground,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground ?? _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? _accent,
                  size: 22,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final List<_ActivityItem> items = _activityItemsFromCheckins();

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(
          'No check-ins yet. Your activity will show up here.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.06),
                indent: 16,
                endIndent: 16,
              ),
            _buildActivityItem(items[i]),
          ],
        ],
      ),
    );
  }

  List<_ActivityItem> _activityItemsFromCheckins() {
    final List<_ActivityItem> items = <_ActivityItem>[];
    for (final Map<String, dynamic> checkin in _checkins.take(5)) {
      final DateTime? when = _parseEventTime(checkin);
      if (when == null) {
        continue;
      }
      final bool isLate = _isLateCheckin(when);
      final int graceUsed = isLate ? _graceMinutesUsed(when) : 0;
      items.add(
        _ActivityItem(
          title: isLate ? 'Checked in late' : 'Checked in',
          subtitle: isLate
              ? '${_formatActivityWhen(when)} · $graceUsed min grace used'
              : _formatActivityWhen(when),
          badgeLabel: isLate ? 'LATE' : 'SAFE',
          badgeColor: isLate ? const Color(0xFFFBBF24) : const Color(0xFF4ADE80),
          icon: isLate ? Icons.schedule_rounded : Icons.check_rounded,
          iconColor: isLate ? const Color(0xFFFBBF24) : const Color(0xFF4ADE80),
        ),
      );
    }
    return items;
  }

  bool _isLateCheckin(DateTime when) {
    final List<String> parts = _checkinTime.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final DateTime scheduled = DateTime(
      when.year,
      when.month,
      when.day,
      hour,
      minute,
    );
    return when.isAfter(scheduled);
  }

  int _graceMinutesUsed(DateTime when) {
    final List<String> parts = _checkinTime.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final DateTime scheduled = DateTime(
      when.year,
      when.month,
      when.day,
      hour,
      minute,
    );
    return when.difference(scheduled).inMinutes.clamp(0, _gracePeriod.inMinutes);
  }

  String _formatActivityWhen(DateTime when) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(when.year, when.month, when.day);
    final int dayDiff = today.difference(day).inDays;
    final String timeLabel = TimeOfDay.fromDateTime(when).format(context);

    if (dayDiff == 0) {
      return 'Today · $timeLabel';
    }
    if (dayDiff == 1) {
      return 'Yesterday · $timeLabel';
    }
    const List<String> weekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return '${weekdays[when.weekday - 1]} · $timeLabel';
  }

  Widget _buildActivityItem(_ActivityItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: item.badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: item.badgeColor.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              item.badgeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: item.badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF081221),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              _buildNavItem(
                index: 0,
                icon: SafeCheckNavIconType.home,
                label: 'Home',
              ),
              _buildNavItem(
                index: 1,
                icon: SafeCheckNavIconType.checkIn,
                label: 'Check In',
              ),
              _buildNavItem(
                index: 2,
                icon: SafeCheckNavIconType.journey,
                label: 'Journey',
              ),
              _buildNavItem(
                index: 3,
                icon: SafeCheckNavIconType.history,
                label: 'History',
              ),
              _buildNavItem(
                index: 4,
                icon: SafeCheckNavIconType.contacts,
                label: 'Contacts',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required SafeCheckNavIconType icon,
    required String label,
  }) {
    final bool selected = _selectedNavIndex == index;
    final Color color = selected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.42);

    return Expanded(
      child: InkWell(
        onTap: () => _onNavTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SafeCheckNavIcon(type: icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onNavTap(int index) async {
    if (index == 0 || index == 2 || index == 3 || index == 4) {
      setState(() => _selectedNavIndex = index);
      return;
    }
    if (index == 1) {
      await _openCheckInScreen();
    }
  }

  String _displayTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 18;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.badgeColor,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String subtitle;
  final String badgeLabel;
  final Color badgeColor;
  final IconData icon;
  final Color iconColor;
}
