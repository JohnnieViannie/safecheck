import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:safecheck/firebase_options.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/auth_service.dart';
import 'package:safecheck/utils/app_log.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:safecheck/services/call_dedup_service.dart';
import 'package:safecheck/services/endpoints.dart';

/// Handles server-driven FCM pushes that wake the app for check-in calls.
class PushCheckinService {
  PushCheckinService._();

  static final PushCheckinService instance = PushCheckinService._();

  final Set<String> _handledCallKitIds = <String>{};
  bool _initialized = false;

  static Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await handleRemoteMessage(message, fromBackground: true);
  }

  static Future<void> handleRemoteMessage(
    RemoteMessage message, {
    bool fromBackground = false,
  }) async {
    final Map<String, dynamic> data = message.data;
    if (data['type']?.toString() != 'checkin_call') {
      return;
    }

    if (fromBackground) {
      await ensureBackgroundAlarmIsolateReady();
    }

    final String callKitId = data['callKitId']?.toString() ?? '';
    if (callKitId.isEmpty) {
      return;
    }

    final String frequency = data['frequency']?.toString() ?? 'Daily';
    final String checkinTime = data['checkinTime']?.toString() ?? '18:00';
    final bool snoozed = data['snoozed']?.toString() == 'true';
    final int alarmId =
        int.tryParse(data['alarmId']?.toString() ?? '') ?? (snoozed ? 1 : 0);
    final DateTime scheduledFor = DateTime.tryParse(
          data['scheduledFor']?.toString() ?? '',
        ) ??
        DateTime.now();

    final bool show = await CallDedupService.instance.shouldShowCall(
      callKitId: callKitId,
      scheduledFor: scheduledFor,
    );
    if (!show) return;

    if (fromBackground) {
      try {
        await FlutterRingtonePlayer().playAlarm();
      } catch (_) {}
    }

    final CallKitParams params = CallKitParams(
      id: callKitId,
      nameCaller: 'SafeCheck',
      handle: 'SafeCheck',
      type: 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      callingNotification: const NotificationParams(
        showNotification: false,
        isShowCallback: true,
        subtitle: 'Calling...',
        callbackText: 'Hang Up',
      ),
      extra: <String, dynamic>{
        'scheduledFor': scheduledFor.toIso8601String(),
        'frequency': frequency,
        'checkinTime': checkinTime,
        'alarmId': alarmId,
        'callKitId': callKitId,
        'source': 'fcm',
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        ringtonePath: 'system_ringtone_default',
        incomingCallNotificationChannelName: 'Incoming call',
        missedCallNotificationChannelName: 'Missed call',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        handleType: 'generic',
        audioSessionMode: 'default',
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
        iconName: 'CallKitLogo',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> initialize() async {
    if (_initialized || !DefaultFirebaseOptions.isConfigured) {
      return;
    }

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (_handledCallKitIds.contains(message.data['callKitId']?.toString())) {
        return;
      }
      final String? id = message.data['callKitId']?.toString();
      if (id != null && id.isNotEmpty) {
        _handledCallKitIds.add(id);
      }
      await handleRemoteMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await handleRemoteMessage(message);
    });

    _initialized = true;
    await registerTokenIfLoggedIn();
  }

  Future<void> registerTokenIfLoggedIn() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      return;
    }
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }

    try {
      if (!_initialized) {
        await initialize();
      }

      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      final String? token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        return;
      }

      final String platform = defaultTargetPlatform.name;
      final response = await ApiService.instance.post(
        Endpoints.registerPushToken,
        body: <String, dynamic>{
          'uid': uid,
          'fcm_token': token,
          'platform': platform,
        },
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        appLog('register-push failed: ${response.statusCode} ${response.body}');
      }

      messaging.onTokenRefresh.listen((String newToken) async {
        await ApiService.instance.post(
          Endpoints.registerPushToken,
          body: <String, dynamic>{
            'uid': uid,
            'fcm_token': newToken,
            'platform': platform,
          },
        );
      });
    } catch (error) {
      appLog('FCM registerTokenIfLoggedIn error: $error');
    }
  }

  Future<void> unregisterTokenIfLoggedIn() async {
    final String? uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    try {
      await ApiService.instance.post(
        Endpoints.unregisterPushToken,
        body: <String, dynamic>{'uid': uid},
      );
    } catch (error) {
      appLog('FCM unregister error: $error');
    }
  }
}
