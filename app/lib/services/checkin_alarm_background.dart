import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:safecheck/services/alarm_ids.dart';
import 'package:safecheck/services/alarm_schedule_logic.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:safecheck/services/call_dedup_service.dart';
import 'package:safecheck/services/notification_service.dart';
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
      await _ringAndShowCallkit(alarmId: alarmId);
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

  for (final int id in AlarmIds.allManagedIds(frequency)) {
    await AndroidAlarmManager.cancel(id);
  }

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

  for (int i = 0; i < AlarmIds.retrySlots; i++) {
    await AndroidAlarmManager.cancel(AlarmIds.retryBase + i);
  }

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
}

Future<void> _ringAndShowCallkit({required int alarmId}) async {
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

  try {
    await FlutterRingtonePlayer().playAlarm();
  } catch (_) {
    // Ringtone may fail in isolate; CallKit/notification still attempted.
  }

  try {
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
        'scheduledFor': now.toIso8601String(),
        'frequency': frequency,
        'checkinTime': checkinTime,
        'alarmId': alarmId,
        'callKitId': callKitId,
        'source': 'local_alarm',
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
  } catch (error, stack) {
    appLog('CallKit from background failed: $error\n$stack');
    await NotificationService.showBackgroundIncomingCallFallback();
  }
}
