import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safecheck/models/user_model.dart';
import 'package:safecheck/services/api_service.dart';
import 'package:safecheck/services/endpoints.dart';
import 'package:safecheck/services/safety_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  String? _token;
  UserModel? _currentUser;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Stream<bool> get authStateChanges => _authStateController.stream;
  UserModel? get currentUser => _currentUser;

  Future<void> loadSavedSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedToken = prefs.getString('safecheck_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      ApiService.instance.setBearerToken(savedToken);
      // Emit authenticated immediately so the app doesn't hang on a network call.
      // Refresh profile in the background without blocking startup.
      _authStateController.add(true);
      final String? uid = prefs.getString('safecheck_user_uid');
      if (uid != null) {
        final UserModel? remoteUser = await getUserProfile(uid);
        if (remoteUser != null) {
          _currentUser = remoteUser;
        }
      }
      return;
    }
    _authStateController.add(false);
  }

  Future<void> _saveSession({
    required String token,
    required UserModel user,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('safecheck_token', token);
    await prefs.setString('safecheck_user_uid', user.uid);
    _token = token;
    _currentUser = user;
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
  }

  Future<void> clearSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('safecheck_token');
    await prefs.remove('safecheck_user_uid');
    _token = null;
    _currentUser = null;
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
      onError('Failed to send verification code: ${response.statusCode}');
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

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Google Sign-In
  // ---------------------------------------------------------------------------

  bool _googleSignInInitialized = false;

  /// Sign in with Google using the native account picker.
  /// Sends the Google ID token + email to the backend for verification.
  Future<void> signInWithGoogle({
    required void Function(UserModel user) onSuccess,
    required void Function(String error) onError,
  }) async {
    try {
      if (!_googleSignInInitialized) {
        await GoogleSignIn.instance.initialize(
          // In Android's new Credential Manager, this Web Client ID is strictly required.
          serverClientId:
              '310691842473-cjf81pa8cj45rn6f92g1vdk0j6ma9njj.apps.googleusercontent.com',
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
      onError('Google sign-in failed: ${response.statusCode}');
    } catch (error) {
      final bool userCancelled =
          error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled;
      if (userCancelled) {
        onError('Google sign-in was canceled.');
        return;
      }

      final String baseUrl = ApiService.instance.baseUrl;
      if (baseUrl.contains('10.0.2.2')) {
        onError(
          'Cannot reach backend at $baseUrl from this device. Open Settings and set a reachable server URL (LAN IP or public URL).',
        );
        return;
      }

      onError('Google sign-in failed: $error');
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

  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final response = await ApiService.instance.get(
        '${Endpoints.userProfile}$uid/',
      );
      if (response.statusCode == 200) {
        final data = ApiService.instance.decodeJson<Map<String, dynamic>>(
          response,
        );
        return UserModel.fromMap(data);
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<bool> createOrUpdateUser({
    required String uid,
    required String phoneNumber,
    required Map<String, dynamic> extra,
  }) async {
    try {
      final body = <String, dynamic>{
        'uid': uid,
        'phone_number': phoneNumber,
        ...extra,
      };
      final response = await ApiService.instance.post(
        Endpoints.updateProfile,
        body: body,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = ApiService.instance
            .decodeJson<Map<String, dynamic>>(response);
        _currentUser = UserModel.fromMap(data);
        _authStateController.add(true);
        return true;
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  Future<void> signOut() async {
    await clearSession();
  }
}
