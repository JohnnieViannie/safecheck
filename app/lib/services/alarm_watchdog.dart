import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:safecheck/services/alarm_scheduler.dart';
import 'package:safecheck/services/background_location_service.dart';
import 'package:safecheck/services/push_checkin_service.dart';

/// Keeps alarms and push registration alive across app lifecycle changes.
class AlarmWatchdog extends WidgetsBindingObserver {
  AlarmWatchdog._();

  static final AlarmWatchdog instance = AlarmWatchdog._();
  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await AlarmScheduler.instance.ensureAlarmsScheduled();
    await PushCheckinService.instance.registerTokenIfLoggedIn();
    await BackgroundLocationService.instance.pingIfDue();
  }

  /// Call after login or onboarding so alarms + FCM are registered immediately.
  Future<void> bootstrapAfterLogin() async {
    attach();
    await refresh();
  }
}
