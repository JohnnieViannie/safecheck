import 'dart:async';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/alarm_watchdog.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/background_location_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/storage_service.dart';

/// Heavy startup work deferred until after the splash screen is visible.
class AppBootstrap {
  AppBootstrap._();

  static bool _started = false;

  static void startDeferredInit({required bool loggedIn}) {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_run(loggedIn: loggedIn));
  }

  static Future<void> _run({required bool loggedIn}) async {
    await AndroidAlarmManager.initialize();

    final String apiBaseUrl =
        await StorageService.instance.getApiBaseUrl() ?? Endpoints.baseUrl;
    ApiService.instance.init(url: apiBaseUrl);

    await NotificationService.instance.initialize();
    await PushCheckinService.instance.initialize();

    if (loggedIn) {
      await AlarmScheduler.instance.ensureAlarmsScheduled();
      await PushCheckinService.instance.registerTokenIfLoggedIn();
      await BackgroundLocationService.instance.pingIfDue();
      AlarmWatchdog.instance.attach();
    }

    if (Platform.isAndroid) {
      await FlutterCallkitIncoming.requestNotificationPermission(
        <String, dynamic>{
          'title': 'SafeCheck Call Alerts',
          'rationaleMessagePermission':
              'SafeCheck needs permission to show incoming call screens.',
          'postNotificationMessageRequired':
              'SafeCheck needs notification permission to show call alerts.',
        },
      );

      final bool? canFullScreen =
          await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (canFullScreen == true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    }
  }
}
