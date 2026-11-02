import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:safecheck/services/alarm_ids.dart';
import 'package:safecheck/services/alarm_schedule_logic.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:safecheck/services/call_dedup_service.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/pending_call_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/utils/app_log.dart';

/// Background callback for SafeCheck alarms.
@pragma('vm:entry-point')
Future<void> checkinAlarmCallback(int alarmId) async {
  await ensureBackgroundAlarmIsolateReady();

  try {
    if (AlarmIds.isHeartbeat(alarmId)) {
      await _rescheduleAllFromBackground();
      return;
    }

    if (AlarmIds.isRolling(alarmId)) {
      await _rescheduleAllFromBackground();
      final DateTime now = DateTime.now();
      await _scheduleRetriesFromBackground(firstRingAt: now);
    }

    if (AlarmIds.shouldRing(alarmId)) {
      await _ringAndShowCall(alarmId: alarmId);
    }
  } catch (error, stack) {
    appLog('checkinAlarmCallback failed: $error\n$stack');
    await NotificationService.showBackgroundIncomingCallFallback();
  }
}

/// Re-schedule all alarms after device reboot.
@pragma('vm:entry-point')
Future<void> bootRescheduleCallback() async {
  await ensureBackgroundAlarmIsolateReady();
  await _rescheduleAllFromBackground();
}

Future<void> _rescheduleAllFromBackground() async {
  final String checkinTime =
      (await StorageService.instance.getCheckinTime()) ?? '18:00';
  final String frequency =
      await StorageService.instance.getCheckinFrequency();
  final DateTime now = DateTime.now();
  final int horizon = AlarmIds.horizonForFrequency(frequency);

  await _cancelAllTrackedAlarmsBackground();

  final List<DateTime> occurrences = AlarmScheduleLogic.rollingOccurrences(
    now: now,
    checkinTime: checkinTime,
    frequency: frequency,
    horizon: horizon,
  );

  for (int i = 0; i < occurrences.length; i++) {
    await _scheduleOneShotBackground(
      when: occurrences[i],
      alarmId: AlarmIds.rollingBase + i,
    );
  }

  await _scheduleOneShotBackground(
    when: now.add(AlarmIds.heartbeatInterval),
    alarmId: AlarmIds.heartbeat,
  );

  final DateTime? snoozed = await StorageService.instance.getSnoozedUntil();
  if (snoozed != null && snoozed.isAfter(now)) {
    await _scheduleOneShotBackground(when: snoozed, alarmId: AlarmIds.snooze);
  }
}

Future<void> _scheduleRetriesFromBackground({
  required DateTime firstRingAt,
}) async {
  final Duration grace = await StorageService.instance.getGracePeriod();
  final List<DateTime> retries = AlarmScheduleLogic.retryTimes(
    firstRingAt: firstRingAt,
    gracePeriod: grace,
    retryInterval: AlarmIds.retryInterval,
    maxSlots: AlarmIds.retrySlots,
  );

  await _cancelTrackedAlarmsBackground(
    List<int>.generate(AlarmIds.retrySlots, (int i) => AlarmIds.retryBase + i),
  );

  for (int i = 0; i < retries.length; i++) {
    await _scheduleOneShotBackground(
      when: retries[i],
      alarmId: AlarmIds.retryBase + i,
    );
  }
}

Future<void> _scheduleOneShotBackground({
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
  await StorageService.instance.addScheduledAlarmId(alarmId);
}

Future<void> _cancelTrackedAlarmsBackground(Iterable<int> ids) async {
  final Set<int> scheduled =
      await StorageService.instance.getScheduledAlarmIds();
  for (final int id in ids) {
    if (!scheduled.contains(id)) {
      continue;
    }
    await AndroidAlarmManager.cancel(id);
    await StorageService.instance.removeScheduledAlarmId(id);
  }
}

Future<void> _cancelAllTrackedAlarmsBackground() async {
  final Set<int> scheduled =
      await StorageService.instance.getScheduledAlarmIds();
  for (final int id in scheduled) {
    await AndroidAlarmManager.cancel(id);
  }
  await StorageService.instance.clearScheduledAlarmIds();
}

Future<void> _ringAndShowCall({required int alarmId}) async {
  final String frequency = await StorageService.instance.getCheckinFrequency();
  final String checkinTime =
      (await StorageService.instance.getCheckinTime()) ?? '18:00';
  final DateTime now = DateTime.now();

  final int seed = now.millisecondsSinceEpoch ^ (alarmId * 0x9e3779b9);
  final String hex = seed.toRadixString(16).padLeft(32, '0').substring(0, 32);
  final String callKitId = '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';

  final bool show = await CallDedupService.instance.shouldShowCall(
    callKitId: callKitId,
    scheduledFor: now,
  );
  if (!show) return;

  await PendingCallService.instance.save(
    PendingCallPayload(
      callKitId: callKitId,
      scheduledFor: now,
      frequency: frequency,
      checkinTime: checkinTime,
      alarmId: alarmId,
      source: 'local_alarm',
    ),
  );

  await NotificationService.showIncomingCheckinCallBackground(
    callKitId: callKitId,
    scheduledFor: now,
    frequency: frequency,
    checkinTime: checkinTime,
    alarmId: alarmId,
    snoozed: alarmId == AlarmIds.snooze,
    source: 'local_alarm',
  );
}
