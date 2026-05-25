import 'package:safecheck/services/notification_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

class PermissionsService {
  PermissionsService._();

  static final PermissionsService instance = PermissionsService._();
  bool _requestedThisLaunch = false;

  Future<void> requestPostSignInPermissions() async {
    if (_requestedThisLaunch) return;
    _requestedThisLaunch = true;

    // Triggers runtime microphone permission prompt on Android/iOS.
    try {
      final speech = SpeechToText();
      await speech.initialize();
    } catch (_) {
      // Keep sign-in flow resilient even if permission/plugin check fails.
    }

    // Ensure notifications permission is requested in the same post-login flow.
    try {
      await NotificationService.instance.initialize();
    } catch (_) {
      // Non-blocking permission request; ignore failures.
    }
  }
}
