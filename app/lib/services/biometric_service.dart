import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safecheck/utils/app_log.dart';

class BiometricLoginCredentials {
  const BiometricLoginCredentials({
    required this.token,
    required this.uid,
    this.email,
    required this.onboardingCompleted,
  });

  final String token;
  final String uid;
  final String? email;
  final bool onboardingCompleted;
}

class BiometricAuthResult {
  const BiometricAuthResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

class BiometricService {
  BiometricService._();

  static final BiometricService instance = BiometricService._();
  static const String _enabledKey = 'settings_biometric_unlock';
  static const String _tokenKey = 'safecheck_biometric_token';
  static const String _uidKey = 'safecheck_biometric_uid';
  static const String _emailKey = 'safecheck_biometric_email';
  static const String _onboardingKey = 'safecheck_biometric_onboarding_completed';

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) {
      await clearLoginCredentials();
    }
  }

  Future<bool> hasStoredLogin() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString(_tokenKey);
    final String? uid = prefs.getString(_uidKey);
    return (token?.isNotEmpty ?? false) && (uid?.isNotEmpty ?? false);
  }

  Future<void> saveLoginCredentials({
    required String token,
    required String uid,
    String? email,
    required bool onboardingCompleted,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_uidKey, uid);
    if (email != null && email.trim().isNotEmpty) {
      await prefs.setString(_emailKey, email.trim());
    } else {
      await prefs.remove(_emailKey);
    }
    await prefs.setBool(_onboardingKey, onboardingCompleted);
  }

  Future<BiometricLoginCredentials?> readLoginCredentials() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString(_tokenKey);
    final String? uid = prefs.getString(_uidKey);
    if (token == null ||
        token.isEmpty ||
        uid == null ||
        uid.isEmpty) {
      return null;
    }
    return BiometricLoginCredentials(
      token: token,
      uid: uid,
      email: prefs.getString(_emailKey),
      onboardingCompleted: prefs.getBool(_onboardingKey) ?? false,
    );
  }

  Future<void> clearLoginCredentials() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_uidKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_onboardingKey);
  }

  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (error) {
      appLog('Biometric isDeviceSupported error: $error');
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (error) {
      appLog('Biometric getAvailableBiometrics error: $error');
      return <BiometricType>[];
    }
  }

  Future<bool> canUseBiometrics() async {
    if (!await isDeviceSupported()) {
      return false;
    }
    final List<BiometricType> available = await availableBiometrics();
    return available.isNotEmpty;
  }

  Future<bool> canUnlockApp() async {
    if (!await isDeviceSupported()) {
      return false;
    }
    if (await canUseBiometrics()) {
      return true;
    }
    return await _auth.canCheckBiometrics;
  }

  Future<BiometricAuthResult> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      if (!await isDeviceSupported()) {
        return const BiometricAuthResult(
          success: false,
          errorMessage: 'This device does not support biometric unlock.',
        );
      }

      final bool unlocked = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );

      if (unlocked) {
        return const BiometricAuthResult(success: true);
      }
      return const BiometricAuthResult(
        success: false,
        errorMessage: 'Biometric verification was cancelled.',
      );
    } on PlatformException catch (error) {
      appLog('Biometric authenticate error: ${error.code} ${error.message}');
      return BiometricAuthResult(
        success: false,
        errorMessage: error.message ?? 'Biometric verification failed.',
      );
    } catch (error) {
      appLog('Biometric authenticate error: $error');
      return BiometricAuthResult(
        success: false,
        errorMessage: 'Biometric verification failed.',
      );
    }
  }

  Future<bool> authenticateSimple({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final BiometricAuthResult result = await authenticate(
      reason: reason,
      biometricOnly: biometricOnly,
    );
    return result.success;
  }
}

/// Prevents biometric app-lock from re-firing in a loop (e.g. when the
/// system biometric sheet briefly sets the app to [AppLifecycleState.inactive]).
class BiometricLockSession {
  BiometricLockSession._();

  static bool _unlocked = false;
  static bool _needsUnlockAfterPause = false;
  static int _suppressCount = 0;
  static DateTime? _lastPromptAt;

  static void markUnlocked() {
    _unlocked = true;
    _needsUnlockAfterPause = false;
  }

  static void markNeedsUnlock() {
    _unlocked = false;
  }

  static void onAppPaused() {
    _needsUnlockAfterPause = true;
    _unlocked = false;
  }

  static bool get needsUnlockAfterPause =>
      _needsUnlockAfterPause && !_unlocked;

  static void suppressPrompts() {
    _suppressCount++;
  }

  static void releasePrompts() {
    if (_suppressCount > 0) {
      _suppressCount--;
    }
  }

  static bool shouldPrompt({
    required bool enabled,
    required bool loggedIn,
  }) {
    if (!enabled || !loggedIn) {
      return false;
    }
    if (_suppressCount > 0) {
      return false;
    }
    // Only after the app was sent to the background — never on sign-in or launch.
    if (!_needsUnlockAfterPause) {
      return false;
    }
    if (_unlocked) {
      return false;
    }
    if (_lastPromptAt != null &&
        DateTime.now().difference(_lastPromptAt!) <
            const Duration(seconds: 4)) {
      return false;
    }
    return true;
  }

  static void recordPrompt() {
    _lastPromptAt = DateTime.now();
  }
}
