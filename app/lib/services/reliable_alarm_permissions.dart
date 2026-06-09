import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class AlarmSetupStatus {
  const AlarmSetupStatus({
    required this.exactAlarmGranted,
    required this.batteryOptimizationDisabled,
    required this.notificationsGranted,
  });

  final bool exactAlarmGranted;
  final bool batteryOptimizationDisabled;
  final bool notificationsGranted;

  bool get isReady =>
      exactAlarmGranted && notificationsGranted;
}

/// Requests Android permissions/settings that alarm-clock apps need.
class ReliableAlarmPermissions {
  ReliableAlarmPermissions._();

  static Future<AlarmSetupStatus> checkAndroidAlarmSetup() async {
    if (!Platform.isAndroid) {
      return const AlarmSetupStatus(
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        notificationsGranted: true,
      );
    }

    final PermissionStatus exactAlarm =
        await Permission.scheduleExactAlarm.status;
    final PermissionStatus battery =
        await Permission.ignoreBatteryOptimizations.status;
    final PermissionStatus notifications =
        await Permission.notification.status;

    return AlarmSetupStatus(
      exactAlarmGranted: exactAlarm.isGranted,
      batteryOptimizationDisabled: battery.isGranted,
      notificationsGranted: notifications.isGranted,
    );
  }

  static Future<void> ensureAndroidAlarmReliability({
    BuildContext? context,
  }) async {
    if (!Platform.isAndroid) return;

    final AlarmSetupStatus status = await checkAndroidAlarmSetup();
    if (!status.exactAlarmGranted) {
      await requestExactAlarm();
      if (context != null && context.mounted) {
        final PermissionStatus after = await Permission.scheduleExactAlarm.status;
        if (!after.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Allow "Alarms & reminders" for SafeCheck so check-in calls work in the background.',
              ),
              duration: Duration(seconds: 6),
            ),
          );
          await openAppSettings();
        }
      }
    }

    if (!status.batteryOptimizationDisabled) {
      await requestBatteryExemption();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Disable battery optimization for SafeCheck. On some phones also enable Autostart.',
            ),
            duration: Duration(seconds: 7),
          ),
        );
      }
    }

    if (!status.notificationsGranted) {
      await requestNotifications();
    }
  }

  static Future<void> requestExactAlarm() async {
    if (!Platform.isAndroid) return;
    await Permission.scheduleExactAlarm.request();
  }

  static Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    await Permission.ignoreBatteryOptimizations.request();
  }

  static Future<void> requestNotifications() async {
    await Permission.notification.request();
  }

  static Future<void> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return;
    // Best-effort: permission_handler opens app settings where autostart lives.
    await openAppSettings();
  }
}
