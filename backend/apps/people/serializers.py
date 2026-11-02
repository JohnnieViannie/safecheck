from rest_framework import serializers

from .models import Person, TrustedContact


class PersonSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(read_only=True)
    current_bracelet = serializers.SerializerMethodField()
    last_alert_at = serializers.SerializerMethodField()

    class Meta:
        model = Person
        fields = [
            "id",
            "organization",
            "owner_user",
            "linked_user",
            "first_name",
            "last_name",
            "full_name",
            "email",
            "phone",
            "external_id",
            "notes",
            "is_active",
            "current_bracelet",
            "last_alert_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_current_bracelet(self, obj):
        assignment = (
            obj.assignments.filter(unassigned_at__isnull=True)
            .select_related("bracelet")
            .first()
        )
        if not assignment:
            return None
        return {
            "id": str(assignment.bracelet_id),
            "device_id": assignment.bracelet.device_id,
            "status": assignment.bracelet.status,
        }

    def get_last_alert_at(self, obj):
        alert = obj.alerts.order_by("-received_at").first()
        return alert.received_at if alert else None


class TrustedContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrustedContact
        fields = [
            "id",
            "organization",
            "person",
            "owner_user",
            "name",
            "phone",
            "email",
            "relationship",
            "notify_sms",
            "notify_email",
            "priority",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "owner_user", "created_at", "updated_at"]

    def validate(self, attrs):
        instance = self.instance
        phone = attrs.get("phone", instance.phone if instance else "")
        email = attrs.get("email", instance.email if instance else "")
        if not phone and not email:
            raise serializers.ValidationError({"phone": "Enter a phone number or email."})
        return attrs
