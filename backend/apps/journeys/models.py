import uuid

from django.conf import settings
from django.db import models


class JourneySession(models.Model):
    STATUS_CHOICES = [
        ("active", "Active"),
        ("completed", "Completed"),
        ("cancelled", "Cancelled"),
        ("missed", "Missed"),
    ]
    FREQUENCY_CHOICES = [
        ("none", "None"),
        ("30", "Every 30 min"),
        ("60", "Every 1 hour"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="journeys",
    )
    from_location = models.CharField(max_length=256)
    to_location = models.CharField(max_length=256)
    duration_minutes = models.IntegerField()
    checkin_frequency = models.CharField(
        max_length=16,
        choices=FREQUENCY_CHOICES,
        default="none",
    )
    started_at = models.DateTimeField(auto_now_add=True)
    expected_arrival_at = models.DateTimeField()
    arrived_at = models.DateTimeField(blank=True, null=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="active")
    last_latitude = models.FloatField(blank=True, null=True)
    last_longitude = models.FloatField(blank=True, null=True)

    class Meta:
        ordering = ["-started_at"]

    def __str__(self):
        return f"{self.user_id} journey {self.status}"
