from rest_framework import serializers

from .models import Incident, IncidentEvent


class IncidentEventSerializer(serializers.ModelSerializer):
    actor_email = serializers.EmailField(source="actor.email", read_only=True, default=None)

    class Meta:
        model = IncidentEvent
        fields = [
            "id",
            "action",
            "from_status",
            "to_status",
            "note",
            "actor",
            "actor_email",
            "metadata",
            "created_at",
        ]


class IncidentSerializer(serializers.ModelSerializer):
    person_name = serializers.CharField(source="person.full_name", read_only=True, default=None)
    device_id = serializers.CharField(
        source="alert.bracelet.device_id", read_only=True, default=None
    )
    alert_code = serializers.CharField(source="alert.alert_code", read_only=True)
    latitude = serializers.DecimalField(
        source="alert.latitude", max_digits=9, decimal_places=6, read_only=True
    )
    longitude = serializers.DecimalField(
        source="alert.longitude", max_digits=9, decimal_places=6, read_only=True
    )
    location_label = serializers.CharField(source="alert.location_label", read_only=True)
    location_area = serializers.CharField(source="alert.location_area", read_only=True)
    location_source = serializers.CharField(source="alert.location_source", read_only=True)
    location_accuracy_m = serializers.IntegerField(source="alert.location_accuracy_m", read_only=True)
    assigned_responder_email = serializers.EmailField(
        source="assigned_responder.email", read_only=True, default=None
    )
    organization_name = serializers.CharField(
        source="organization.name", read_only=True, default=None
    )
    events = IncidentEventSerializer(many=True, read_only=True)

    class Meta:
        model = Incident
        fields = [
            "id",
            "alert",
            "alert_code",
            "organization",
            "organization_name",
            "person",
            "person_name",
            "device_id",
            "latitude",
            "longitude",
            "location_label",
            "location_area",
            "location_source",
            "location_accuracy_m",
            "owner_user",
            "status",
            "assigned_responder",
            "assigned_responder_email",
            "acknowledged_at",
            "response_started_at",
            "resolved_at",
            "closed_at",
            "resolution",
            "notes",
            "events",
            "created_at",
            "updated_at",
        ]
