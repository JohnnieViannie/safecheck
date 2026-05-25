class Endpoints {
  Endpoints._();

  // Set your hosted API base URL here.
  // E.g. https://api.safecheck.me/v1
  // You can override with --dart-define=SAFECHECK_API_BASE_URL=https://your-api/api
  static const String baseUrl = String.fromEnvironment(
    'SAFECHECK_API_BASE_URL',
    defaultValue: 'http://10.55.185.220:8080/api',
  );

  // Email-based authentication (primary).
  static const String sendEmailCode = '/auth/send-email-code/';
  static const String verifyEmailCode = '/auth/verify-email-code/';
  static const String socialSignIn = '/auth/social-sign-in/';

  // Legacy phone-based OTP.
  static const String sendOtp = '/auth/send-otp/';
  static const String verifyOtp = '/auth/verify-otp/';

  // User profile.
  static const String userProfile = '/user/profile/';
  static const String updateProfile = '/user/profile/';
  static const String updateLocation = '/user/location/';
  static const String registerPushToken = '/devices/register-push/';

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
