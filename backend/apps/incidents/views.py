from django.contrib.auth import get_user_model
from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from apps.organizations.permissions import RESPONDER_ROLES, get_membership, user_org_ids

from .models import Incident
from .serializers import IncidentSerializer
from .services import IncidentService

User = get_user_model()


class IncidentViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = IncidentSerializer
    search_fields = [
        "person__first_name",
        "person__last_name",
        "alert__alert_code",
        "alert__bracelet__device_id",
        "status",
    ]
    filterset_fields = ["organization", "status", "assigned_responder", "person"]
    ordering_fields = ["created_at", "status", "updated_at"]

    def get_queryset(self):
        user = self.request.user
        qs = Incident.objects.select_related(
            "alert",
            "alert__bracelet",
            "person",
            "organization",
            "assigned_responder",
        ).prefetch_related("events")
        if user.is_platform_admin:
            return qs
        org_ids = user_org_ids(user)
        return qs.filter(Q(organization_id__in=org_ids) | Q(owner_user=user))

    def _ensure_responder(self, incident):
        user = self.request.user
        if user.is_platform_admin:
            return
        if incident.owner_user_id == user.id:
            return
        if incident.organization_id:
            m = get_membership(user, incident.organization_id)
            if m and m.role in RESPONDER_ROLES:
                return
        raise PermissionDenied()

    @action(detail=True, methods=["post"])
    def acknowledge(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        IncidentService.acknowledge(incident, request.user, note=request.data.get("note", ""))
        return Response(IncidentSerializer(incident).data)

    @action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        responder_id = request.data.get("responder_id") or str(request.user.id)
        try:
            responder = User.objects.get(id=responder_id)
        except User.DoesNotExist:
            return Response({"error": "Responder not found"}, status=404)
        IncidentService.assign(
            incident, request.user, responder, note=request.data.get("note", "")
        )
        return Response(IncidentSerializer(incident).data)

    @action(detail=True, methods=["post"])
    def respond(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        IncidentService.start_responding(
            incident, request.user, note=request.data.get("note", "")
        )
        return Response(IncidentSerializer(incident).data)

    @action(detail=True, methods=["post"])
    def resolve(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        IncidentService.resolve(
            incident, request.user, resolution=request.data.get("resolution", "")
        )
        return Response(IncidentSerializer(incident).data)

    @action(detail=True, methods=["post"])
    def close(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        IncidentService.close(incident, request.user, note=request.data.get("note", ""))
        return Response(IncidentSerializer(incident).data)

    @action(detail=True, methods=["post"])
    def add_note(self, request, pk=None):
        incident = self.get_object()
        self._ensure_responder(incident)
        note = request.data.get("note", "")
        if not note:
            return Response({"error": "note required"}, status=400)
        IncidentService.add_note(incident, request.user, note)
        return Response(IncidentSerializer(incident).data)
