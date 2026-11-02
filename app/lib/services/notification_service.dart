import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:safecheck/services/pending_call_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'dart:convert';
import 'dart:async';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set from [main] when user should open journey mode from a notification.
  static void Function(String type, String? journeyId)? onJourneyNotificationOpened;

  /// Set from [main] to open the check-in flow when user taps a notification.
  static void Function()? onIncomingCallOpened;

  static const int incomingCallNotificationId = 1999;
  static const int onboardingTestNotificationId = 1002;
  static const String incomingCallChannelId = 'safecheck_incoming_call_channel';
  static const String onboardingTestChannelId = 'safecheck_onboarding_test_channel';
  static const String reminderChannelId = 'safecheck_reminder_channel';
  static const String journeyChannelId = 'safecheck_journey_channel';
  static const int journeyArrivalNotificationId = 4100;
  static const int journeyCheckinNotificationBaseId = 4101;

  static bool _timezoneConfigured = false;

  static Future<void> _configureLocalTimezone() async {
    if (_timezoneConfigured) {
      return;
    }
    tzdata.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'UTC',
      );
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _timezoneConfigured = true;
  }

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
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    tzdata.initializeTimeZones();
    await _configureLocalTimezone();
    await _ensureIncomingCallChannel(_plugin);
    await _ensureReminderChannel(_plugin);
    await _ensureJourneyChannel(_plugin);

    final NotificationAppLaunchDetails? launchDetails =
        await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final NotificationResponse? response = launchDetails?.notificationResponse;
      if (response != null) {
        await _handleNotificationTap(response);
      }
    }
  }

  static Future<void> _ensureIncomingCallChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final AndroidFlutterLocalNotificationsPlugin? android = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      incomingCallChannelId,
      'SafeCheck Incoming Calls',
      description: 'Incoming safety check-in calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await android.createNotificationChannel(channel);
  }

  static Future<void> _ensureReminderChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final AndroidFlutterLocalNotificationsPlugin? android = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      reminderChannelId,
      'SafeCheck Reminders',
      description: 'Daily check-in reminders',
      importance: Importance.defaultImportance,
    );
    await android.createNotificationChannel(channel);
  }

  static Future<void> _ensureJourneyChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final AndroidFlutterLocalNotificationsPlugin? android = plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      journeyChannelId,
      'SafeCheck Journey',
      description: 'Journey mode reminders and arrival alerts',
      importance: Importance.high,
    );
    await android.createNotificationChannel(channel);
  }

  static Map<String, dynamic> _incomingCallPayload({
    required String callKitId,
    required DateTime scheduledFor,
    required String frequency,
    required String checkinTime,
    required int alarmId,
    required bool snoozed,
    required String source,
  }) {
    return <String, dynamic>{
      'type': 'incomingCheckinCall',
      'callKitId': callKitId,
      'scheduledFor': scheduledFor.toIso8601String(),
      'frequency': frequency,
      'checkinTime': checkinTime,
      'alarmId': alarmId,
      'snoozed': snoozed,
      'source': source,
    };
  }

  static NotificationDetails _incomingCallDetails() {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      incomingCallChannelId,
      'SafeCheck Incoming Calls',
      channelDescription: 'Incoming safety check-in calls',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    );
    return const NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentSound: true,
      ),
    );
  }

  /// Shows full-screen incoming call notification (AlarmManager / FCM background).
  @pragma('vm:entry-point')
  static Future<void> showIncomingCheckinCallBackground({
    required String callKitId,
    required DateTime scheduledFor,
    required String frequency,
    required String checkinTime,
    required int alarmId,
    required bool snoozed,
    required String source,
  }) async {
    await ensureBackgroundAlarmIsolateReady();
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
    await _ensureIncomingCallChannel(plugin);

    final String payload = jsonEncode(
      _incomingCallPayload(
        callKitId: callKitId,
        scheduledFor: scheduledFor,
        frequency: frequency,
        checkinTime: checkinTime,
        alarmId: alarmId,
        snoozed: snoozed,
        source: source,
      ),
    );

    await plugin.show(
      incomingCallNotificationId,
      'SafeCheck',
      'Incoming safety check-in — tap to answer',
      _incomingCallDetails(),
      payload: payload,
    );
  }

  Future<void> showIncomingCheckinCall({
    required String callKitId,
    required DateTime scheduledFor,
    required String frequency,
    required String checkinTime,
    required int alarmId,
    required bool snoozed,
    required String source,
  }) async {
    final String payload = jsonEncode(
      _incomingCallPayload(
        callKitId: callKitId,
        scheduledFor: scheduledFor,
        frequency: frequency,
        checkinTime: checkinTime,
        alarmId: alarmId,
        snoozed: snoozed,
        source: source,
      ),
    );

    await _plugin.show(
      incomingCallNotificationId,
      'SafeCheck',
      'Incoming safety check-in — tap to answer',
      _incomingCallDetails(),
      payload: payload,
    );
  }

  Future<void> cancelIncomingCheckinCall() async {
    await _plugin.cancel(incomingCallNotificationId);
  }

  /// Legacy fallback name kept for alarm callback error path.
  @pragma('vm:entry-point')
  static Future<void> showBackgroundIncomingCallFallback() async {
    await showIncomingCheckinCallBackground(
      callKitId: 'fallback-${DateTime.now().millisecondsSinceEpoch}',
      scheduledFor: DateTime.now(),
      frequency: 'Daily',
      checkinTime: '18:00',
      alarmId: 0,
      snoozed: false,
      source: 'local_alarm',
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

  Future<void> showOnboardingTestNotification() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        onboardingTestChannelId,
        'SafeCheck Tests',
        description: 'Onboarding test notifications',
        importance: Importance.high,
      );
      await android.createNotificationChannel(channel);
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      onboardingTestChannelId,
      'SafeCheck Tests',
      channelDescription: 'Onboarding test notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(
        'Hi — Just your daily SafeCheck. Tap to confirm you\'re okay.',
      ),
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        subtitle: 'Safebangle • SafeCheck • TEST ONLY',
      ),
    );
    await _plugin.show(
      onboardingTestNotificationId,
      'Are you okay?',
      'Hi — Just your daily SafeCheck. Tap to confirm you\'re okay.',
      details,
      payload: jsonEncode(<String, dynamic>{'type': 'onboardingTest'}),
    );
  }

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
      category: AndroidNotificationCategory.call,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final String body = snoozed
        ? 'Time to confirm you are safe (snoozed).'
        : 'Time to confirm you are safe.';

    final Map<String, dynamic> payloadMap = <String, dynamic>{
      'type': 'incomingCheckinCall',
      'callKitId': callKitId,
      'snoozed': snoozed,
      'scheduledFor': scheduledForIso,
      'frequency': frequency,
      'checkinTime': checkinTime,
      'alarmId': snoozed ? 1 : 0,
      'source': 'scheduled_notification',
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

  static const int dailyReminderNotificationId = 1998;

  Future<void> scheduleDailyReminder({
    required bool enabled,
    required String checkinTimeHHmm,
  }) async {
    await _configureLocalTimezone();
    await _ensureReminderChannel(_plugin);
    await _plugin.cancel(dailyReminderNotificationId);
    if (!enabled) {
      return;
    }

    final List<String> parts = checkinTimeHHmm.split(':');
    final int hour = int.tryParse(parts.first) ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final DateTime now = DateTime.now();
    DateTime when = DateTime(now.year, now.month, now.day, hour, minute)
        .subtract(const Duration(minutes: 30));
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      reminderChannelId,
      'SafeCheck Reminders',
      channelDescription: 'Daily check-in reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      when.year,
      when.month,
      when.day,
      when.hour,
      when.minute,
    );

    await _plugin.zonedSchedule(
      dailyReminderNotificationId,
      'SafeCheck',
      'Check-in reminder: 30 minutes until your scheduled check-in.',
      scheduled,
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: jsonEncode(<String, dynamic>{'type': 'dailyReminder'}),
    );
  }

  Future<void> cancelCheckInNotification(int notificationId) async {
    await _plugin.cancel(notificationId);
  }

  Future<void> scheduleJourneyNotifications({
    required String journeyId,
    required DateTime startedAt,
    required DateTime expectedArrivalAt,
    required String checkinFrequency,
  }) async {
    await cancelJourneyNotifications();
    await _configureLocalTimezone();

    await _scheduleJourneyNotification(
      id: journeyArrivalNotificationId,
      when: expectedArrivalAt,
      body: 'Expected arrival time reached. Confirm you arrived safely.',
      payload: <String, dynamic>{
        'type': 'journeyArrivalMissed',
        'journeyId': journeyId,
      },
    );

    final int intervalMinutes = switch (checkinFrequency) {
      '30' => 30,
      '60' => 60,
      _ => 0,
    };
    if (intervalMinutes <= 0) {
      return;
    }

    DateTime next = startedAt.add(Duration(minutes: intervalMinutes));
    for (int slot = 0;
        slot < 8 && next.isBefore(expectedArrivalAt);
        slot++) {
      await _scheduleJourneyNotification(
        id: journeyCheckinNotificationBaseId + slot,
        when: next,
        body: 'Mid-journey check-in — tap to confirm you\'re okay.',
        payload: <String, dynamic>{
          'type': 'journeyCheckin',
          'journeyId': journeyId,
        },
      );
      next = next.add(Duration(minutes: intervalMinutes));
    }
  }

  Future<void> _scheduleJourneyNotification({
    required int id,
    required DateTime when,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    if (!when.isAfter(DateTime.now())) {
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      journeyChannelId,
      'SafeCheck Journey',
      channelDescription: 'Journey mode reminders and arrival alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id,
      'SafeCheck Journey',
      body,
      tz.TZDateTime.from(when.toUtc(), tz.UTC),
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode(payload),
    );
  }

  Future<void> cancelJourneyNotifications() async {
    await _plugin.cancel(journeyArrivalNotificationId);
    for (int i = 0; i < 8; i++) {
      await _plugin.cancel(journeyCheckinNotificationBaseId + i);
    }
  }

  Future<void> _handleNotificationTap(NotificationResponse details) async {
    final String? rawPayload = details.payload;
    if (rawPayload == null || rawPayload.isEmpty) return;

    final Map<String, dynamic> payload =
        jsonDecode(rawPayload) as Map<String, dynamic>;
    final String? type = payload['type']?.toString();
    if (type == 'dailyReminder') {
      return;
    }
    if (type == 'journeyArrivalMissed' || type == 'journeyCheckin') {
      onJourneyNotificationOpened?.call(
        type!,
        payload['journeyId']?.toString(),
      );
      return;
    }
    if (type != 'incomingCheckinCall' && type != 'dueCallRequest') {
      return;
    }

    await PendingCallService.instance.save(
      PendingCallPayload(
        callKitId: payload['callKitId']?.toString() ?? '',
        scheduledFor: DateTime.tryParse(
              payload['scheduledFor']?.toString() ?? '',
            ) ??
            DateTime.now(),
        frequency: payload['frequency']?.toString() ?? 'Daily',
        checkinTime: payload['checkinTime']?.toString() ?? '18:00',
        alarmId: int.tryParse(payload['alarmId']?.toString() ?? '') ??
            (payload['snoozed'] == true ? 1 : 0),
        source: payload['source']?.toString() ?? 'scheduled_notification',
      ),
    );

    onIncomingCallOpened?.call();
  }
}
