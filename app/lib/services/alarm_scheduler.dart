import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safecheck/services/alarm_ids.dart';
import 'package:safecheck/services/alarm_schedule_logic.dart';
import 'package:safecheck/services/checkin_alarm_background.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/storage_service.dart';

/// Schedules check-in alarms using Android AlarmManager (rolling window +
/// heartbeat + grace retries) or iOS local notifications.
class AlarmScheduler {
  AlarmScheduler._();

  static final AlarmScheduler instance = AlarmScheduler._();

  static const int iosRegularNotificationBaseId = 2100;
  static const int iosSnoozeNotificationId = 2101;

  String _uuidFromSeed(int seed) {
    final String hex = seed.toRadixString(16).padLeft(32, '0').substring(0, 32);
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  String _callKitIdForWhen(DateTime when, {required bool snoozed}) {
    final int kindSeed = snoozed ? 1 : 0;
    final int seed = when.millisecondsSinceEpoch ^ (kindSeed * 0x9e3779b9);
    return _uuidFromSeed(seed);
  }

  /// Returns false when exact alarms cannot be scheduled (Android 12+).
  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    final PermissionStatus status = await Permission.scheduleExactAlarm.status;
    return status.isGranted;
  }

  Future<void> ensureAlarmsScheduled() async {
    if (Platform.isAndroid && !await canScheduleExactAlarms()) {
      return;
    }

    await scheduleNextRegularAlarm();

    if (!Platform.isAndroid) return;

    final DateTime? snoozed = await StorageService.instance.getSnoozedUntil();
    if (snoozed != null && snoozed.isAfter(DateTime.now())) {
      await scheduleSnoozeAlarm(snoozed);
    }
  }

  Future<void> scheduleNextRegularAlarm() async {
    final String checkinTime =
        (await StorageService.instance.getCheckinTime()) ?? '18:00';
    final String frequency = await StorageService.instance.getCheckinFrequency();
    final DateTime now = DateTime.now();

    if (Platform.isAndroid) {
      await _scheduleAndroidAlarms(
        now: now,
        checkinTime: checkinTime,
        frequency: frequency,
      );
      return;
    }

    if (Platform.isIOS) {
      await _scheduleIosRegularNotifications(
        now: now,
        checkinTime: checkinTime,
        frequency: frequency,
      );
    }
  }

  Future<void> _scheduleAndroidAlarms({
    required DateTime now,
    required String checkinTime,
    required String frequency,
  }) async {
    await _cancelAndroidManagedAlarms(frequency);

    final int horizon = AlarmIds.horizonForFrequency(frequency);
    final List<DateTime> occurrences = AlarmScheduleLogic.rollingOccurrences(
      now: now,
      checkinTime: checkinTime,
      frequency: frequency,
      horizon: horizon,
    );

    for (int i = 0; i < occurrences.length; i++) {
      await _scheduleOneShot(
        when: occurrences[i],
        alarmId: AlarmIds.rollingBase + i,
      );
    }

    await _scheduleOneShot(
      when: now.add(AlarmIds.heartbeatInterval),
      alarmId: AlarmIds.heartbeat,
    );
  }

  Future<void> scheduleRetryAlarms(DateTime firstRingAt) async {
    if (!Platform.isAndroid) return;

    final Duration grace = await StorageService.instance.getGracePeriod();
    final List<DateTime> retries = AlarmScheduleLogic.retryTimes(
      firstRingAt: firstRingAt,
      gracePeriod: grace,
      retryInterval: AlarmIds.retryInterval,
      maxSlots: AlarmIds.retrySlots,
    );

    for (int i = 0; i < AlarmIds.retrySlots; i++) {
      await AndroidAlarmManager.cancel(AlarmIds.retryBase + i);
    }

    for (int i = 0; i < retries.length; i++) {
      await _scheduleOneShot(
        when: retries[i],
        alarmId: AlarmIds.retryBase + i,
      );
    }
  }

  Future<void> cancelRetryAlarms() async {
    if (!Platform.isAndroid) return;
    for (int i = 0; i < AlarmIds.retrySlots; i++) {
      await AndroidAlarmManager.cancel(AlarmIds.retryBase + i);
    }
  }

  Future<void> scheduleSnoozeAlarm(DateTime snoozedUntil) async {
    if (!snoozedUntil.isAfter(DateTime.now())) return;

    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(AlarmIds.snooze);
      await _scheduleOneShot(when: snoozedUntil, alarmId: AlarmIds.snooze);
      return;
    }

    if (Platform.isIOS) {
      final String frequency =
          await StorageService.instance.getCheckinFrequency();
      final String checkinTime =
          await StorageService.instance.getCheckinTime() ?? '18:00';
      final String callKitId =
          _callKitIdForWhen(snoozedUntil, snoozed: true);
      await NotificationService.instance.scheduleCheckInNotification(
        notificationId: iosSnoozeNotificationId,
        when: snoozedUntil,
        snoozed: true,
        callKitId: callKitId,
        scheduledForIso: snoozedUntil.toIso8601String(),
        frequency: frequency,
        checkinTime: checkinTime,
      );
    }
  }

  Future<void> cancelSnoozeAlarm() async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(AlarmIds.snooze);
    } else if (Platform.isIOS) {
      await NotificationService.instance
          .cancelCheckInNotification(iosSnoozeNotificationId);
    }
  }

  Future<void> cancelAllAlarms() async {
    if (Platform.isAndroid) {
      final String frequency = await StorageService.instance.getCheckinFrequency();
      await _cancelAndroidManagedAlarms(frequency);
    } else if (Platform.isIOS) {
      for (int i = 0; i < 30; i++) {
        await NotificationService.instance
            .cancelCheckInNotification(iosRegularNotificationBaseId + i);
      }
      await NotificationService.instance
          .cancelCheckInNotification(iosSnoozeNotificationId);
    }
  }

  Future<void> _cancelAndroidManagedAlarms(String frequency) async {
    for (final int id in AlarmIds.allManagedIds(frequency)) {
      await AndroidAlarmManager.cancel(id);
    }
  }

  Future<void> _scheduleOneShot({
    required DateTime when,
    required int alarmId,
  }) async {
    if (!when.isAfter(DateTime.now())) return;

    await AndroidAlarmManager.oneShotAt(
      when,
      alarmId,
      checkinAlarmCallback,
      exact: true,
      wakeup: true,
      alarmClock: true,
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );
  }

  Future<void> _scheduleIosRegularNotifications({
    required DateTime now,
    required String checkinTime,
    required String frequency,
  }) async {
    final int horizon = frequency == 'Weekly' ? 8 : 30;

    for (int i = 0; i < horizon; i++) {
      await NotificationService.instance.cancelCheckInNotification(
        iosRegularNotificationBaseId + i,
      );
    }

    final List<DateTime> occurrences = AlarmScheduleLogic.rollingOccurrences(
      now: now,
      checkinTime: checkinTime,
      frequency: frequency,
      horizon: horizon,
    );

    for (int i = 0; i < occurrences.length; i++) {
      final DateTime when = occurrences[i];
      final String callKitId = _callKitIdForWhen(when, snoozed: false);
      await NotificationService.instance.scheduleCheckInNotification(
        notificationId: iosRegularNotificationBaseId + i,
        when: when,
        snoozed: false,
        callKitId: callKitId,
        scheduledForIso: when.toIso8601String(),
        frequency: frequency,
        checkinTime: checkinTime,
      );
    }
  }
}
