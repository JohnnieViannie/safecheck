from django.urls import path
from . import views

urlpatterns = [
    path('health/', views.health, name='health'),

    # Email-based auth (primary).
    path('auth/send-email-code/', views.send_email_code, name='send_email_code'),
    path('auth/verify-email-code/', views.verify_email_code, name='verify_email_code'),
    path('auth/forgot-password/', views.send_password_reset_code, name='send_password_reset_code'),
    path('auth/reset-password/', views.reset_password, name='reset_password'),
    path('auth/social-sign-in/', views.social_sign_in, name='social_sign_in'),

    # Legacy phone-based OTP.
    path('auth/send-otp/', views.send_otp, name='send_otp'),
    path('auth/verify-otp/', views.verify_otp, name='verify_otp'),

    # Profile & check-ins.
    path('user/profile/<str:uid>/', views.user_profile, name='user_profile'),
    path('user/profile/', views.upsert_user_profile, name='upsert_user_profile'),
    path('user/location/', views.update_location, name='update_location'),
    path('devices/register-push/', views.register_push_token, name='register_push_token'),
    path('devices/unregister-push/', views.unregister_push_token, name='unregister_push_token'),
    path('checkins/', views.checkins, name='checkins'),
    path('checkins/create/', views.create_checkin, name='create_checkin'),
    path('checkins/confirm-safe/', views.confirm_safe_checkin, name='confirm_safe_checkin'),
    path('checkins/snooze/', views.snooze_checkin, name='snooze_checkin'),
    path('checkins/trigger-call/', views.trigger_checkin_call, name='trigger_checkin_call'),
    path('checkins/escalate/', views.escalate_missed_checkin, name='escalate_missed_checkin'),
    path('calls/<str:uid>/attempts/', views.call_attempts, name='call_attempts'),
    path('alerts/<str:uid>/', views.alerts, name='alerts'),
    path('alerts/', views.alerts_collection, name='alerts_collection'),
    path('incidents/', views.incidents_collection, name='incidents_collection'),
    path('patrol-logs/', views.patrol_logs_collection, name='patrol_logs_collection'),
    path('checkpoints/', views.checkpoints_collection, name='checkpoints_collection'),
    path('guards/', views.guards_collection, name='guards_collection'),
    path('location-pings/', views.location_pings_collection, name='location_pings_collection'),
    path('timeline-events/', views.timeline_events_collection, name='timeline_events_collection'),
    path('webhooks/call-status/', views.call_status_webhook, name='call_status_webhook'),
]
