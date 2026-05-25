import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Prepares a background alarm isolate so plugins (CallKit, notifications,
/// shared_preferences) can run when AlarmManager fires with the app closed.
Future<void> ensureBackgroundAlarmIsolateReady() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
}
