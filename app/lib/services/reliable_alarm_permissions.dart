import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests Android permissions/settings that alarm-clock apps need so
/// check-in calls can fire while the app is closed.
class ReliableAlarmPermissions {
  ReliableAlarmPermissions._();

  static Future<void> ensureAndroidAlarmReliability({BuildContext? context}) async {
    if (!Platform.isAndroid) return;

    final PermissionStatus exactAlarm = await Permission.scheduleExactAlarm.status;
    if (!exactAlarm.isGranted) {
      final PermissionStatus requested = await Permission.scheduleExactAlarm.request();
      if (!requested.isGranted && context != null && context.mounted) {
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

    final PermissionStatus battery = await Permission.ignoreBatteryOptimizations.status;
    if (!battery.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Disable battery optimization for SafeCheck. On some phones also enable Autostart in app settings.',
            ),
            duration: Duration(seconds: 7),
          ),
        );
      }
    }

    final PermissionStatus notifications = await Permission.notification.status;
    if (!notifications.isGranted) {
      await Permission.notification.request();
    }
  }
}
