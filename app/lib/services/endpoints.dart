class Endpoints {
  Endpoints._();

  /// Production API root (unified Blaces + SafeCheck backend).
  /// Override at build time:
  /// `--dart-define=SAFECHECK_API_BASE_URL=https://api.safebangle.com/api`
  /// or local: `--dart-define=SAFECHECK_API_BASE_URL=http://10.0.2.2:8001/api`
  static const String baseUrl = String.fromEnvironment(
    'SAFECHECK_API_BASE_URL',
    defaultValue: 'https://server.safebangle.com/api',
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
  static const String verifyPin = '/user/profile/verify-pin/';
  static const String onboardingDraft = '/user/onboarding-draft/';
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
  static const String exportCheckins = '/checkins/export/';
  static const String sendContactOptIn = '/contacts/send-opt-in/';
  static const String vaultDocuments = '/vault/documents/';
  static const String vaultUpload = '/vault/documents/upload/';
  static String vaultDocument(String docId) => '/vault/documents/$docId/';
  static String vaultDelete(String docId) => '/vault/documents/$docId/delete/';
  static String vaultDownload(String docId) => '/vault/documents/$docId/download/';
  static const String callAttempts = '/calls';
  static const String alerts = '/alerts';
  static const String timelineEvents = '/timeline-events/';
  static const String callStatusWebhook = '/webhooks/call-status/';

  static const String journeyActive = '/journeys/active/';
  static const String journeyStart = '/journeys/start/';
  static String journeyConfirmArrival(String journeyId) =>
      '/journeys/$journeyId/confirm-arrival/';
  static String journeyEnd(String journeyId) => '/journeys/$journeyId/end/';
  static String journeyPing(String journeyId) => '/journeys/$journeyId/ping/';
}
