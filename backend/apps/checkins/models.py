from django.conf import settings
from django.db import models


class Checkin(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="checkins",
    )
    timestamp = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=32, default="ok")

    def __str__(self):
        return f"{self.user_id} @ {self.timestamp}"


class CallAttempt(models.Model):
    STATUS_CHOICES = [
        ("scheduled", "Scheduled"),
        ("in_progress", "In Progress"),
        ("no_answer", "No Answer"),
        ("safe_confirmed", "Safe Confirmed"),
        ("unsafe_detected", "Unsafe Detected"),
        ("failed", "Failed"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="call_attempts",
    )
    attempt_number = models.IntegerField(default=1)
    provider_call_id = models.CharField(max_length=128, blank=True, null=True)
    status = models.CharField(max_length=32, choices=STATUS_CHOICES, default="scheduled")
    recognized_text = models.TextField(blank=True, null=True)
    scheduled_for = models.DateTimeField(blank=True, null=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user_id} attempt {self.attempt_number} ({self.status})"
