import secrets
import uuid
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from .usernames import generate_username


class PlatformRole(models.TextChoices):
    REGISTRAR = "registrar", "Registrar"


def generate_numeric_code(length: int = 6) -> str:
    # cryptographically stronger than random.randint for OTP
    return "".join(str(secrets.randbelow(10)) for _ in range(length))


class UserManager(BaseUserManager):
    def create_user(self, email=None, password=None, **extra):
        if not email and not extra.get("phone"):
            raise ValueError("A phone number or email is required")
        email = self.normalize_email(email) if email else None
        user = self.model(email=email, **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("is_platform_admin", True)
        extra.setdefault("email_verified", True)
        return self.create_user(email, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True, db_index=True, null=True, blank=True)
    first_name = models.CharField(max_length=150, blank=True)
    last_name = models.CharField(max_length=150, blank=True)
    phone = models.CharField(
        max_length=32, unique=True, null=True, blank=True, help_text="E.164 format"
    )
    phone_verified = models.BooleanField(default=False)
    username = models.CharField(max_length=64, unique=True, blank=True)
    city = models.CharField(max_length=100, blank=True)
    address = models.CharField(max_length=255, blank=True)
    photo = models.ImageField(upload_to="profile_photos/%Y/%m/", null=True, blank=True)
    platform_role = models.CharField(
        max_length=20, choices=PlatformRole.choices, blank=True, default=""
    )
    registered_by = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="registered_users",
        help_text="Staff member who registered this person.",
    )
    country_code = models.CharField(max_length=2, blank=True, help_text="ISO 3166-1 alpha-2")
    sex = models.CharField(
        max_length=20,
        blank=True,
        choices=[
            ("female", "Female"),
            ("male", "Male"),
            ("other", "Other"),
            ("prefer_not", "Prefer not to say"),
        ],
    )
    date_of_birth = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    is_platform_admin = models.BooleanField(default=False)
    email_verified = models.BooleanField(default=False)
    is_muted = models.BooleanField(
        default=False,
        help_text="When muted, suppress alert / SMS notifications for this user.",
    )
    account_type = models.CharField(
        max_length=20,
        choices=[("individual", "Individual"), ("organization", "Organization")],
        default="individual",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.username or self.email or self.phone or str(self.id)

    @property
    def is_registrar(self):
        return self.platform_role == PlatformRole.REGISTRAR

    def clean(self):
        super().clean()
        if not self.email and not self.phone:
            raise ValidationError("A phone number or email is required.")

    def save(self, *args, **kwargs):
        # Unique columns: several empty values are only allowed as NULL, never "".
        self.email = self.email or None
        self.phone = self.phone or None
        if not self.username:
            self.username = generate_username(type(self), self.first_name, self.last_name)
        self.username = self.username.lower()
        super().save(*args, **kwargs)

    @property
    def full_name(self):
        name = f"{self.first_name} {self.last_name}".strip()
        return name or self.email or self.phone or ""

    @property
    def age(self):
        if not self.date_of_birth:
            return None
        today = timezone.localdate()
        years = today.year - self.date_of_birth.year
        if (today.month, today.day) < (self.date_of_birth.month, self.date_of_birth.day):
            years -= 1
        return years


class EmailVerificationToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="email_tokens")
    token = models.CharField(max_length=64, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)

    @classmethod
    def create_for_user(cls, user):
        cls.objects.filter(user=user, used_at__isnull=True).update(used_at=timezone.now())
        minutes = getattr(settings, "EMAIL_CODE_EXPIRY_MINUTES", 15)
        return cls.objects.create(
            user=user,
            token=generate_numeric_code(6),
            expires_at=timezone.now() + timedelta(minutes=minutes),
        )

    @property
    def is_valid(self):
        return self.used_at is None and timezone.now() < self.expires_at


class PhoneVerificationToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="phone_tokens")
    token = models.CharField(max_length=64, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)

    @classmethod
    def create_for_user(cls, user):
        cls.objects.filter(user=user, used_at__isnull=True).update(used_at=timezone.now())
        minutes = getattr(settings, "EMAIL_CODE_EXPIRY_MINUTES", 15)
        return cls.objects.create(
            user=user,
            token=generate_numeric_code(6),
            expires_at=timezone.now() + timedelta(minutes=minutes),
        )

    @property
    def is_valid(self):
        return self.used_at is None and timezone.now() < self.expires_at


class PasswordResetToken(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reset_tokens")
    token = models.CharField(max_length=64, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)

    @classmethod
    def create_for_user(cls, user):
        cls.objects.filter(user=user, used_at__isnull=True).update(used_at=timezone.now())
        minutes = getattr(settings, "PASSWORD_RESET_CODE_EXPIRY_MINUTES", 15)
        return cls.objects.create(
            user=user,
            token=generate_numeric_code(6),
            expires_at=timezone.now() + timedelta(minutes=minutes),
        )

    @property
    def is_valid(self):
        return self.used_at is None and timezone.now() < self.expires_at
