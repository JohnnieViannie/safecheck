/// Build-time configuration via `--dart-define`.
class AppConfig {
  AppConfig._();

  /// `prod` (default) or `dev`. Dev enables looser diagnostics only on the client.
  static const String environment = String.fromEnvironment(
    'SAFECHECK_ENV',
    defaultValue: 'prod',
  );

  static bool get isProduction => environment == 'prod';

  /// Web OAuth client ID from Firebase project safecheck-c4fa6 (client_type 3).
  /// Must match google-services.json. See app/GOOGLE_SIGNIN_SETUP.md.
  static const String googleServerClientId = String.fromEnvironment(
    'SAFECHECK_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '780122444136-53f0g0j9mqnivaq8mdboffso50nefo8j.apps.googleusercontent.com',
  );

  static const String termsUrl = String.fromEnvironment(
    'SAFECHECK_TERMS_URL',
    defaultValue: 'https://safebangle.com/terms',
  );

  static const String privacyUrl = String.fromEnvironment(
    'SAFECHECK_PRIVACY_URL',
    defaultValue: 'https://safebangle.com/privacy',
  );

  /// HTTP timeout for safety-critical API calls.
  static const Duration apiTimeout = Duration(seconds: 30);

  /// Set false to hide Google buttons (see GOOGLE_SIGNIN_SETUP.md).
  static const bool enableGoogleSignIn = true;

  /// Apple Sign-In — disabled until sign_in_with_apple is integrated.
  static const bool enableAppleSignIn = false;

  static bool get enableSocialSignIn =>
      enableGoogleSignIn || enableAppleSignIn;
}
