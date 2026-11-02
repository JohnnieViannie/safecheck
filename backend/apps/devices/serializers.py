from rest_framework import serializers

from .models import Bracelet, BraceletAssignment


class BraceletSerializer(serializers.ModelSerializer):
    person_name = serializers.SerializerMethodField()
    organization_name = serializers.CharField(
        source="organization.name", read_only=True, default=None
    )
    last_alert_at = serializers.SerializerMethodField()

    class Meta:
        model = Bracelet
        fields = [
            "id",
            "device_id",
            "serial_number",
            "status",
            "organization",
            "organization_name",
            "owner_user",
            "current_person",
            "person_name",
            "activated_at",
            "notes",
            "last_alert_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "current_person",
            "activated_at",
            "created_at",
            "updated_at",
        ]

    def get_person_name(self, obj):
        return obj.current_person.full_name if obj.current_person else None

    def get_last_alert_at(self, obj):
        alert = obj.alerts.order_by("-received_at").first()
        return alert.received_at if alert else None


class BraceletAssignmentSerializer(serializers.ModelSerializer):
    person_name = serializers.CharField(source="person.full_name", read_only=True)
    device_id = serializers.CharField(source="bracelet.device_id", read_only=True)
    assigned_by_email = serializers.EmailField(
        source="assigned_by.email", read_only=True, default=None
    )

    class Meta:
        model = BraceletAssignment
        fields = [
            "id",
            "bracelet",
            "device_id",
            "person",
            "person_name",
            "organization",
            "assigned_at",
            "unassigned_at",
            "assigned_by",
            "assigned_by_email",
            "reason",
        ]


class AssignBraceletSerializer(serializers.Serializer):
    person_id = serializers.UUIDField()
    reason = serializers.CharField(required=False, allow_blank=True, default="")
