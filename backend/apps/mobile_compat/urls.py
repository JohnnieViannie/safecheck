from django.urls import path

from apps.mobile_compat import views

urlpatterns = [
    # Email-based auth (primary) — SafeCheck mobile contract.
    # forgot/reset live on accounts with dual mobile+web payloads.
    path("auth/send-email-code/", views.send_email_code, name="mobile_send_email_code"),
    path("auth/verify-email-code/", views.verify_email_code, name="mobile_verify_email_code"),
    path("auth/social-sign-in/", views.social_sign_in, name="mobile_social_sign_in"),
    # Legacy phone OTP.
    path("auth/send-otp/", views.send_otp, name="mobile_send_otp"),
    path("auth/verify-otp/", views.verify_otp, name="mobile_verify_otp"),
    # Profile & check-ins.
    path("user/profile/<str:uid>/", views.user_profile, name="mobile_user_profile"),
    path("user/profile/", views.upsert_user_profile, name="mobile_upsert_user_profile"),
    path("user/profile/verify-pin/", views.verify_pin, name="mobile_verify_pin"),
    path(
        "user/onboarding-draft/<str:uid>/",
        views.get_onboarding_draft,
        name="mobile_get_onboarding_draft",
    ),
    path("user/onboarding-draft/", views.save_onboarding_draft, name="mobile_save_onboarding_draft"),
    path(
        "user/onboarding-draft/<str:uid>/clear/",
        views.clear_onboarding_draft,
        name="mobile_clear_onboarding_draft",
    ),
    path("user/location/", views.update_location, name="mobile_update_location"),
    path("devices/register-push/", views.register_push_token, name="mobile_register_push"),
    path("devices/unregister-push/", views.unregister_push_token, name="mobile_unregister_push"),
    path("checkins/", views.checkins, name="mobile_checkins"),
    path("checkins/create/", views.create_checkin, name="mobile_create_checkin"),
    path("checkins/confirm-safe/", views.confirm_safe_checkin, name="mobile_confirm_safe"),
    path("checkins/snooze/", views.snooze_checkin, name="mobile_snooze"),
    path("checkins/trigger-call/", views.trigger_checkin_call, name="mobile_trigger_call"),
    path("checkins/escalate/", views.escalate_missed_checkin, name="mobile_escalate"),
    path("checkins/export/", views.export_checkins_csv, name="mobile_export_checkins"),
    path("contacts/send-opt-in/", views.send_contact_opt_in, name="mobile_send_contact_opt_in"),
    path("vault/documents/", views.list_vault_documents, name="mobile_list_vault"),
    path("vault/documents/upload/", views.upload_vault_document, name="mobile_upload_vault"),
    path(
        "vault/documents/<str:doc_id>/download/",
        views.download_vault_document,
        name="mobile_download_vault",
    ),
    path(
        "vault/documents/<str:doc_id>/delete/",
        views.delete_vault_document,
        name="mobile_delete_vault_post",
    ),
    path("vault/documents/<str:doc_id>/", views.delete_vault_document, name="mobile_delete_vault"),
    path("vault/release/<str:token>/", views.release_vault_documents, name="mobile_release_vault"),
    path(
        "vault/release/<str:token>/<str:doc_id>/download/",
        views.download_released_vault_document,
        name="mobile_download_released_vault",
    ),
    path("calls/<str:uid>/attempts/", views.call_attempts, name="mobile_call_attempts"),
    path("patrol-logs/", views.patrol_logs_collection, name="mobile_patrol_logs"),
    path("checkpoints/", views.checkpoints_collection, name="mobile_checkpoints"),
    path("guards/", views.guards_collection, name="mobile_guards"),
    path("location-pings/", views.location_pings_collection, name="mobile_location_pings"),
    path("timeline-events/", views.timeline_events_collection, name="mobile_timeline_events"),
    path("journeys/active/", views.journey_active, name="mobile_journey_active"),
    path("journeys/start/", views.journey_start, name="mobile_journey_start"),
    path(
        "journeys/<uuid:journey_id>/confirm-arrival/",
        views.journey_confirm_arrival,
        name="mobile_journey_confirm_arrival",
    ),
    path("journeys/<uuid:journey_id>/end/", views.journey_end, name="mobile_journey_end"),
    path("journeys/<uuid:journey_id>/ping/", views.journey_ping, name="mobile_journey_ping"),
    path("webhooks/call-status/", views.call_status_webhook, name="mobile_call_status_webhook"),
    path("webhooks/sms-inbound/", views.sms_inbound_webhook, name="mobile_sms_inbound_webhook"),
    path("sms/", views.list_sms_messages, name="mobile_list_sms"),
    path("sms/send/", views.send_sms_message, name="mobile_send_sms"),
]
