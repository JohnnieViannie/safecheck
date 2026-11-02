import hashlib
import uuid

from django.db import models


class AlertCode(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    code = models.CharField(max_length=50, unique=True)
    label = models.CharField(max_length=100)
    severity = models.CharField(
        max_length=20,
        choices=[
            ("info", "Info"),
            ("warning", "Warning"),
            ("critical", "Critical"),
        ],
        default="critical",
    )
    is_active = models.BooleanField(default=True)
    description = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.code


class InboundSmsEvent(models.Model):
    class ProcessStatus(models.TextChoices):
        RECEIVED = "RECEIVED", "Received"
        PROCESSED = "PROCESSED", "Processed"
        DUPLICATE = "DUPLICATE", "Duplicate"
        FAILED = "FAILED", "Failed"
        IGNORED = "IGNORED", "Ignored"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    idempotency_key = models.CharField(max_length=128, unique=True, db_index=True)
    provider_message_id = models.CharField(max_length=128, blank=True, db_index=True)
    sender = models.CharField(max_length=64, blank=True)
    recipient = models.CharField(max_length=64, blank=True)
    text = models.TextField()
    raw_payload = models.JSONField(default=dict)
    status = models.CharField(
        max_length=20, choices=ProcessStatus.choices, default=ProcessStatus.RECEIVED
    )
    error_message = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    @staticmethod
    def make_idempotency_key(provider_id: str, sender: str, text: str, date: str) -> str:
        if provider_id:
            return f"at:{provider_id}"
        raw = f"{sender}|{text}|{date}"
        return "hash:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()


class Alert(models.Model):
    class ProcessingStatus(models.TextChoices):
        NEW = "NEW", "New"
        PROCESSED = "PROCESSED", "Processed"
        FAILED = "FAILED", "Failed"
        IGNORED = "IGNORED", "Ignored"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    bracelet = models.ForeignKey(
        "devices.Bracelet",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="alerts",
    )
    person = models.ForeignKey(
        "people.Person",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="alerts",
    )
    organization = models.ForeignKey(
        "organizations.Organization",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="alerts",
    )
    owner_user = models.ForeignKey(
        "accounts.User",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="alerts",
    )
    class LocationSource(models.TextChoices):
        GPS = "gps", "GPS"
        OPENCELLID = "opencellid", "OpenCellID"
        SMS = "sms", "SMS"

    alert_code = models.CharField(max_length=50, db_index=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_label = models.CharField(max_length=500, blank=True)
    location_area = models.CharField(
        max_length=200, blank=True, help_text="Short place name used in text messages."
    )
    location_source = models.CharField(
        max_length=20,
        choices=LocationSource.choices,
        default=LocationSource.SMS,
        blank=True,
    )
    location_accuracy_m = models.PositiveIntegerField(null=True, blank=True)
    received_at = models.DateTimeField(db_index=True)
    raw_payload = models.JSONField(default=dict)
    processing_status = models.CharField(
        max_length=20,
        choices=ProcessingStatus.choices,
        default=ProcessingStatus.NEW,
    )
    inbound_event = models.OneToOneField(
        InboundSmsEvent,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="alert",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-received_at"]
        indexes = [
            models.Index(fields=["organization", "received_at"]),
            models.Index(fields=["alert_code", "received_at"]),
        ]
