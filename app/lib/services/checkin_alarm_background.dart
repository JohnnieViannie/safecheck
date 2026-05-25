import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:safecheck/services/background_alarm_init.dart';
import 'package:safecheck/services/notification_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

/// Background callback for SafeCheck alarms.
///
/// This callback is invoked by Android's AlarmManager even when the app is
/// not running.
///
/// The alarm id is passed as the single int argument.
@pragma('vm:entry-point')
Future<void> checkinAlarmCallback(int alarmId) async {
  await ensureBackgroundAlarmIsolateReady();

  try {
    // Always (re)schedule the next regular alarm when the regular alarm fires
    // so the chain continues even if the UI is never opened again.
    if (alarmId == AlarmSchedulerIds.regularAlarmId) {
      await _scheduleNextRegularAlarm();
    }

    // Show incoming call UI (CallKit). If plugins fail in the background
    // isolate, fall back to a loud full-screen alarm notification.
    await _showCallkitIncomingForAlarm(alarmId: alarmId);
  } catch (error, stack) {
    debugPrint('checkinAlarmCallback failed: $error\n$stack');
    await NotificationService.showBackgroundIncomingCallFallback();
  }
}

class AlarmSchedulerIds {
  static const int regularAlarmId = 0;
  static const int snoozeAlarmId = 1;
}

Future<void> _scheduleNextRegularAlarm() async {
  final String checkinTime = (await StorageService.instance.getCheckinTime()) ??
      '18:00';
  final String frequency =
      await StorageService.instance.getCheckinFrequency();

  final DateTime now = DateTime.now();
  final DateTime next = _computeNextRegularAt(
    now: now,
    checkinTime: checkinTime,
    frequency: frequency,
  );

  // Replace any existing regular alarm so schedule changes apply.
  await AndroidAlarmManager.cancel(AlarmSchedulerIds.regularAlarmId);
  await AndroidAlarmManager.oneShotAt(
    next,
    AlarmSchedulerIds.regularAlarmId,
    checkinAlarmCallback,
    exact: true,
    wakeup: true,
    alarmClock: true,
    rescheduleOnReboot: true,
    allowWhileIdle: true,
  );
}

/// Re-schedule the next check-in after device reboot (alarms are cleared on reboot).
@pragma('vm:entry-point')
Future<void> bootRescheduleCallback() async {
  await ensureBackgroundAlarmIsolateReady();
  await _scheduleNextRegularAlarm();
}

Future<void> _showCallkitIncomingForAlarm({required int alarmId}) async {
  final String frequency = await StorageService.instance.getCheckinFrequency();
  final String checkinTime = await StorageService.instance.getCheckinTime() ??
      '18:00';

  final DateTime now = DateTime.now();

  // CallKit `id` must be a UUID.
  final int seed = now.millisecondsSinceEpoch ^ (alarmId * 0x9e3779b9);
  final String hex = seed.toRadixString(16).padLeft(32, '0').substring(0, 32);
  final String callKitId = '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';

  final CallKitParams params = CallKitParams(
    id: callKitId,
    nameCaller: 'SafeCheck',
    handle: 'SafeCheck',
    type: 0, // audio call
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

DateTime _computeNextRegularAt({
  required DateTime now,
  required String checkinTime,
  required String frequency,
}) {
  final List<String> parts = checkinTime.split(':');
  final int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 18;
  final int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

  final Duration period =
      frequency == 'Weekly' ? const Duration(days: 7) : const Duration(days: 1);

  DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (!candidate.isAfter(now)) {
    candidate = candidate.add(period);
  }
  return candidate;
}

