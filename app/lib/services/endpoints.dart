class Endpoints {
  Endpoints._();

  /// Production API root. Override at build time:
  /// `--dart-define=SAFECHECK_API_BASE_URL=https://api.safebangle.com/api`
  static const String baseUrl = String.fromEnvironment(
    'SAFECHECK_API_BASE_URL',
    defaultValue: 'https://safebangle.com/api',
  );

  // Email-based authentication (primary).
  static const String sendEmailCode = '/auth/send-email-code/';
  static const String verifyEmailCode = '/auth/verify-email-code/';
  static const String forgotPassword = '/auth/forgot-password/';
  static const String resetPassword = '/auth/reset-password/';
  static const String socialSignIn = '/auth/social-sign-in/';

  // Legacy phone-based OTP.
  static const String sendOtp = '/auth/send-otp/';
  static const String verifyOtp = '/auth/verify-otp/';

  // User profile.
  static const String userProfile = '/user/profile/';
  static const String updateProfile = '/user/profile/';
  static const String updateLocation = '/user/location/';
  static const String registerPushToken = '/devices/register-push/';
  static const String unregisterPushToken = '/devices/unregister-push/';
  static const String confirmSafe = '/checkins/confirm-safe/';
  static const String snoozeCheckin = '/checkins/snooze/';

  // Check-ins.
  static const String checkin = '/checkins/';
  static const String createCheckin = '/checkins/create/';
  static const String triggerCall = '/checkins/trigger-call/';
  static const String escalateMissed = '/checkins/escalate/';
  static const String callAttempts = '/calls';
  static const String alerts = '/alerts';
  static const String timelineEvents = '/timeline-events/';
  static const String callStatusWebhook = '/webhooks/call-status/';
}
