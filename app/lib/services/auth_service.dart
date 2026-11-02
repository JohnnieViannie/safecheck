import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safecheck/config/app_config.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/offline_sync_service.dart';
import 'package:safecheck/services/profile_sync_service.dart';
import 'package:safecheck/services/push_checkin_service.dart';
import 'package:safecheck/services/safety_service.dart';
import 'package:safecheck/services/storage_service.dart';
import 'package:safecheck/utils/app_log.dart';
import 'package:safecheck/services/biometric_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  String? _token;
  UserModel? _currentUser;
  bool? _onboardingCompletedCache;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// Cached onboarding flag for splash routing (defaults false until explicitly saved).
  bool get onboardingCompletedFromCache => _onboardingCompletedCache ?? false;

  Stream<bool> get authStateChanges => _authStateController.stream;
  UserModel? get currentUser => _currentUser;

  Future<void> loadSavedSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedToken = prefs.getString('safecheck_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      _onboardingCompletedCache =
          prefs.getBool('safecheck_onboarding_completed');
      ApiService.instance.setBearerToken(savedToken);
      _authStateController.add(true);
      final String? uid = prefs.getString('safecheck_user_uid');
      if (uid != null && uid.isNotEmpty) {
        final Map<String, dynamic>? cached =
            await StorageService.instance.getCachedProfile();
        if (cached != null) {
          _currentUser = UserModel.fromMap(<String, dynamic>{
            ...cached,
            'uid': uid,
          });
        } else {
          _currentUser = UserModel(
            uid: uid,
            onboardingCompleted: _onboardingCompletedCache ?? false,
            email: prefs.getString('safecheck_user_email'),
          );
        }
        unawaited(_refreshProfileInBackground(uid));
      }
      unawaited(syncBiometricLoginBackup());
      return;
    }
    _onboardingCompletedCache = null;
    _authStateController.add(false);
  }

  Future<void> _refreshProfileInBackground(String uid) async {
    final UserModel? remoteUser = await getUserProfile(uid);
    if (remoteUser != null) {
      _currentUser = remoteUser;
      _onboardingCompletedCache = remoteUser.onboardingCompleted;
      await ProfileSyncService.instance.applyFromProfile(remoteUser);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        'safecheck_onboarding_completed',
        remoteUser.onboardingCompleted,
      );
    }
  }

  Future<void> _saveSession({
    required String token,
    required UserModel user,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('safecheck_token', token);
    await prefs.setString('safecheck_user_uid', user.uid);
    if (user.email != null && user.email!.trim().isNotEmpty) {
      await prefs.setString('safecheck_user_email', user.email!.trim());
    }
    await prefs.setBool(
      'safecheck_onboarding_completed',
      user.onboardingCompleted,
    );
    _token = token;
    _currentUser = user;
    _onboardingCompletedCache = user.onboardingCompleted;
    ApiService.instance.setBearerToken(token);
    final UserModel? remoteUser = await getUserProfile(user.uid);
    if (remoteUser != null) {
      _currentUser = remoteUser;
    }
    await SafetyService.instance.logTimelineEvent(
      uid: user.uid,
      eventType: 'login_success',
      status: 'authenticated',
      payload: <String, dynamic>{'method': 'auth_session'},
    );
    _authStateController.add(true);
    await syncBiometricLoginBackup();
    BiometricLockSession.markUnlocked();
  }

  Future<void> syncBiometricLoginBackup() async {
    if (!await BiometricService.instance.isEnabled()) {
      await BiometricService.instance.clearLoginCredentials();
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = _token ?? prefs.getString('safecheck_token');
    final String? uid =
        _currentUser?.uid ?? prefs.getString('safecheck_user_uid');
    if (token == null ||
        token.isEmpty ||
        uid == null ||
        uid.isEmpty) {
      return;
    }

    await BiometricService.instance.saveLoginCredentials(
      token: token,
      uid: uid,
      email: _currentUser?.email ?? prefs.getString('safecheck_user_email'),
      onboardingCompleted: _onboardingCompletedCache ??
          prefs.getBool('safecheck_onboarding_completed') ??
          false,
    );
  }

  Future<void> clearSession() async {
    if (await BiometricService.instance.isEnabled()) {
      await syncBiometricLoginBackup();
    }
    await PushCheckinService.instance.unregisterTokenIfLoggedIn();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('safecheck_token');
    await prefs.remove('safecheck_user_uid');
    await prefs.remove('safecheck_user_email');
    await prefs.remove('safecheck_onboarding_completed');
    _token = null;
    _currentUser = null;
    _onboardingCompletedCache = null;
    ApiService.instance.setBearerToken('');
    _authStateController.add(false);
  }

  // ---------------------------------------------------------------------------
  // Email-based authentication
  // ---------------------------------------------------------------------------

  /// Send a verification code to the given [email].
  Future<void> sendEmailCode({
    required String email,
    required String password,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.sendEmailCode,
        body: <String, dynamic>{'email': email, 'password': password},
        timeout: AppConfig.emailAuthTimeout,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = ApiService.instance
            .decodeJson<Map<String, dynamic>>(response);
        final String verificationId = data['verificationId'] as String? ?? '';
        if (verificationId.isEmpty) {
          onError('No verification id returned by server.');
        } else {
          onCodeSent(verificationId);
        }
        return;
      }
      final String? serverError = _extractApiError(response.body);
      onError(
        serverError ??
            'Failed to send verification code: ${response.statusCode}',
      );
    } catch (error) {
      onError('Failed to send verification code: $error');
    }
  }

  /// Verify the code sent to [email].
  Future<void> verifyEmailCode({
    required String verificationId,
    required String email,
    required String password,
    required String code,
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.verifyEmailCode,
        body: <String, dynamic>{
          'verificationId': verificationId,
          'email': email,
          'password': password,
          'code': code,
        },
      );

      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        final String token = data['token'] as String? ?? '';
        final Map<String, dynamic> userMap =
            data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final user = UserModel.fromMap(userMap);
        await _saveSession(token: token, user: user);
        onSuccess(user);
        return;
      }
      onError('Verification failed: ${response.statusCode}');
    } catch (error) {
      onError('Verification failed: $error');
    }
  }

  /// Send a password reset code to an existing email account.
  Future<void> sendPasswordResetCode({
    required String email,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.forgotPassword,
        body: <String, dynamic>{'email': email},
        timeout: AppConfig.emailAuthTimeout,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = ApiService.instance
            .decodeJson<Map<String, dynamic>>(response);
        final String verificationId = data['verificationId'] as String? ?? '';
        if (verificationId.isEmpty) {
          onError('No verification id returned by server.');
        } else {
          onCodeSent(verificationId);
        }
        return;
      }
      final String? serverError = _extractApiError(response.body);
      onError(
        serverError ??
            'Failed to send reset code: ${response.statusCode}',
      );
    } catch (error) {
      onError('Failed to send reset code: $error');
    }
  }

  /// Verify reset code and set a new password.
  Future<void> resetPassword({
    required String verificationId,
    required String email,
    required String code,
    required String newPassword,
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.resetPassword,
        body: <String, dynamic>{
          'verificationId': verificationId,
          'email': email,
          'code': code,
          'newPassword': newPassword,
        },
      );

      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        final String token = data['token'] as String? ?? '';
        final Map<String, dynamic> userMap =
            data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final user = UserModel.fromMap(userMap);
        await _saveSession(token: token, user: user);
        onSuccess(user);
        return;
      }
      final String? serverError = _extractApiError(response.body);
      onError(
        serverError ?? 'Password reset failed: ${response.statusCode}',
      );
    } catch (error) {
      onError('Password reset failed: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Google Sign-In
  // ---------------------------------------------------------------------------

  bool _googleSignInInitialized = false;

  String _googleSignInErrorMessage(Object error) {
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          return 'Google sign-in was canceled.';
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google Sign-In is not configured for this app. '
              'In Firebase Console (safecheck-c4fa6): enable Google sign-in, '
              'add your Android SHA-1 fingerprint, create a Web OAuth client, '
              'then re-download google-services.json. '
              'See app/GOOGLE_SIGNIN_SETUP.md.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Google sign-in UI is unavailable on this device. Try again.';
        case GoogleSignInExceptionCode.interrupted:
          return 'Google sign-in was interrupted. Please try again.';
        case GoogleSignInExceptionCode.userMismatch:
          return 'Google account mismatch. Sign out of Google on this device and try again.';
        case GoogleSignInExceptionCode.unknownError:
          break;
      }
      final String? details = error.description;
      if (details != null && details.isNotEmpty) {
        if (details.contains('28444') ||
            details.contains('Developer console is not set up correctly')) {
          return 'Google Sign-In setup incomplete (error 28444). '
              'Add your debug SHA-1 fingerprint in Firebase Console → '
              'Project settings → Android app → SHA certificate fingerprints, '
              'then re-download google-services.json and reinstall the app. '
              'See app/GOOGLE_SIGNIN_SETUP.md.';
        }
        return 'Google sign-in failed: $details';
      }
    }
    return 'Google sign-in failed: $error';
  }

  /// Sign in with Google using the native account picker.
  /// Sends the Google ID token + email to the backend for verification.
  Future<void> signInWithGoogle({
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      if (!_googleSignInInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: AppConfig.googleServerClientId.trim(),
        );
        _googleSignInInitialized = true;
      }

      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate(scopeHint: const <String>['email']);

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      final String email = googleUser.email;

      // Send the token + email to our backend.
      final response = await ApiService.instance.post(
        Endpoints.socialSignIn,
        body: <String, dynamic>{
          'provider': 'google',
          'idToken': idToken ?? '',
          'email': email,
          'displayName': googleUser.displayName ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        final String token = data['token'] as String? ?? '';
        final Map<String, dynamic> userMap =
            data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final user = UserModel.fromMap(userMap);
        await _saveSession(token: token, user: user);
        onSuccess(user);
        return;
      }

      String serverMessage = '';
      try {
        final Map<String, dynamic> body =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        serverMessage = (body['error'] as String? ?? '').trim();
      } catch (_) {
        // ignore parse errors
      }
      onError(
        serverMessage.isNotEmpty
            ? serverMessage
            : 'Google sign-in failed: server returned ${response.statusCode}',
      );
    } catch (error) {
      final String baseUrl = ApiService.instance.baseUrl;
      if (baseUrl.contains('10.0.2.2')) {
        onError(
          'Cannot reach backend at $baseUrl from this device. Use a reachable API URL (LAN IP or public URL).',
        );
        return;
      }

      onError(_googleSignInErrorMessage(error));
    }
  }

  /// Generic social sign-in for providers other than Google (e.g. Apple).
  /// Sends provider + token to the backend.
  Future<void> socialSignIn({
    required String provider,
    String? idToken,
    String? email,
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.socialSignIn,
        body: <String, dynamic>{
          'provider': provider,
          'idToken': idToken ?? '',
          'email': email ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        final String token = data['token'] as String? ?? '';
        final Map<String, dynamic> userMap =
            data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final user = UserModel.fromMap(userMap);
        await _saveSession(token: token, user: user);
        onSuccess(user);
        return;
      }
      onError('Sign-in failed: ${response.statusCode}');
    } catch (error) {
      onError('Sign-in failed: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Legacy phone-based OTP (kept for backward compatibility)
  // ---------------------------------------------------------------------------

  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.sendOtp,
        body: <String, dynamic>{'phoneNumber': phoneNumber},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = ApiService.instance
            .decodeJson<Map<String, dynamic>>(response);
        final String verificationId = data['verificationId'] as String? ?? '';
        if (verificationId.isEmpty) {
          onError('No verification id returned by server.');
        } else {
          onCodeSent(verificationId);
        }
        return;
      }
      onError('Failed to send OTP: ${response.statusCode}');
    } catch (error) {
      onError('Failed to send OTP: $error');
    }
  }

  Future<void> verifyOtp({
    required String verificationId,
    required String phoneNumber,
    required String smsCode,
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      final response = await ApiService.instance.post(
        Endpoints.verifyOtp,
        body: <String, dynamic>{
          'verificationId': verificationId,
          'phoneNumber': phoneNumber,
          'smsCode': smsCode,
        },
      );

      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        final String token = data['token'] as String? ?? '';
        final Map<String, dynamic> userMap =
            data['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final user = UserModel.fromMap(userMap);
        await _saveSession(token: token, user: user);
        onSuccess(user);
        return;
      }
      onError('OTP verification failed: ${response.statusCode}');
    } catch (error) {
      onError('OTP verification failed: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Profile helpers
  // ---------------------------------------------------------------------------

  /// Ensures [_currentUser] is available after token restore (before profile fetch).
  Future<UserModel?> resolveSessionUser() async {
    if (_currentUser != null && _currentUser!.uid.isNotEmpty) {
      return _currentUser;
    }
    if (!isLoggedIn) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? uid = prefs.getString('safecheck_user_uid');
    if (uid == null || uid.isEmpty) {
      return null;
    }
    _currentUser = UserModel(
      uid: uid,
      onboardingCompleted: _onboardingCompletedCache ?? false,
      email: prefs.getString('safecheck_user_email'),
    );
    return _currentUser;
  }

  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final List<ConnectivityResult> connectivity =
          await Connectivity().checkConnectivity();
      final bool offline = connectivity.every(
        (ConnectivityResult result) => result == ConnectivityResult.none,
      );
      if (offline) {
        final Map<String, dynamic>? cached =
            await StorageService.instance.getCachedProfile();
        if (cached != null) {
          final UserModel user = UserModel.fromMap(<String, dynamic>{
            ...cached,
            'uid': uid,
          });
          _currentUser = user;
          await ProfileSyncService.instance.applyFromProfile(user);
          return user;
        }
        return null;
      }

      final response = await ApiService.instance.get(
        '${Endpoints.userProfile}$uid/',
      );
      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        await StorageService.instance.saveCachedProfile(data);
        final UserModel user = UserModel.fromMap(data);
        _currentUser = user;
        await ProfileSyncService.instance.applyFromProfile(user);
        return user;
      }
    } catch (_) {
      // Fall back to cached profile below.
    }

    final Map<String, dynamic>? cached =
        await StorageService.instance.getCachedProfile();
    if (cached != null) {
      final UserModel user = UserModel.fromMap(<String, dynamic>{
        ...cached,
        'uid': uid,
      });
      _currentUser = user;
      await ProfileSyncService.instance.applyFromProfile(user);
      return user;
    }
    return null;
  }

  Future<bool> verifyPin({
    required String uid,
    required String pin,
  }) async {
    if (uid.trim().isEmpty || pin.trim().length != 4) {
      return false;
    }
    if (_token != null && _token!.isNotEmpty) {
      ApiService.instance.setBearerToken(_token!);
    }
    if (ApiService.instance.baseUrl.trim().isEmpty) {
      ApiService.instance.init(url: Endpoints.baseUrl);
    }

    try {
      final response = await ApiService.instance.post(
        Endpoints.verifyPin,
        body: <String, dynamic>{
          'uid': uid,
          'pin': pin.trim(),
        },
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            ApiService.instance.decodeJson<Map<String, dynamic>>(response);
        return data['valid'] == true;
      }
    } catch (_) {
      // Fall through to false.
    }
    return false;
  }

  String? _lastProfileSaveError;
  bool _lastSaveQueuedOffline = false;

  String? get lastProfileSaveError => _lastProfileSaveError;

  bool get lastSaveQueuedOffline => _lastSaveQueuedOffline;

  Future<bool> createOrUpdateUser({
    required String uid,
    required String phoneNumber,
    required Map<String, dynamic> extra,
  }) async {
    _lastProfileSaveError = null;
    _lastSaveQueuedOffline = false;
    if (uid.trim().isEmpty) {
      appLog('createOrUpdateUser: missing uid');
      return false;
    }
    if (_token != null && _token!.isNotEmpty) {
      ApiService.instance.setBearerToken(_token!);
    }
    if (ApiService.instance.baseUrl.trim().isEmpty) {
      ApiService.instance.init(url: Endpoints.baseUrl);
    }

    try {
      final body = <String, dynamic>{
        'uid': uid,
        'phone_number': phoneNumber,
        ...extra,
      };
      appLog('createOrUpdateUser POST ${Endpoints.updateProfile} uid=$uid');
      final response = await ApiService.instance.post(
        Endpoints.updateProfile,
        body: body,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = ApiService.instance
            .decodeJson<Map<String, dynamic>>(response);
        if (extra.containsKey('emergency_contacts_json')) {
          final Object? stored = data['emergency_contacts_json'] ??
              data['emergencyContactsJson'];
          if (stored == null || stored.toString().trim().isEmpty) {
            _lastProfileSaveError =
                'Server did not save contacts. Update the backend (see deploy/SERVER_UPDATE.md).';
            appLog('createOrUpdateUser: server missing emergency_contacts_json');
            return false;
          }
        }
        await StorageService.instance.saveCachedProfile(data);
        final UserModel updated = UserModel.fromMap(data);
        _currentUser = updated;
        await ProfileSyncService.instance.applyFromProfile(updated);
        _onboardingCompletedCache = updated.onboardingCompleted;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        if (updated.email != null && updated.email!.trim().isNotEmpty) {
          await prefs.setString('safecheck_user_email', updated.email!.trim());
        }
        await prefs.setBool(
          'safecheck_onboarding_completed',
          updated.onboardingCompleted,
        );
        _authStateController.add(true);
        return true;
      }
      _lastProfileSaveError = _extractApiError(response.body) ??
          'Server returned ${response.statusCode}';
      appLog(
        'createOrUpdateUser failed: ${response.statusCode} ${response.body}',
      );
    } catch (error) {
      if (OfflineSyncService.isNetworkError(error)) {
        final Map<String, dynamic> body = <String, dynamic>{
          'uid': uid,
          'phone_number': phoneNumber,
          ...extra,
        };
        await OfflineSyncService.instance.enqueue(
          type: OfflineSyncService.opUpdateProfile,
          payload: body,
        );
        await _cacheProfileMerge(body);
        _lastProfileSaveError = null;
        _lastSaveQueuedOffline = true;
        return true;
      }
      _lastProfileSaveError = error.toString();
      appLog('createOrUpdateUser error: $error');
    }
    return false;
  }

  Future<void> _cacheProfileMerge(Map<String, dynamic> body) async {
    final Map<String, dynamic>? existing =
        await StorageService.instance.getCachedProfile();
    final Map<String, dynamic> merged = <String, dynamic>{
      if (existing != null) ...existing,
      ...body,
    };
    await StorageService.instance.saveCachedProfile(merged);
    _currentUser = UserModel.fromMap(merged);
    await ProfileSyncService.instance.applyFromProfile(_currentUser!);
    _authStateController.add(true);
  }

  Future<Map<String, dynamic>?> getOnboardingDraft(String uid) async {
    if (uid.trim().isEmpty) {
      return null;
    }
    if (_token != null && _token!.isNotEmpty) {
      ApiService.instance.setBearerToken(_token!);
    }
    try {
      final response = await ApiService.instance.get(
        '${Endpoints.onboardingDraft}$uid/',
      );
      if (response.statusCode != 200) {
        return null;
      }
      final Map<String, dynamic> data = ApiService.instance
          .decodeJson<Map<String, dynamic>>(response);
      if (data['onboarding_completed'] == true) {
        return null;
      }
      final Map<String, dynamic>? draft =
          data['draft'] as Map<String, dynamic>?;
      if (draft == null) {
        return null;
      }
      final int? step = data['step'] as int?;
      if (step != null) {
        draft['step'] = step;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOnboardingDraft({
    required String uid,
    required int step,
    required Map<String, dynamic> draft,
  }) async {
    if (uid.trim().isEmpty) {
      return;
    }
    if (_token != null && _token!.isNotEmpty) {
      ApiService.instance.setBearerToken(_token!);
    }
    try {
      await ApiService.instance.post(
        Endpoints.onboardingDraft,
        body: <String, dynamic>{
          'uid': uid,
          'step': step,
          'draft': draft,
        },
      );
    } catch (_) {
      // Non-fatal — local draft remains the fallback.
    }
  }

  Future<void> clearOnboardingDraftOnServer(String uid) async {
    if (uid.trim().isEmpty) {
      return;
    }
    if (_token != null && _token!.isNotEmpty) {
      ApiService.instance.setBearerToken(_token!);
    }
    try {
      await ApiService.instance.delete(
        '${Endpoints.onboardingDraft}$uid/clear/',
      );
    } catch (_) {
      // Non-fatal.
    }
  }

  String? _extractApiError(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final Object? error = decoded['error'];
        if (error != null) {
          return error.toString();
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> signOut() async {
    await clearSession();
  }

  Future<void> signInWithBiometrics({
    required void Function(UserModel user) onSuccess,
    required void Function(String message) onError,
  }) async {
    if (!await BiometricService.instance.canUnlockApp()) {
      onError(
        'Set up fingerprint or Face ID in your phone settings first.',
      );
      return;
    }
    if (!await BiometricService.instance.hasStoredLogin()) {
      onError(
        'No saved account for biometric sign-in. Log in once and enable biometric unlock in Settings.',
      );
      return;
    }

    final BiometricAuthResult auth = await BiometricService.instance.authenticate(
      reason: 'Sign in to SafeCheck',
      biometricOnly: true,
    );
    if (!auth.success) {
      if (auth.errorMessage != null && auth.errorMessage!.isNotEmpty) {
        onError(auth.errorMessage!);
      }
      return;
    }

    final BiometricLoginCredentials? credentials =
        await BiometricService.instance.readLoginCredentials();
    if (credentials == null) {
      onError('Could not restore your saved session. Log in with email instead.');
      return;
    }

    final UserModel user = UserModel(
      uid: credentials.uid,
      onboardingCompleted: credentials.onboardingCompleted,
      email: credentials.email,
    );
    await _saveSession(token: credentials.token, user: user);
    onSuccess(_currentUser ?? user);
  }
}
