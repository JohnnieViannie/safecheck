from django.db.models import Q
from rest_framework import serializers, viewsets
from rest_framework.permissions import IsAuthenticated

from apps.organizations.permissions import IsPlatformAdmin, user_org_ids

from .models import AuditLog


class AuditLogSerializer(serializers.ModelSerializer):
    actor_email = serializers.EmailField(source="actor.email", read_only=True, default=None)

    class Meta:
        model = AuditLog
        fields = [
            "id",
            "actor",
            "actor_email",
            "action",
            "object_type",
            "object_id",
            "organization",
            "ip_address",
            "metadata",
            "created_at",
        ]


class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AuditLogSerializer
    permission_classes = [IsAuthenticated]
    search_fields = ["action", "object_type", "object_id", "actor__email"]
    filterset_fields = ["action", "organization", "object_type"]
    ordering_fields = ["created_at"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return AuditLog.objects.select_related("actor", "organization")
        org_ids = user_org_ids(user)
        return AuditLog.objects.filter(
            Q(organization_id__in=org_ids) | Q(actor=user)
        ).select_related("actor", "organization")
