from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.utils import timezone
from rest_framework import serializers

from apps.organizations.models import Organization

from .phone import normalize_phone

User = get_user_model()


def clean_phone(value, country_code=None, exclude_user_id=None) -> str:
    """Normalize a phone to E164 and make sure no other account uses it."""
    phone = normalize_phone(value, country_code)
    if not phone:
        raise serializers.ValidationError(
            "Enter a valid phone number, including the country code."
        )
    existing = User.objects.filter(phone=phone)
    if exclude_user_id:
        existing = existing.exclude(id=exclude_user_id)
    if existing.exists():
        raise serializers.ValidationError("An account with this phone number already exists.")
    return phone


def clean_optional_email(value, exclude_user_id=None):
    email = (value or "").strip().lower()
    if not email:
        return None
    existing = User.objects.filter(email__iexact=email)
    if exclude_user_id:
        existing = existing.exclude(id=exclude_user_id)
    if existing.exists():
        raise serializers.ValidationError("An account with this email already exists.")
    return email


class EditablePhoneMixin(serializers.Serializer):
    """Phone field for profile edits. Changing the number means it must be verified again."""

    phone = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=32)

    def validate_phone(self, value):
        if not (value or "").strip():
            return None
        instance = getattr(self, "instance", None)
        country_code = self.initial_data.get("country_code") or getattr(
            instance, "country_code", None
        )
        return clean_phone(value, country_code, exclude_user_id=getattr(instance, "id", None))

    def update(self, instance, validated_data):
        if "phone" in validated_data and validated_data["phone"] != instance.phone:
            validated_data["phone_verified"] = False
        return super().update(instance, validated_data)


class UserSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(read_only=True)
    age = serializers.IntegerField(read_only=True, allow_null=True)
    memberships = serializers.SerializerMethodField()
    bracelet_count = serializers.SerializerMethodField()
    person_count = serializers.SerializerMethodField()
    has_app_profile = serializers.SerializerMethodField()
    has_watch = serializers.SerializerMethodField()
    sources = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    photo_url = serializers.SerializerMethodField()
    has_device = serializers.SerializerMethodField()
    device_id = serializers.SerializerMethodField()
    organization_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "email",
            "first_name",
            "last_name",
            "full_name",
            "phone",
            "country_code",
            "city",
            "address",
            "photo_url",
            "platform_role",
            "has_device",
            "device_id",
            "organization_name",
            "sex",
            "date_of_birth",
            "age",
            "is_active",
            "is_muted",
            "is_platform_admin",
            "email_verified",
            "phone_verified",
            "account_type",
            "memberships",
            "bracelet_count",
            "person_count",
            "has_app_profile",
            "has_watch",
            "sources",
            "status_label",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "username",
            "photo_url",
            "platform_role",
            "has_device",
            "device_id",
            "organization_name",
            "full_name",
            "age",
            "memberships",
            "bracelet_count",
            "person_count",
            "has_app_profile",
            "has_watch",
            "sources",
            "status_label",
            "created_at",
            "updated_at",
            "is_platform_admin",
            "email_verified",
            "phone_verified",
            "account_type",
        ]

    def get_photo_url(self, obj):
        if not obj.photo:
            return None
        request = self.context.get("request")
        return request.build_absolute_uri(obj.photo.url) if request else obj.photo.url

    def get_device_id(self, obj):
        if hasattr(obj, "_device_id"):
            return obj._device_id
        from apps.devices.services import current_bracelet_for_user

        bracelet = current_bracelet_for_user(obj)
        return bracelet.device_id if bracelet else None

    def get_organization_name(self, obj):
        """The organization someone wears a bracelet with, or works in as staff."""
        if hasattr(obj, "_person_organization"):
            if obj._person_organization:
                return obj._person_organization
        else:
            person = obj.person_profiles.select_related("organization").filter(
                organization__isnull=False
            ).first()
            if person:
                return person.organization.name
        membership = obj.memberships.select_related("organization").filter(is_active=True).first()
        return membership.organization.name if membership else None

    def get_has_device(self, obj):
        return bool(self.get_device_id(obj))

    def get_memberships(self, obj):
        from apps.organizations.serializers import MembershipBriefSerializer

        qs = obj.memberships.select_related("organization").filter(is_active=True)
        return MembershipBriefSerializer(qs, many=True).data

    def get_bracelet_count(self, obj):
        if getattr(obj, "_bracelet_count", None) is not None:
            return obj._bracelet_count
        return obj.bracelets.count()

    def get_person_count(self, obj):
        owned = getattr(obj, "_owned_people", None)
        linked = getattr(obj, "_linked_people", None)
        if owned is not None and linked is not None:
            return int(owned) + int(linked)
        return obj.owned_people.count() + obj.person_profiles.count()

    def get_has_app_profile(self, obj):
        flagged = getattr(obj, "_has_app_profile", None)
        if flagged is not None:
            return bool(flagged)
        from apps.safety.models import SafetyProfile

        return SafetyProfile.objects.filter(user_id=obj.id).exists()

    def get_has_watch(self, obj):
        count = self.get_bracelet_count(obj)
        return bool(count and count > 0)

    def get_sources(self, obj):
        labels = []
        if self.get_has_app_profile(obj) or obj.account_type:
            labels.append("app")
        if self.get_has_watch(obj):
            labels.append("watch")
        if obj.account_type == "organization" or obj.memberships.filter(is_active=True).exists():
            if "org" not in labels:
                labels.append("org")
        return labels or ["app"]

    def get_status_label(self, obj):
        if not obj.is_active:
            return "blocked"
        if obj.is_muted:
            return "muted"
        return "active"


class UserDetailSerializer(UserSerializer):
    """One user's full record for the management page."""

    person_id = serializers.SerializerMethodField()
    current_device = serializers.SerializerMethodField()
    device_history = serializers.SerializerMethodField()
    registered_by_name = serializers.CharField(
        source="registered_by.full_name", read_only=True, default=None
    )

    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields + [
            "person_id",
            "current_device",
            "device_history",
            "registered_by_name",
        ]

    def get_person_id(self, obj):
        from apps.devices.services import person_for_user

        person = person_for_user(obj)
        return str(person.id) if person else None

    def get_current_device(self, obj):
        from apps.devices.serializers import BraceletSerializer
        from apps.devices.services import current_bracelet_for_user

        bracelet = current_bracelet_for_user(obj)
        return BraceletSerializer(bracelet).data if bracelet else None

    def get_device_history(self, obj):
        from apps.devices.models import BraceletAssignment
        from apps.devices.serializers import BraceletAssignmentSerializer
        from apps.devices.services import people_for_user

        assignments = BraceletAssignment.objects.filter(
            person__in=people_for_user(obj)
        ).select_related("person", "bracelet", "assigned_by")
        return BraceletAssignmentSerializer(assignments, many=True).data


class AdminUserUpdateSerializer(EditablePhoneMixin, serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            "first_name",
            "last_name",
            "phone",
            "country_code",
            "city",
            "address",
            "sex",
            "date_of_birth",
            "is_active",
            "is_muted",
        ]


class AdminUserCreateSerializer(serializers.Serializer):
    """Staff register a person with their bracelet. They set a password later."""

    phone = serializers.CharField(max_length=32)
    device_id = serializers.CharField(max_length=100)
    city = serializers.CharField(max_length=100)
    date_of_birth = serializers.DateField()
    address = serializers.CharField(required=False, allow_blank=True, default="", max_length=255)
    country_code = serializers.CharField(required=False, allow_blank=True, default="", max_length=2)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, default="", max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True, allow_null=True, default=None)
    organization = serializers.PrimaryKeyRelatedField(
        queryset=Organization.objects.all(), required=False, allow_null=True, default=None
    )

    def validate_email(self, value):
        return clean_optional_email(value)

    def validate_date_of_birth(self, value):
        today = timezone.localdate()
        if value > today:
            raise serializers.ValidationError("Date of birth can't be in the future.")
        if today.year - value.year > 120:
            raise serializers.ValidationError("Enter a valid date of birth.")
        return value

    def validate(self, attrs):
        attrs["country_code"] = (attrs.get("country_code") or "").upper()
        try:
            attrs["phone"] = clean_phone(attrs["phone"], attrs["country_code"])
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({"phone": exc.detail})
        return attrs


class StaffInviteSerializer(serializers.Serializer):
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, default="", max_length=150)
    phone = serializers.CharField(max_length=32)
    email = serializers.EmailField(required=False, allow_blank=True, allow_null=True, default=None)
    country_code = serializers.CharField(required=False, allow_blank=True, default="", max_length=2)

    def validate(self, attrs):
        attrs["country_code"] = (attrs.get("country_code") or "").upper()
        phone = normalize_phone(attrs["phone"], attrs["country_code"])
        if not phone:
            raise serializers.ValidationError(
                {"phone": "Enter a valid phone number, including the country code."}
            )
        attrs["phone"] = phone
        attrs["email"] = (attrs.get("email") or "").strip().lower() or None
        by_phone = User.objects.filter(phone=phone).first()
        by_email = (
            User.objects.filter(email__iexact=attrs["email"]).first() if attrs["email"] else None
        )
        if by_email and (by_phone != by_email if by_phone else bool(by_email.phone)):
            raise serializers.ValidationError(
                {"email": "This email belongs to an account with a different phone number."}
            )
        existing = by_phone or by_email
        if existing and existing.is_platform_admin:
            raise serializers.ValidationError({"phone": "This person is already a super admin."})
        if existing and existing.is_registrar:
            raise serializers.ValidationError({"phone": "This person is already a registrar."})
        attrs["existing"] = existing
        return attrs


class StaffSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(read_only=True)
    pending = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "full_name",
            "phone",
            "email",
            "platform_role",
            "is_active",
            "pending",
            "created_at",
        ]

    def get_pending(self, obj):
        return not obj.has_usable_password()


class IdentifierSerializer(serializers.Serializer):
    """Accepts a username, phone or email as `identifier`. `email` still works for older clients."""

    identifier = serializers.CharField(required=False, allow_blank=True)
    email = serializers.CharField(required=False, allow_blank=True)
    phone = serializers.CharField(required=False, allow_blank=True)
    country_code = serializers.CharField(required=False, allow_blank=True, default="", max_length=2)

    def validate(self, attrs):
        identifier = (
            attrs.get("identifier") or attrs.get("email") or attrs.get("phone") or ""
        ).strip()
        if not identifier:
            raise serializers.ValidationError(
                {"identifier": "Enter your username, phone number or email."}
            )
        attrs["identifier"] = identifier
        return attrs


class LoginSerializer(IdentifierSerializer):
    password = serializers.CharField(write_only=True)


class ProfileUpdateSerializer(EditablePhoneMixin, serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            "first_name",
            "last_name",
            "phone",
            "country_code",
            "city",
            "address",
            "sex",
            "date_of_birth",
        ]


class PasswordResetRequestSerializer(IdentifierSerializer):
    pass


class PasswordResetConfirmSerializer(IdentifierSerializer):
    code = serializers.CharField(min_length=6, max_length=6)
    password = serializers.CharField(min_length=6, required=False)
    newPassword = serializers.CharField(min_length=6, required=False)
    verificationId = serializers.CharField(required=False, allow_blank=True)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        password = attrs.get("password") or attrs.get("newPassword")
        if not password:
            raise serializers.ValidationError(
                {"password": "password or newPassword is required."}
            )
        validate_password(password)
        attrs["password"] = password
        return attrs

    def validate_code(self, value):
        if not value.isdigit():
            raise serializers.ValidationError("Code must be 6 digits.")
        return value


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField()
    new_password = serializers.CharField(min_length=8)

    def validate_new_password(self, value):
        validate_password(value)
        return value


class VerifyCodeSerializer(IdentifierSerializer):
    code = serializers.CharField(min_length=6, max_length=6)

    def validate_code(self, value):
        if not value.isdigit():
            raise serializers.ValidationError("Code must be 6 digits.")
        return value


class ResendCodeSerializer(IdentifierSerializer):
    pass
