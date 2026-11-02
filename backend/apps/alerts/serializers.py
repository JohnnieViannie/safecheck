from rest_framework import serializers

from .models import Alert, AlertCode, InboundSmsEvent


class AlertSerializer(serializers.ModelSerializer):
    person_name = serializers.CharField(source="person.full_name", read_only=True, default=None)
    device_id = serializers.CharField(source="bracelet.device_id", read_only=True, default=None)
    organization_name = serializers.CharField(
        source="organization.name", read_only=True, default=None
    )
    incident_id = serializers.SerializerMethodField()

    class Meta:
        model = Alert
        fields = [
            "id",
            "bracelet",
            "device_id",
            "person",
            "person_name",
            "organization",
            "organization_name",
            "owner_user",
            "alert_code",
            "latitude",
            "longitude",
            "location_label",
            "location_area",
            "location_source",
            "location_accuracy_m",
            "received_at",
            "processing_status",
            "incident_id",
            "created_at",
        ]

    def get_incident_id(self, obj):
        try:
            return str(obj.incident.id)
        except Exception:
            return None


class AlertCodeSerializer(serializers.ModelSerializer):
    class Meta:
        model = AlertCode
        fields = ["id", "code", "label", "severity", "is_active", "description"]


class InboundSmsEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = InboundSmsEvent
        fields = [
            "id",
            "idempotency_key",
            "provider_message_id",
            "sender",
            "text",
            "status",
            "error_message",
            "created_at",
            "processed_at",
        ]


class BraceletGpsSosSerializer(serializers.Serializer):
    device_id = serializers.CharField(max_length=100)
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    timestamp = serializers.CharField(required=False, allow_blank=True, default="")
    phone = serializers.CharField(max_length=32)
    alert_code = serializers.CharField(max_length=50, required=False, default="SOS")

    def validate(self, attrs):
        lat = float(attrs["latitude"])
        lng = float(attrs["longitude"])
        if not (-90 <= lat <= 90 and -180 <= lng <= 180):
            raise serializers.ValidationError({"coordinates": "Out of range."})
        attrs["alert_code"] = (attrs.get("alert_code") or "SOS").strip().upper()
        return attrs


class BraceletCellSosSerializer(serializers.Serializer):
    device_id = serializers.CharField(max_length=100)
    mcc = serializers.IntegerField(min_value=100, max_value=999)
    mnc = serializers.IntegerField(min_value=0, max_value=999)
    lac = serializers.IntegerField(min_value=0)
    cellid = serializers.IntegerField(min_value=0)
    radio = serializers.CharField(max_length=20, required=False, allow_blank=True, default="")
    timestamp = serializers.CharField(required=False, allow_blank=True, default="")
    phone = serializers.CharField(max_length=32)
    alert_code = serializers.CharField(max_length=50, required=False, default="SOS")

    def validate(self, attrs):
        attrs["alert_code"] = (attrs.get("alert_code") or "SOS").strip().upper()
        attrs["radio"] = (attrs.get("radio") or "").strip().upper()
        return attrs
