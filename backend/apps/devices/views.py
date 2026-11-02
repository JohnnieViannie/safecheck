from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from apps.audit.services import AuditService
from apps.organizations.permissions import user_org_ids
from apps.people.models import Person

from .models import Bracelet, BraceletStatus
from .serializers import (
    AssignBraceletSerializer,
    BraceletAssignmentSerializer,
    BraceletSerializer,
)
from .services import BraceletAssignmentService


class BraceletViewSet(viewsets.ModelViewSet):
    serializer_class = BraceletSerializer
    search_fields = ["device_id", "serial_number"]
    filterset_fields = ["status", "organization"]
    ordering_fields = ["created_at", "device_id", "status"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return Bracelet.objects.select_related(
                "organization", "current_person", "owner_user"
            )
        org_ids = user_org_ids(user)
        visible = Q(organization_id__in=org_ids) | Q(owner_user=user)
        if user.is_registrar:
            visible |= Q(current_person__linked_user__registered_by=user)
        return Bracelet.objects.filter(visible).select_related(
            "organization", "current_person", "owner_user"
        )

    def perform_create(self, serializer):
        # Registration is staff-only. Devices normally arrive through Add user.
        user = self.request.user
        if not (user.is_platform_admin or user.is_registrar):
            raise PermissionDenied("Bracelets are registered by SafeBangle staff.")
        org_id = self.request.data.get("organization")
        status_val = self.request.data.get("status", BraceletStatus.INVENTORY)
        if org_id:
            bracelet = serializer.save(organization_id=org_id, status=status_val)
        else:
            bracelet = serializer.save(status=status_val)
        AuditService.log(
            actor=user,
            action="bracelet.registered",
            object_type="Bracelet",
            object_id=str(bracelet.id),
            organization=bracelet.organization,
            metadata={"device_id": bracelet.device_id},
            request=self.request,
        )

    def perform_update(self, serializer):
        self._ensure_manage(serializer.instance)
        serializer.save()

    def perform_destroy(self, instance):
        self._ensure_manage(instance)
        instance.delete()

    def _ensure_manage(self, bracelet):
        if not self.request.user.is_platform_admin:
            raise PermissionDenied("Bracelets are managed by SafeBangle staff.")

    @action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        bracelet = self.get_object()
        self._ensure_manage(bracelet)
        ser = AssignBraceletSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            person = Person.objects.get(id=ser.validated_data["person_id"])
        except Person.DoesNotExist:
            return Response({"error": "Person not found"}, status=404)
        # tenant check
        if bracelet.organization_id and person.organization_id != bracelet.organization_id:
            if not (
                person.owner_user_id
                and bracelet.owner_user_id
                and person.owner_user_id == bracelet.owner_user_id
            ):
                return Response(
                    {"error": "Person does not belong to this bracelet's organization."},
                    status=400,
                )
        assignment = BraceletAssignmentService.assign(
            bracelet,
            person,
            assigned_by=request.user,
            reason=ser.validated_data.get("reason", ""),
        )
        AuditService.log(
            actor=request.user,
            action="bracelet.assigned",
            object_type="Bracelet",
            object_id=str(bracelet.id),
            organization=bracelet.organization,
            metadata={"person_id": str(person.id)},
            request=request,
        )
        return Response(BraceletAssignmentSerializer(assignment).data)

    @action(detail=True, methods=["post"])
    def unassign(self, request, pk=None):
        bracelet = self.get_object()
        self._ensure_manage(bracelet)
        BraceletAssignmentService.unassign(
            bracelet, reason=request.data.get("reason", "")
        )
        AuditService.log(
            actor=request.user,
            action="bracelet.unassigned",
            object_type="Bracelet",
            object_id=str(bracelet.id),
            organization=bracelet.organization,
            request=request,
        )
        return Response(BraceletSerializer(bracelet).data)

    @action(detail=True, methods=["post"])
    def activate(self, request, pk=None):
        bracelet = self.get_object()
        self._ensure_manage(bracelet)
        BraceletAssignmentService.activate(bracelet)
        AuditService.log(
            actor=request.user,
            action="bracelet.activated",
            object_type="Bracelet",
            object_id=str(bracelet.id),
            organization=bracelet.organization,
            request=request,
        )
        return Response(BraceletSerializer(bracelet).data)

    @action(detail=True, methods=["post"])
    def deactivate(self, request, pk=None):
        bracelet = self.get_object()
        self._ensure_manage(bracelet)
        BraceletAssignmentService.deactivate(bracelet)
        AuditService.log(
            actor=request.user,
            action="bracelet.deactivated",
            object_type="Bracelet",
            object_id=str(bracelet.id),
            organization=bracelet.organization,
            request=request,
        )
        return Response(BraceletSerializer(bracelet).data)

    @action(detail=True, methods=["get"])
    def history(self, request, pk=None):
        bracelet = self.get_object()
        qs = bracelet.assignments.select_related("person", "assigned_by")
        return Response(BraceletAssignmentSerializer(qs, many=True).data)
