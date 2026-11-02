from django.conf import settings
from django.db import models


class VaultDocument(models.Model):
    STATUS_CHOICES = [("active", "Active"), ("empty", "Empty")]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="vault_documents",
    )
    doc_id = models.CharField(max_length=64)
    title = models.CharField(max_length=256)
    file = models.FileField(upload_to="vault/%Y/%m/", blank=True, null=True)
    format = models.CharField(max_length=16, blank=True, default="")
    size_bytes = models.IntegerField(default=0)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="active")
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("user", "doc_id")

    def __str__(self):
        return f"{self.user_id} {self.title}"


class VaultReleaseToken(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="vault_release_tokens",
    )
    token = models.CharField(max_length=128, unique=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user_id} release {self.token[:8]}"
