import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:io';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/services/checkin_alarm_background.dart';

/// Schedules the next SafeCheck check-in alarm using Android's AlarmManager.
///
/// The alarm callback posts a full-screen notification that brings the user
/// into the app's incoming-call UI (see `HomeScreen`).
class AlarmScheduler {
  AlarmScheduler._();

  static final AlarmScheduler instance = AlarmScheduler._();

  // Keep these ids in sync with the background callback.
  static const int regularAlarmId = 0;
  static const int snoozeAlarmId = 1;

  // iOS local notification ids (must be stable).
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

  /// Call on app startup and after login so alarms exist even if HomeScreen
  /// is never opened again.
  Future<void> ensureAlarmsScheduled() async {
    await scheduleNextRegularAlarm();

    if (!Platform.isAndroid) return;

    final DateTime? snoozed = await StorageService.instance.getSnoozedUntil();
    if (snoozed != null && snoozed.isAfter(DateTime.now())) {
      await scheduleSnoozeAlarm(snoozed);
    }
  }

  Future<void> scheduleNextRegularAlarm() async {
    final String checkinTime = (await StorageService.instance.getCheckinTime()) ??
        '18:00';
    final String frequency = await StorageService.instance.getCheckinFrequency();

    final DateTime now = DateTime.now();

    if (Platform.isAndroid) {
      final DateTime next = _computeNextRegularAt(
        now: now,
        checkinTime: checkinTime,
        frequency: frequency,
      );

      // Replace any existing regular alarm so schedule changes apply immediately.
      await AndroidAlarmManager.cancel(regularAlarmId);
      await AndroidAlarmManager.oneShotAt(
        next,
        regularAlarmId,
        checkinAlarmCallback,
        exact: true,
        wakeup: true,
        alarmClock: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      return;
    }

    if (Platform.isIOS) {
      // iOS cannot run background Dart callbacks at an exact time.
      // Scheduling local notifications ensures the alarm still fires while the
      // app is closed; when the user taps it, the existing HomeScreen grace
      // logic will open the incoming-call UI.
      await _scheduleIosRegularNotifications(
        now: now,
        checkinTime: checkinTime,
        frequency: frequency,
      );
    }
  }

  Future<void> scheduleSnoozeAlarm(DateTime snoozedUntil) async {
    // Ignore obviously invalid times.
    if (!snoozedUntil.isAfter(DateTime.now())) return;

    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(snoozeAlarmId);
      await AndroidAlarmManager.oneShotAt(
        snoozedUntil,
        snoozeAlarmId,
        checkinAlarmCallback,
        exact: true,
        wakeup: true,
        alarmClock: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      return;
    }

    if (Platform.isIOS) {
      final String frequency =
          await StorageService.instance.getCheckinFrequency();
      final String checkinTime = await StorageService.instance.getCheckinTime() ??
          '18:00';
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
      await AndroidAlarmManager.cancel(snoozeAlarmId);
    } else if (Platform.isIOS) {
      await NotificationService.instance
          .cancelCheckInNotification(iosSnoozeNotificationId);
    }
  }

  Future<void> cancelAllAlarms() async {
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(regularAlarmId);
      await AndroidAlarmManager.cancel(snoozeAlarmId);
    } else if (Platform.isIOS) {
      // Cancel a small horizon of scheduled regular notifications.
      for (int i = 0; i < 30; i++) {
        await NotificationService.instance
            .cancelCheckInNotification(iosRegularNotificationBaseId + i);
      }
      await NotificationService.instance
          .cancelCheckInNotification(iosSnoozeNotificationId);
    }
  }

  DateTime _computeNextRegularAt({
    required DateTime now,
    required String checkinTime,
    required String frequency,
  }) {
    final List<String> parts = checkinTime.split(':');
    final int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 18;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

    final Duration period = frequency == 'Weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);

    DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      // Move forward to ensure we schedule into the future.
      candidate = candidate.add(period);
    }
    return candidate;
  }

  Future<void> _scheduleIosRegularNotifications({
    required DateTime now,
    required String checkinTime,
    required String frequency,
  }) async {
    // iOS keeps at most 64 pending notifications; refresh a rolling window.
    final int horizon = frequency == 'Weekly' ? 8 : 30;

    // Cancel the ids we are going to (re)create.
    for (int i = 0; i < horizon; i++) {
      await NotificationService.instance.cancelCheckInNotification(
        iosRegularNotificationBaseId + i,
      );
    }

    DateTime candidate = _computeNextRegularAt(
      now: now,
      checkinTime: checkinTime,
      frequency: frequency,
    );

    // Schedule a few upcoming occurrences so it still triggers even if the
    // user doesn't open the app for a couple of days.
    for (int i = 0; i < horizon; i++) {
      final int notificationId = iosRegularNotificationBaseId + i;
      final DateTime when = candidate;
      final String callKitId = _callKitIdForWhen(when, snoozed: false);
      await NotificationService.instance.scheduleCheckInNotification(
        notificationId: notificationId,
        when: when,
        snoozed: false,
        callKitId: callKitId,
        scheduledForIso: when.toIso8601String(),
        frequency: frequency,
        checkinTime: checkinTime,
      );

      final Duration period = frequency == 'Weekly'
          ? const Duration(days: 7)
          : const Duration(days: 1);
      candidate = candidate.add(period);
    }
  }
}

