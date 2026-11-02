"""Safety profile and related mobile-safety models keyed to accounts.User."""
from django.conf import settings
from django.db import models


class SafetyProfile(models.Model):
    """Mobile SafeCheck fields formerly on UserProfile, 1:1 with accounts.User."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="safety_profile",
        primary_key=True,
    )
    # Mobile clients historically used email (or phone) as uid.
    legacy_uid = models.CharField(max_length=128, unique=True, db_index=True)
    onboarding_completed = models.BooleanField(default=False)
    onboarding_step = models.IntegerField(blank=True, null=True)
    onboarding_draft_json = models.TextField(blank=True, null=True)
    user_type = models.CharField(max_length=32, blank=True, null=True)
    checkin_frequency = models.CharField(max_length=32, blank=True, null=True)
    grace_period_hours = models.IntegerField(blank=True, null=True)
    grace_period_minutes = models.IntegerField(blank=True, null=True)
    # Legacy single-contact columns kept for mobile payload shape; NOK truth is TrustedContact.
    emergency_contact_name = models.CharField(max_length=128, blank=True, null=True)
    emergency_contact_relationship = models.CharField(max_length=64, blank=True, null=True)
    emergency_contact_country_code = models.CharField(max_length=2, default="UG")
    emergency_contact_phone = models.CharField(max_length=32, blank=True, null=True)
    emergency_contact_email = models.EmailField(blank=True, null=True)
    # Write buffer / opt-in metadata; canonical NOK rows live in people.TrustedContact.
    emergency_contacts_json = models.TextField(blank=True, null=True)
    trigger_actions_json = models.TextField(blank=True, null=True)
    notification_prefs_json = models.TextField(blank=True, null=True)
    pin = models.CharField(max_length=128, blank=True, null=True)
    last_check_in_at = models.DateTimeField(blank=True, null=True)
    checkin_time = models.TimeField(blank=True, null=True)
    timezone = models.CharField(max_length=64, default="UTC")
    max_retry_attempts = models.IntegerField(default=3)
    last_call_status = models.CharField(max_length=32, default="idle")
    escalation_status = models.CharField(max_length=32, default="none")
    last_escalated_at = models.DateTimeField(blank=True, null=True)
    next_scheduled_checkin_at = models.DateTimeField(blank=True, null=True)
    fcm_token = models.CharField(max_length=512, blank=True, null=True)
    fcm_token_updated_at = models.DateTimeField(blank=True, null=True)
    fcm_platform = models.CharField(max_length=16, blank=True, null=True)
    snoozed_until = models.DateTimeField(blank=True, null=True)
    last_push_sent_at = models.DateTimeField(blank=True, null=True)
    pending_call_kit_id = models.CharField(max_length=64, blank=True, null=True)

    class Meta:
        indexes = [
            models.Index(fields=["next_scheduled_checkin_at"]),
            models.Index(fields=["legacy_uid"]),
        ]

    def __str__(self):
        return f"SafetyProfile({self.legacy_uid})"

    @property
    def uid(self):
        return self.legacy_uid

    @property
    def email(self):
        return self.user.email or ""

    @property
    def full_name(self):
        return self.user.full_name

    @property
    def phone_number(self):
        return self.user.phone or ""

    @property
    def password(self):
        return self.user.password

    def confirmed_safe_after_last_push(self) -> bool:
        if not self.last_push_sent_at:
            return False
        if self.last_call_status == "safe_confirmed":
            return True
        if self.last_check_in_at and self.last_check_in_at >= self.last_push_sent_at:
            return True
        return False

    def grace_period_timedelta(self):
        from django.utils import timezone as dj_tz

        if self.grace_period_minutes is not None:
            return dj_tz.timedelta(minutes=self.grace_period_minutes)
        hours = self.grace_period_hours if self.grace_period_hours is not None else 2
        return dj_tz.timedelta(hours=hours)


class LocationSnapshot(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="locations",
    )
    latitude = models.FloatField()
    longitude = models.FloatField()
    accuracy_meters = models.FloatField(blank=True, null=True)
    address = models.CharField(max_length=256, blank=True, null=True)
    captured_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user_id} @ ({self.latitude}, {self.longitude})"


class EscalationAlert(models.Model):
    """Outbound NOK alert from missed check-in / journey escalation (mobile path)."""

    CHANNEL_CHOICES = [("sms", "SMS"), ("email", "Email")]
    STATUS_CHOICES = [("queued", "Queued"), ("sent", "Sent"), ("failed", "Failed")]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="escalation_alerts",
    )
    channel = models.CharField(max_length=16, choices=CHANNEL_CHOICES, default="sms")
    recipient = models.CharField(max_length=128)
    message = models.TextField()
    provider_message_id = models.CharField(max_length=128, blank=True, null=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="queued")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user_id} {self.channel} -> {self.recipient} ({self.status})"


class UserTimelineEvent(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="timeline_events",
    )
    event_type = models.CharField(max_length=64)
    source = models.CharField(max_length=32, default="app")
    status = models.CharField(max_length=32, default="info")
    payload_json = models.JSONField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user_id} {self.event_type} ({self.status})"


class SmsMessage(models.Model):
    DIRECTION_CHOICES = [("outbound", "Outbound"), ("inbound", "Inbound")]
    STATUS_CHOICES = [
        ("queued", "Queued"),
        ("sent", "Sent"),
        ("delivered", "Delivered"),
        ("failed", "Failed"),
        ("received", "Received"),
    ]
    PURPOSE_CHOICES = [
        ("otp", "OTP"),
        ("escalation", "Escalation"),
        ("contact_opt_in", "Contact opt-in"),
        ("test", "Test"),
        ("inbound", "Inbound"),
        ("general", "General"),
    ]

    direction = models.CharField(max_length=16, choices=DIRECTION_CHOICES, default="outbound")
    provider = models.CharField(max_length=32, blank=True, default="")
    purpose = models.CharField(max_length=32, choices=PURPOSE_CHOICES, default="general")
    phone_number = models.CharField(max_length=32, db_index=True)
    message = models.TextField()
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="queued")
    provider_message_id = models.CharField(max_length=128, blank=True, default="", db_index=True)
    cost = models.CharField(max_length=64, blank=True, default="")
    error = models.TextField(blank=True, default="")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="sms_messages",
        blank=True,
        null=True,
    )
    raw_response = models.JSONField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["-created_at"]),
            models.Index(fields=["direction", "status"]),
        ]

    def __str__(self):
        return f"{self.direction} {self.phone_number} ({self.status})"
