import uuid

from django.conf import settings
from django.db import models


class BraceletStatus(models.TextChoices):
    MANUFACTURED = "MANUFACTURED", "Manufactured"
    INVENTORY = "INVENTORY", "Inventory"
    ACTIVATED = "ACTIVATED", "Activated"
    ASSIGNED = "ASSIGNED", "Assigned"
    IN_USE = "IN_USE", "In use"
    UNASSIGNED = "UNASSIGNED", "Unassigned"
    DEACTIVATED = "DEACTIVATED", "Deactivated"


class Bracelet(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device_id = models.CharField(max_length=100, unique=True, db_index=True)
    serial_number = models.CharField(max_length=100, blank=True, db_index=True)
    status = models.CharField(
        max_length=20,
        choices=BraceletStatus.choices,
        default=BraceletStatus.MANUFACTURED,
        db_index=True,
    )
    organization = models.ForeignKey(
        "organizations.Organization",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="bracelets",
    )
    owner_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="bracelets",
        help_text="Individual owner when not org-owned.",
    )
    current_person = models.ForeignKey(
        "people.Person",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="current_bracelets",
    )
    activated_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.device_id


class BraceletAssignment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    bracelet = models.ForeignKey(
        Bracelet, on_delete=models.CASCADE, related_name="assignments"
    )
    person = models.ForeignKey(
        "people.Person", on_delete=models.CASCADE, related_name="assignments"
    )
    organization = models.ForeignKey(
        "organizations.Organization",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="bracelet_assignments",
    )
    assigned_at = models.DateTimeField(auto_now_add=True)
    unassigned_at = models.DateTimeField(null=True, blank=True)
    assigned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="bracelet_assignments_made",
    )
    reason = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["-assigned_at"]
        indexes = [
            models.Index(fields=["bracelet", "unassigned_at"]),
        ]
