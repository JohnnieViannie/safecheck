from django.db import models

class UserProfile(models.Model):
    uid = models.CharField(max_length=128, primary_key=True)
    full_name = models.CharField(max_length=128, blank=True, null=True)
    email = models.EmailField(unique=True, blank=True, null=True)
    password = models.CharField(max_length=128, blank=True, null=True)
    phone_number = models.CharField(max_length=32, blank=True, null=True)
    onboarding_completed = models.BooleanField(default=False)
    user_type = models.CharField(max_length=32, blank=True, null=True)
    checkin_frequency = models.CharField(max_length=32, blank=True, null=True)
    grace_period_hours = models.IntegerField(blank=True, null=True)
    emergency_contact_name = models.CharField(max_length=128, blank=True, null=True)
    emergency_contact_relationship = models.CharField(max_length=64, blank=True, null=True)
    emergency_contact_country_code = models.CharField(max_length=2, default='UG')
    emergency_contact_phone = models.CharField(max_length=32, blank=True, null=True)
    emergency_contact_email = models.EmailField(blank=True, null=True)
    pin = models.CharField(max_length=128, blank=True, null=True)
    last_check_in_at = models.DateTimeField(blank=True, null=True)
    checkin_time = models.TimeField(blank=True, null=True)
    timezone = models.CharField(max_length=64, default='UTC')
    max_retry_attempts = models.IntegerField(default=3)
    last_call_status = models.CharField(max_length=32, default='idle')
    escalation_status = models.CharField(max_length=32, default='none')
    last_escalated_at = models.DateTimeField(blank=True, null=True)
    next_scheduled_checkin_at = models.DateTimeField(blank=True, null=True)
    fcm_token = models.CharField(max_length=512, blank=True, null=True)
    fcm_token_updated_at = models.DateTimeField(blank=True, null=True)
    fcm_platform = models.CharField(max_length=16, blank=True, null=True)
    snoozed_until = models.DateTimeField(blank=True, null=True)
    last_push_sent_at = models.DateTimeField(blank=True, null=True)
    pending_call_kit_id = models.CharField(max_length=64, blank=True, null=True)

    def confirmed_safe_after_last_push(self) -> bool:
        """True if the user completed a safe check-in after the last server push."""
        if not self.last_push_sent_at:
            return False
        if self.last_call_status == 'safe_confirmed':
            return True
        if self.last_check_in_at and self.last_check_in_at >= self.last_push_sent_at:
            return True
        return False

    def __str__(self):
        return f"{self.uid} ({self.email or self.phone_number})"

class Checkin(models.Model):
    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE)
    timestamp = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=32, default='ok')

    def __str__(self):
        return f"{self.user.uid} @ {self.timestamp}"


class LocationSnapshot(models.Model):
    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='locations')
    latitude = models.FloatField()
    longitude = models.FloatField()
    accuracy_meters = models.FloatField(blank=True, null=True)
    address = models.CharField(max_length=256, blank=True, null=True)
    captured_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.uid} @ ({self.latitude}, {self.longitude})"


class CallAttempt(models.Model):
    STATUS_CHOICES = [
        ('scheduled', 'Scheduled'),
        ('in_progress', 'In Progress'),
        ('no_answer', 'No Answer'),
        ('safe_confirmed', 'Safe Confirmed'),
        ('unsafe_detected', 'Unsafe Detected'),
        ('failed', 'Failed'),
    ]

    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='call_attempts')
    attempt_number = models.IntegerField(default=1)
    provider_call_id = models.CharField(max_length=128, blank=True, null=True)
    status = models.CharField(max_length=32, choices=STATUS_CHOICES, default='scheduled')
    recognized_text = models.TextField(blank=True, null=True)
    scheduled_for = models.DateTimeField(blank=True, null=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.uid} attempt {self.attempt_number} ({self.status})"


class AlertEvent(models.Model):
    CHANNEL_CHOICES = [
        ('sms', 'SMS'),
        ('email', 'Email'),
    ]
    STATUS_CHOICES = [
        ('queued', 'Queued'),
        ('sent', 'Sent'),
        ('failed', 'Failed'),
    ]

    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='alert_events')
    channel = models.CharField(max_length=16, choices=CHANNEL_CHOICES, default='sms')
    recipient = models.CharField(max_length=128)
    message = models.TextField()
    provider_message_id = models.CharField(max_length=128, blank=True, null=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default='queued')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.uid} {self.channel} -> {self.recipient} ({self.status})"


class UserTimelineEvent(models.Model):
    user = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name='timeline_events')
    event_type = models.CharField(max_length=64)
    source = models.CharField(max_length=32, default='app')
    status = models.CharField(max_length=32, default='info')
    payload_json = models.JSONField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.uid} {self.event_type} ({self.status})"
