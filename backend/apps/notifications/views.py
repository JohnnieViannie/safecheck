from django.db.models import Q
from django.utils import timezone
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.organizations.permissions import user_org_ids

from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            "id",
            "organization",
            "channel",
            "recipient",
            "subject",
            "message",
            "status",
            "alert",
            "incident",
            "created_at",
            "sent_at",
            "read_at",
        ]


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer
    filterset_fields = ["channel", "status", "organization"]
    ordering_fields = ["created_at"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return Notification.objects.all()
        org_ids = user_org_ids(user)
        return Notification.objects.filter(Q(user=user) | Q(organization_id__in=org_ids))

    @action(detail=True, methods=["post"])
    def mark_read(self, request, pk=None):
        n = self.get_object()
        n.status = Notification.Status.READ
        n.read_at = timezone.now()
        n.save(update_fields=["status", "read_at"])
        return Response(NotificationSerializer(n).data)
