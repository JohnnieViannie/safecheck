from rest_framework import serializers
from .models import AlertEvent, CallAttempt, Checkin, LocationSnapshot, UserProfile, UserTimelineEvent

class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserProfile
        fields = [
            'uid',
            'full_name',
            'email',
            'phone_number',
            'onboarding_completed',
            'user_type',
            'checkin_frequency',
            'grace_period_hours',
            'emergency_contact_name',
            'emergency_contact_relationship',
            'emergency_contact_country_code',
            'emergency_contact_phone',
            'emergency_contact_email',
            'last_check_in_at',
            'checkin_time',
            'timezone',
            'max_retry_attempts',
            'last_call_status',
            'escalation_status',
            'last_escalated_at',
            'next_scheduled_checkin_at',
            'fcm_platform',
            'fcm_token_updated_at',
            'snoozed_until',
            'last_push_sent_at',
        ]

class CheckinSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.uid')

    class Meta:
        model = Checkin
        fields = ['id', 'user_id', 'timestamp', 'status']


class LocationSnapshotSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.uid', read_only=True)

    class Meta:
        model = LocationSnapshot
        fields = [
            'id',
            'user_id',
            'latitude',
            'longitude',
            'accuracy_meters',
            'address',
            'captured_at',
        ]


class CallAttemptSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.uid', read_only=True)

    class Meta:
        model = CallAttempt
        fields = [
            'id',
            'user_id',
            'attempt_number',
            'provider_call_id',
            'status',
            'recognized_text',
            'scheduled_for',
            'completed_at',
            'created_at',
        ]


class AlertEventSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.uid', read_only=True)

    class Meta:
        model = AlertEvent
        fields = [
            'id',
            'user_id',
            'channel',
            'recipient',
            'message',
            'provider_message_id',
            'status',
            'created_at',
        ]


class UserTimelineEventSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.uid', read_only=True)

    class Meta:
        model = UserTimelineEvent
        fields = [
            'id',
            'user_id',
            'event_type',
            'source',
            'status',
            'payload_json',
            'created_at',
        ]
