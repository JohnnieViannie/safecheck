import 'package:flutter/material.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/screens/home_screen.dart';
import 'package:safecheck/screens/onboarding_screen.dart';
import 'package:safecheck/services/alarm_watchdog.dart';
import 'package:safecheck/services/permissions_service.dart';

class AuthNavigation {
  AuthNavigation._();

  static Future<void> routeAfterAuth(
    BuildContext context,
    UserModel user,
  ) async {
    await PermissionsService.instance.requestPostSignInPermissions();
    await AlarmWatchdog.instance.bootstrapAfterLogin();
    if (!context.mounted) {
      return;
    }
    final Widget destination = user.onboardingCompleted
        ? const HomeScreen()
        : const OnboardingScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => destination),
      (_) => false,
    );
  }
}
