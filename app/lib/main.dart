import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:safecheck/screens/alert_triggered_screen.dart';
import 'package:safecheck/screens/checkin_flow.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/screens/splash_screen.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/pending_call_service.dart';
import 'package:safecheck/services/ringtone_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/biometric_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/theme.dart';
import 'package:safecheck/widgets/biometric_lock_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool callScreenVisible = false;

  Future<void> handleCallResult(
    SimulatedCallResult? result, {
    DateTime? missedCheckinAt,
  }) async {
    callScreenVisible = false;
    await RingtoneService.stopAll();
    await NotificationService.instance.cancelIncomingCheckinCall();

    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || result == null) {
      return;
    }

    switch (result.action) {
      case SimulatedCallAction.safeConfirmed:
        await StorageService.instance.saveLastCheckIn(DateTime.now());
        await SafetyService.instance.confirmSafe(uid: uid);
        await SafetyService.instance.createCheckin(
          uid: uid,
          status: 'safe_confirmed',
        );
        await StorageService.instance.clearSnoozedUntil();
        unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
        unawaited(AlarmScheduler.instance.cancelRetryAlarms());
        break;
      case SimulatedCallAction.remindMe:
        if (result.snoozedUntil != null) {
          await StorageService.instance.saveSnoozedUntil(result.snoozedUntil!);
          await AlarmScheduler.instance.scheduleSnoozeAlarm(result.snoozedUntil!);
          await SafetyService.instance.syncSnooze(
            uid: uid,
            snoozedUntil: result.snoozedUntil!,
          );
        }
        break;
      case SimulatedCallAction.declined:
        await StorageService.instance.clearSnoozedUntil();
        unawaited(AlarmScheduler.instance.cancelSnoozeAlarm());
        final String reason = result.note?.toString() ?? 'declined';
        if (reason == 'cancelled_by_pin') {
          await SafetyService.instance.logTimelineEvent(
            uid: uid,
            eventType: 'alert_cancelled_by_pin',
            status: 'cancelled',
          );
          break;
        }
        final bool escalated = await SafetyService.instance.escalateMissedOrDeclined(
          uid: uid,
          reason: reason == 'grace_expired' ? 'no_answer' : reason,
        );
        if (escalated) {
          final NavigatorState? nav = navigatorKey.currentState;
          if (nav != null) {
            await AlertTriggeredScreen.show(
              nav.context,
              missedCheckinAt: missedCheckinAt ?? DateTime.now(),
            );
          }
        }
        break;
      case SimulatedCallAction.messageSent:
        break;
    }
  }

  Future<void> attemptNavigateToPendingCall() async {
    if (callScreenVisible) return;

    final PendingCallPayload? payload =
        await PendingCallService.instance.load();
    if (payload == null) return;

    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null) return;

    callScreenVisible = true;
    await RingtoneService.stopAll();
    await NotificationService.instance.cancelIncomingCheckinCall();
    await PendingCallService.instance.clear();

    final SimulatedCallContext contextData = SimulatedCallContext(
      callerName: 'SafeCheck',
      userDisplayName:
          AuthService.instance.currentUser?.displayIdentifier ?? 'User',
      scheduledFor: payload.scheduledFor,
      frequency: payload.frequency,
      reason: 'Routine safety check-in call',
      isSnoozedRetry: payload.isSnoozedRetry,
    );

    final Duration gracePeriod = await StorageService.instance.getGracePeriod();

    final SimulatedCallResult? result = await pushCheckinFlow(
      nav.context,
      contextData: contextData,
      gracePeriod: gracePeriod,
    );
    await handleCallResult(result, missedCheckinAt: payload.scheduledFor);
  }

  ApiService.instance.init(url: Endpoints.baseUrl);
  await AuthService.instance.loadSavedSession();

  NotificationService.onIncomingCallOpened = () {
    unawaited(attemptNavigateToPendingCall());
  };

  WidgetsBinding.instance.addObserver(
    _CallNavigationObserver(
      onResumed: () async {
        await OfflineSyncService.instance.flush();
        await attemptNavigateToPendingCall();
      },
    ),
  );

  // iOS FCM may still use CallKit; Android uses pending call + check-in flow.
  if (Platform.isIOS) {
    final Set<String> handledCallKitIds = <String>{};

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      final dynamic rawBody = event.body;
      final Map<String, dynamic> body =
          rawBody is Map<String, dynamic> ? rawBody : <String, dynamic>{};

      final Map<String, dynamic> extra =
          body['extra'] is Map<String, dynamic>
              ? body['extra'] as Map<String, dynamic>
              : <String, dynamic>{};

      final String? callKitId =
          body['callKitId']?.toString() ?? extra['callKitId']?.toString();
      final String source =
          extra['source']?.toString() ?? body['source']?.toString() ?? '';

      if (source != 'fcm') return;
      if (callKitId != null && handledCallKitIds.contains(callKitId)) {
        return;
      }

      switch (event.event) {
        case Event.actionCallAccept:
          if (callKitId != null) handledCallKitIds.add(callKitId);

          await PendingCallService.instance.save(
            PendingCallPayload(
              callKitId: callKitId ?? '',
              scheduledFor: DateTime.tryParse(
                    extra['scheduledFor']?.toString() ?? '',
                  ) ??
                  DateTime.now(),
              frequency: extra['frequency']?.toString() ?? 'Daily',
              checkinTime: extra['checkinTime']?.toString() ?? '18:00',
              alarmId: int.tryParse(extra['alarmId']?.toString() ?? '') ?? 0,
              source: 'fcm',
            ),
          );

          if (callKitId != null && callKitId.isNotEmpty) {
            await FlutterCallkitIncoming.setCallConnected(callKitId);
            await FlutterCallkitIncoming.hideCallkitIncoming(
              CallKitParams(id: callKitId),
            );
          }

          await attemptNavigateToPendingCall();
          break;

        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          if (callKitId != null) handledCallKitIds.add(callKitId);
          await RingtoneService.stopAll();
          await PendingCallService.instance.clear();

          if (callKitId != null && callKitId.isNotEmpty) {
            await FlutterCallkitIncoming.hideCallkitIncoming(
              CallKitParams(id: callKitId),
            );
          }

          final String? uid = AuthService.instance.currentUser?.uid;
          if (uid == null || uid.isEmpty) return;

          await SafetyService.instance.escalateMissedOrDeclined(
            uid: uid,
            reason: event.event == Event.actionCallDecline
                ? 'declined'
                : 'no_answer',
          );
          break;

        default:
          break;
      }
    });
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(attemptNavigateToPendingCall());
  });

  runApp(SafeCheckApp(navigatorKey: navigatorKey));
}

class _CallNavigationObserver extends WidgetsBindingObserver {
  _CallNavigationObserver({required this.onResumed});

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResumed());
    }
  }
}

class SafeCheckApp extends StatefulWidget {
  const SafeCheckApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<SafeCheckApp> createState() => _SafeCheckAppState();
}

class _SafeCheckAppState extends State<SafeCheckApp> with WidgetsBindingObserver {
  bool _locked = false;
  bool _unlockBusy = false;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _maybeRequireUnlock() async {
    final bool enabled = await BiometricService.instance.isEnabled();
    if (!BiometricLockSession.shouldPrompt(
      enabled: enabled,
      loggedIn: AuthService.instance.isLoggedIn,
    )) {
      if (mounted && _locked) {
        setState(() {
          _locked = false;
          _unlockError = null;
        });
      }
      return;
    }

    BiometricLockSession.recordPrompt();
    await _attemptUnlock(showOverlayOnFailure: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      BiometricLockSession.onAppPaused();
      return;
    }
    if (state == AppLifecycleState.resumed &&
        BiometricLockSession.needsUnlockAfterPause) {
      unawaited(_maybeRequireUnlock());
    }
  }

  Future<void> _turnOffBiometricLock() async {
    await BiometricService.instance.setEnabled(false);
    BiometricLockSession.markUnlocked();
    if (!mounted) return;
    setState(() {
      _locked = false;
      _unlockBusy = false;
      _unlockError = null;
    });
  }

  Future<void> _attemptUnlock({bool showOverlayOnFailure = false}) async {
    if (_unlockBusy) return;

    if (!mounted) return;
    setState(() {
      _unlockBusy = true;
      _unlockError = null;
    });

    // Let the current frame finish so the system biometric sheet can appear.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final BiometricAuthResult result =
        await BiometricService.instance.authenticate(
      reason: 'Unlock SafeCheck',
      biometricOnly: false,
    );

    if (!mounted) return;
    setState(() {
      _unlockBusy = false;
      if (result.success) {
        BiometricLockSession.markUnlocked();
        _locked = false;
        _unlockError = null;
      } else {
        _unlockError = result.errorMessage;
        if (showOverlayOnFailure) {
          _locked = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeCheck',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: widget.navigatorKey,
      home: const SplashScreen(),
      builder: (BuildContext context, Widget? child) {
        return Stack(
          children: <Widget>[
            if (child != null) child,
            if (_locked)
              Positioned.fill(
                child: BiometricLockOverlay(
                  onUnlock: () => _attemptUnlock(showOverlayOnFailure: true),
                  onTurnOffLock: _turnOffBiometricLock,
                  errorMessage: _unlockError,
                  busy: _unlockBusy,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shown when Firebase cannot start (missing/invalid [firebase_options.dart] or config).
class FirebaseInitErrorApp extends StatelessWidget {
  const FirebaseInitErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('SafeCheck')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.cloud_off, size: 56, color: Color(0xFF2E7D32)),
                const SizedBox(height: 16),
                const Text(
                  'Firebase is not configured yet',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The app needs Firebase options to start. From your project folder run:',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                const SelectableText(
                  'dart pub global activate flutterfire_cli\nflutterfire configure',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Or copy apiKey, appId, projectId, etc. from Firebase Console into lib/firebase_options.dart.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 20),
                Text(
                  'Details: $message',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
