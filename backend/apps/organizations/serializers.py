from django.contrib.auth import get_user_model
from rest_framework import serializers

from apps.accounts.phone import normalize_phone

from .models import Invitation, MembershipRole, Organization, OrganizationMembership

User = get_user_model()


class OrganizationSerializer(serializers.ModelSerializer):
    member_count = serializers.SerializerMethodField()
    people_count = serializers.SerializerMethodField()

    class Meta:
        model = Organization
        fields = [
            "id",
            "name",
            "slug",
            "description",
            "email",
            "phone",
            "address",
            "is_active",
            "member_count",
            "people_count",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "slug", "created_at", "updated_at", "member_count", "people_count"]

    def get_member_count(self, obj):
        return obj.memberships.filter(is_active=True).count()

    def get_people_count(self, obj):
        return obj.people.filter(is_active=True).count()


class OrganizationCreateSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=255)
    description = serializers.CharField(required=False, allow_blank=True, default="")
    email = serializers.EmailField(required=False, allow_blank=True, default="")
    phone = serializers.CharField(required=False, allow_blank=True, default="")
    address = serializers.CharField(required=False, allow_blank=True, default="")


class OrganizationOnboardSerializer(OrganizationCreateSerializer):
    """Super admin adds an organization along with the representative who will own it."""

    owner_first_name = serializers.CharField(max_length=150)
    owner_last_name = serializers.CharField(required=False, allow_blank=True, default="", max_length=150)
    owner_phone = serializers.CharField(max_length=32)
    owner_email = serializers.EmailField(required=False, allow_blank=True, allow_null=True, default=None)
    country_code = serializers.CharField(required=False, allow_blank=True, default="", max_length=2)

    def validate(self, attrs):
        attrs["country_code"] = (attrs.get("country_code") or "").upper()
        phone = normalize_phone(attrs["owner_phone"], attrs["country_code"])
        if not phone:
            raise serializers.ValidationError(
                {"owner_phone": "Enter a valid phone number, including the country code."}
            )
        attrs["owner_phone"] = phone
        attrs["owner_email"] = (attrs.get("owner_email") or "").strip().lower() or None

        by_phone = User.objects.filter(phone=phone).first()
        by_email = (
            User.objects.filter(email__iexact=attrs["owner_email"]).first()
            if attrs["owner_email"]
            else None
        )
        if by_email and (by_phone != by_email if by_phone else bool(by_email.phone)):
            raise serializers.ValidationError(
                {"owner_email": "This email belongs to an account with a different phone number."}
            )
        existing = by_phone or by_email
        if existing and existing.is_platform_admin:
            raise serializers.ValidationError(
                {"owner_phone": "A platform admin can't own an organization."}
            )
        attrs["existing_owner"] = existing
        return attrs


class MembershipBriefSerializer(serializers.ModelSerializer):
    organization_id = serializers.UUIDField(source="organization.id")
    organization_name = serializers.CharField(source="organization.name")

    class Meta:
        model = OrganizationMembership
        fields = ["id", "organization_id", "organization_name", "role", "is_active"]


class MembershipSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(source="user.email", read_only=True)
    user_phone = serializers.CharField(source="user.phone", read_only=True)
    user_name = serializers.CharField(source="user.full_name", read_only=True)
    user_id = serializers.UUIDField(source="user.id", read_only=True)

    class Meta:
        model = OrganizationMembership
        fields = [
            "id",
            "organization",
            "user_id",
            "user_email",
            "user_phone",
            "user_name",
            "role",
            "is_active",
            "created_at",
        ]
        read_only_fields = ["id", "organization", "created_at"]


class InvitationSerializer(serializers.ModelSerializer):
    organization_name = serializers.CharField(source="organization.name", read_only=True)
    is_valid = serializers.BooleanField(read_only=True)

    class Meta:
        model = Invitation
        fields = [
            "id",
            "organization",
            "organization_name",
            "email",
            "phone",
            "role",
            "created_at",
            "expires_at",
            "accepted_at",
            "revoked_at",
            "is_valid",
        ]
        read_only_fields = [
            "id",
            "organization",
            "created_at",
            "expires_at",
            "accepted_at",
            "revoked_at",
            "is_valid",
        ]


class InvitationCreateSerializer(serializers.Serializer):
    first_name = serializers.CharField(required=False, allow_blank=True, default="", max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, default="", max_length=150)
    phone = serializers.CharField(required=False, allow_blank=True, default="", max_length=32)
    email = serializers.EmailField(required=False, allow_blank=True, default="")
    country_code = serializers.CharField(required=False, allow_blank=True, default="", max_length=2)
    role = serializers.ChoiceField(
        choices=MembershipRole.choices, default=MembershipRole.STAFF
    )

    def validate(self, attrs):
        if not attrs["phone"] and not attrs["email"]:
            raise serializers.ValidationError({"phone": "Enter a phone number or email."})
        if attrs["phone"]:
            phone = normalize_phone(attrs["phone"], attrs["country_code"])
            if not phone:
                raise serializers.ValidationError(
                    {"phone": "Enter a valid phone number, including the country code."}
                )
            attrs["phone"] = phone
        return attrs


class InvitationAcceptSerializer(serializers.Serializer):
    token = serializers.CharField()
