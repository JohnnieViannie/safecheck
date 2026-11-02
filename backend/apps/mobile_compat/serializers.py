"""Mobile-compatible serializers matching SafeCheck Flutter payloads."""
from rest_framework import serializers

from apps.checkins.models import CallAttempt, Checkin
from apps.journeys.models import JourneySession
from apps.mobile_compat.identity import contacts_json_for_profile
from apps.safety.models import EscalationAlert, LocationSnapshot, SafetyProfile, UserTimelineEvent


class SafetyProfileSerializer(serializers.ModelSerializer):
    uid = serializers.CharField(source="legacy_uid", read_only=True)
    full_name = serializers.SerializerMethodField()
    email = serializers.SerializerMethodField()
    phone_number = serializers.SerializerMethodField()
    pin_set = serializers.SerializerMethodField()
    emergency_contacts_json = serializers.SerializerMethodField()

    class Meta:
        model = SafetyProfile
        fields = [
            "uid",
            "full_name",
            "email",
            "phone_number",
            "onboarding_completed",
            "onboarding_step",
            "onboarding_draft_json",
            "user_type",
            "checkin_frequency",
            "grace_period_hours",
            "grace_period_minutes",
            "emergency_contact_name",
            "emergency_contact_relationship",
            "emergency_contact_country_code",
            "emergency_contact_phone",
            "emergency_contact_email",
            "emergency_contacts_json",
            "trigger_actions_json",
            "notification_prefs_json",
            "pin_set",
            "last_check_in_at",
            "checkin_time",
            "timezone",
            "max_retry_attempts",
            "last_call_status",
            "escalation_status",
            "last_escalated_at",
            "next_scheduled_checkin_at",
            "fcm_platform",
            "fcm_token_updated_at",
            "snoozed_until",
            "last_push_sent_at",
        ]

    def get_full_name(self, obj):
        return obj.user.full_name

    def get_email(self, obj):
        return obj.user.email or ""

    def get_phone_number(self, obj):
        return obj.user.phone or ""

    def get_pin_set(self, obj):
        return bool((obj.pin or "").strip())

    def get_emergency_contacts_json(self, obj):
        return contacts_json_for_profile(obj)


class CheckinSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()

    class Meta:
        model = Checkin
        fields = ["id", "user_id", "timestamp", "status"]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)


class LocationSnapshotSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()

    class Meta:
        model = LocationSnapshot
        fields = [
            "id",
            "user_id",
            "latitude",
            "longitude",
            "accuracy_meters",
            "address",
            "captured_at",
        ]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)


class CallAttemptSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()

    class Meta:
        model = CallAttempt
        fields = [
            "id",
            "user_id",
            "attempt_number",
            "provider_call_id",
            "status",
            "recognized_text",
            "scheduled_for",
            "completed_at",
            "created_at",
        ]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)


class AlertEventSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()

    class Meta:
        model = EscalationAlert
        fields = [
            "id",
            "user_id",
            "channel",
            "recipient",
            "message",
            "provider_message_id",
            "status",
            "created_at",
        ]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)


class UserTimelineEventSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()

    class Meta:
        model = UserTimelineEvent
        fields = [
            "id",
            "user_id",
            "event_type",
            "source",
            "status",
            "payload_json",
            "created_at",
        ]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)


class JourneySessionSerializer(serializers.ModelSerializer):
    user_id = serializers.SerializerMethodField()
    journey_id = serializers.UUIDField(source="id", read_only=True)

    class Meta:
        model = JourneySession
        fields = [
            "journey_id",
            "user_id",
            "from_location",
            "to_location",
            "duration_minutes",
            "checkin_frequency",
            "started_at",
            "expected_arrival_at",
            "arrived_at",
            "status",
            "last_latitude",
            "last_longitude",
        ]

    def get_user_id(self, obj):
        profile = getattr(obj.user, "safety_profile", None)
        return profile.legacy_uid if profile else str(obj.user_id)
