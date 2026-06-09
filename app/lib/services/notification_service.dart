import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'dart:convert';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'dart:async';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        unawaited(_handleNotificationTap(details));
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Needed for `zonedSchedule` on iOS/Android.
    tzdata.initializeTimeZones();
  }

  static const String alarmRingChannelId = 'safecheck_alarm_ring_channel';

  static Future<void> _ensureAlarmRingChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final AndroidFlutterLocalNotificationsPlugin? android = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      alarmRingChannelId,
      'SafeCheck Alarm Ring',
      description: 'Loud check-in alarms that wake the phone',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await android.createNotificationChannel(channel);
  }

  /// Fallback when CallKit cannot start from the AlarmManager background isolate.
  @pragma('vm:entry-point')
  static Future<void> showBackgroundIncomingCallFallback() async {
    await ensureBackgroundAlarmIsolateReady();
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await _ensureAlarmRingChannel(plugin);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      alarmRingChannelId,
      'SafeCheck Alarm Ring',
      channelDescription: 'Loud check-in alarms that wake the phone',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentSound: true,
      ),
    );
    await plugin.show(
      1999,
      'SafeCheck',
      'Check-in call — tap to answer',
      details,
    );
  }

  Future<void> showCheckInReminder() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safecheck_channel',
      'SafeCheck Reminders',
      channelDescription: 'Reminders for safety check-ins',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      1001,
      'SafeCheck',
      'Hi — just your SafeCheck. Tap to confirm you\'re okay.',
      details,
    );
  }

  /// Schedules a single check-in notification (iOS + Android).
  ///
  /// `when` can be in local time; it will be converted to UTC internally.
  Future<void> scheduleCheckInNotification({
    required int notificationId,
    required DateTime when,
    required bool snoozed,
    required String callKitId,
    required String scheduledForIso,
    required String frequency,
    required String checkinTime,
  }) async {
    final DateTime whenUtc = when.toUtc();

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
    );

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safecheck_alarm_channel',
      'SafeCheck Alarms',
      channelDescription: 'Full-screen check-in alarms',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final String body = snoozed
        ? 'Time to confirm you are safe (snoozed).'
        : 'Time to confirm you are safe.';

    final Map<String, dynamic> payloadMap = <String, dynamic>{
      'type': 'dueCallRequest',
      'callKitId': callKitId,
      'snoozed': snoozed,
      'scheduledFor': scheduledForIso,
      'frequency': frequency,
      'checkinTime': checkinTime,
    };
    final String payload = jsonEncode(payloadMap);

    await _plugin.zonedSchedule(
      notificationId,
      'SafeCheck',
      body,
      tz.TZDateTime.from(whenUtc, tz.UTC),
      notificationDetails,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelCheckInNotification(int notificationId) async {
    await _plugin.cancel(notificationId);
  }

  Future<void> _handleNotificationTap(NotificationResponse details) async {
    final String? rawPayload = details.payload;
    if (rawPayload == null || rawPayload.isEmpty) return;

    final Map<String, dynamic> payload = jsonDecode(rawPayload) as Map<String, dynamic>;
    if (payload['type']?.toString() != 'dueCallRequest') return;

    final String callKitId = payload['callKitId']?.toString() ??
        '00000000-0000-0000-0000-000000000010';
    final String frequency = payload['frequency']?.toString() ?? 'Daily';
    final String checkinTime = payload['checkinTime']?.toString() ?? '18:00';
    final bool snoozed = payload['snoozed'] == true;
    final DateTime scheduledFor = DateTime.tryParse(
          payload['scheduledFor']?.toString() ?? '',
        ) ??
        DateTime.now();

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
        'alarmId': snoozed ? 1 : 0,
        'callKitId': callKitId,
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
}
