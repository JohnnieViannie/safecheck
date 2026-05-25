import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/welcome_screen.dart';
import 'package:safecheck/screens/simulated_call_screen.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  SimulatedCallContext? pendingCallContext;
  String? pendingCallKitId;

  Future<void> attemptNavigateToPendingCall() async {
    if (pendingCallContext == null) return;
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null) return;

    final SimulatedCallContext contextData = pendingCallContext!;
    final String? callKitId = pendingCallKitId;
    pendingCallContext = null;
    pendingCallKitId = null;

    // Ensure Android incoming-call notification doesn't linger.
    if (callKitId != null && callKitId.isNotEmpty) {
      await FlutterCallkitIncoming.setCallConnected(callKitId);
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParams(id: callKitId),
      );
    }

    nav.push<SimulatedCallResult>(
      MaterialPageRoute<SimulatedCallResult>(
        builder: (_) => SimulatedCallScreen(
          contextData: contextData,
        ),
      ),
    );
  }

  // Required for reliably firing exact alarms on newer Android versions.
  if (Platform.isAndroid) {
    await Permission.scheduleExactAlarm.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  await AndroidAlarmManager.initialize();

  final String apiBaseUrl =
      await StorageService.instance.getApiBaseUrl() ?? Endpoints.baseUrl;
  ApiService.instance.init(url: apiBaseUrl);
  await AuthService.instance.loadSavedSession();

  await NotificationService.instance.initialize();

  // Server push + local alarms as soon as session exists.
  await PushCheckinService.instance.initialize();
  if (AuthService.instance.isLoggedIn) {
    await AlarmScheduler.instance.ensureAlarmsScheduled();
    await PushCheckinService.instance.registerTokenIfLoggedIn();
  }

  // CallKit permissions (Android full-screen + notification).
  if (Platform.isAndroid) {
    await FlutterCallkitIncoming.requestNotificationPermission(<String, dynamic>{
      'title': 'SafeCheck Call Alerts',
      'rationaleMessagePermission':
          'SafeCheck needs permission to show incoming call screens.',
      'postNotificationMessageRequired':
          'SafeCheck needs notification permission to show call alerts.',
    });

    final bool? canFullScreen = await FlutterCallkitIncoming.canUseFullScreenIntent();
    if (canFullScreen == true) {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    }
  }

  // Handle CallKit actions even when the app UI is not currently visible.
  final Set<String> handledCallKitIds = <String>{};

  WidgetsBinding.instance.addObserver(
    _CallNavigationObserver(
      onResumed: () async {
        await attemptNavigateToPendingCall();
      },
    ),
  );

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

    // De-dupe by CallKit id.
    if (callKitId != null && handledCallKitIds.contains(callKitId)) {
      return;
    }

    switch (event.event) {
      case Event.actionCallAccept:
        if (callKitId != null) handledCallKitIds.add(callKitId);

        final int? alarmId = int.tryParse(
          (body['alarmId']?.toString() ?? extra['alarmId']?.toString() ?? ''),
        );
        final bool isSnoozedRetry = alarmId == 1;

        final DateTime scheduledFor = DateTime.tryParse(
              body['scheduledFor']?.toString() ??
                  extra['scheduledFor']?.toString() ??
                  '',
            ) ??
            DateTime.now();
        final String frequency = (body['frequency']?.toString() ??
                extra['frequency']?.toString() ??
                'Daily')
            .toString();

        final SimulatedCallContext contextData = SimulatedCallContext(
          callerName: 'SafeCheck',
          userDisplayName:
              AuthService.instance.currentUser?.displayIdentifier ?? 'User',
          scheduledFor: scheduledFor,
          frequency: frequency,
          reason: 'Routine safety check-in call',
          isSnoozedRetry: isSnoozedRetry,
        );

        // If we get the event while the navigator isn't ready (e.g. user
        // tapped "Answer" on the notification bar), store it and navigate
        // on `resumed`.
        final NavigatorState? nav = navigatorKey.currentState;
        if (nav == null) {
          pendingCallContext = contextData;
          pendingCallKitId = callKitId;
          await attemptNavigateToPendingCall();
          break;
        }

        // Mark call connected and hide Android incoming-call notification
        // so it doesn't persist after answering.
        if (callKitId != null && callKitId.isNotEmpty) {
          await FlutterCallkitIncoming.setCallConnected(callKitId);
          await FlutterCallkitIncoming.hideCallkitIncoming(
            CallKitParams(id: callKitId),
          );
        }

        nav.push<SimulatedCallResult>(
          MaterialPageRoute<SimulatedCallResult>(
            builder: (_) => SimulatedCallScreen(
              contextData: contextData,
            ),
          ),
        );
        break;

      case Event.actionCallDecline:
        if (callKitId != null) handledCallKitIds.add(callKitId);

        final String? uid = AuthService.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return;

        // Ensure Android incoming-call notification doesn't linger.
        if (callKitId != null && callKitId.isNotEmpty) {
          await FlutterCallkitIncoming.hideCallkitIncoming(
            CallKitParams(id: callKitId),
          );
        }

        await SafetyService.instance.escalateMissedOrDeclined(
          uid: uid,
          reason: 'declined',
        );
        break;

      case Event.actionCallTimeout:
        if (callKitId != null) handledCallKitIds.add(callKitId);

        final String? uid = AuthService.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return;

        if (callKitId != null && callKitId.isNotEmpty) {
          await FlutterCallkitIncoming.hideCallkitIncoming(
            CallKitParams(id: callKitId),
          );
        }

        await SafetyService.instance.escalateMissedOrDeclined(
          uid: uid,
          reason: 'no_answer',
        );
        break;

      default:
        break;
    }
  });

  runApp(SafeCheckApp(navigatorKey: navigatorKey));
}

class _CallNavigationObserver extends WidgetsBindingObserver {
  _CallNavigationObserver({required this.onResumed});

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Don't block lifecycle handling; we can navigate on the next frame.
      unawaited(onResumed());
    }
  }
}

class SafeCheckApp extends StatelessWidget {
  const SafeCheckApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeBangle',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: AuthService.instance.authStateChanges,
      // Use the synchronous getter as initialData so we never get stuck
      // on ConnectionState.waiting when the event was already emitted
      // before this StreamBuilder subscribed (broadcast stream race condition).
      initialData: AuthService.instance.isLoggedIn,
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return const HomeScreen();
        }
        return const WelcomeScreen();
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
