import logging

from django.conf import settings
from django.db.models import Q
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle

from apps.alerts.geo import GeoError, opencellid_lookup
from apps.alerts.models import Alert, AlertCode
from apps.alerts.serializers import (
    AlertCodeSerializer,
    AlertSerializer,
    BraceletCellSosSerializer,
    BraceletGpsSosSerializer,
)
from apps.alerts.services import AlertEngine, DeviceAlertError
from apps.organizations.permissions import user_org_ids


logger = logging.getLogger(__name__)


class WebhookThrottle(AnonRateThrottle):
    scope = "webhook"


class BraceletSosThrottle(AnonRateThrottle):
    scope = "bracelet_sos"


def _bracelet_secret_ok(request) -> bool:
    secret = settings.BRACELET_API_SECRET
    provided = request.headers.get("X-Bracelet-Secret") or request.META.get(
        "HTTP_X_BRACELET_SECRET"
    )
    if not secret:
        return bool(settings.DEBUG)
    return provided == secret


def _idempotency_key(request) -> str:
    return (
        request.headers.get("Idempotency-Key")
        or request.META.get("HTTP_IDEMPOTENCY_KEY")
        or ""
    ).strip()


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([WebhookThrottle])
def africastalking_sms_webhook(request):
    secret = settings.WEBHOOK_SHARED_SECRET
    if secret:
        provided = request.headers.get("X-Webhook-Secret") or request.META.get(
            "HTTP_X_WEBHOOK_SECRET"
        )
        if provided != secret:
            return Response({"error": "Unauthorized webhook"}, status=401)

    data = request.data
    text = data.get("text") or data.get("message") or ""
    sender = data.get("from") or data.get("sender") or ""
    recipient = data.get("to") or data.get("recipient") or ""
    provider_id = data.get("id") or data.get("messageId") or ""
    date = data.get("date") or data.get("timestamp") or ""

    if not text:
        return Response({"error": "Missing text field"}, status=400)

    result = AlertEngine.process_inbound(
        text=text,
        sender=str(sender),
        recipient=str(recipient),
        provider_message_id=str(provider_id),
        date=str(date),
        raw_payload=dict(data),
    )
    http_status = status.HTTP_200_OK
    if result.get("error") and not result.get("duplicate"):
        http_status = status.HTTP_202_ACCEPTED
    return Response(result, status=http_status)


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([BraceletSosThrottle])
def bracelet_sos_gps(request):
    if not _bracelet_secret_ok(request):
        return Response({"error": "Unauthorized", "code": "unauthorized"}, status=403)

    serializer = BraceletGpsSosSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    try:
        result = AlertEngine.process_device_sos(
            device_id=data["device_id"],
            alert_code=data["alert_code"],
            latitude=data["latitude"],
            longitude=data["longitude"],
            timestamp=data.get("timestamp") or "",
            phone=data["phone"],
            raw_payload=dict(request.data),
            location_source=Alert.LocationSource.GPS,
            idempotency_key=_idempotency_key(request),
        )
    except DeviceAlertError as exc:
        return Response(
            {"error": str(exc), "code": exc.code},
            status=exc.http_status,
        )

    status_code = status.HTTP_200_OK if result.get("duplicate") else status.HTTP_201_CREATED
    return Response(result, status=status_code)


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([BraceletSosThrottle])
def bracelet_sos_cell(request):
    if not _bracelet_secret_ok(request):
        return Response({"error": "Unauthorized", "code": "unauthorized"}, status=403)

    serializer = BraceletCellSosSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    try:
        cell = opencellid_lookup(
            mcc=data["mcc"],
            mnc=data["mnc"],
            lac=data["lac"],
            cellid=data["cellid"],
            radio=data.get("radio") or None,
        )
    except GeoError as exc:
        # An emergency still goes out without a location. Next of kin hear "location unavailable".
        logger.error("Cell SOS without location for %s: %s", data["device_id"], exc)
        cell = {"latitude": None, "longitude": None, "accuracy_m": None, "error": exc.code}

    payload = dict(request.data)
    payload["opencellid"] = {
        "latitude": str(cell["latitude"]) if cell["latitude"] is not None else None,
        "longitude": str(cell["longitude"]) if cell["longitude"] is not None else None,
        "accuracy_m": cell.get("accuracy_m"),
        "mock": cell.get("mock", False),
        "error": cell.get("error", ""),
    }

    try:
        result = AlertEngine.process_device_sos(
            device_id=data["device_id"],
            alert_code=data["alert_code"],
            latitude=cell["latitude"],
            longitude=cell["longitude"],
            timestamp=data.get("timestamp") or "",
            phone=data["phone"],
            raw_payload=payload,
            location_source=Alert.LocationSource.OPENCELLID,
            location_accuracy_m=cell.get("accuracy_m"),
            idempotency_key=_idempotency_key(request),
        )
    except DeviceAlertError as exc:
        return Response(
            {"error": str(exc), "code": exc.code},
            status=exc.http_status,
        )

    status_code = status.HTTP_200_OK if result.get("duplicate") else status.HTTP_201_CREATED
    return Response(result, status=status_code)


class AlertViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = AlertSerializer
    search_fields = ["alert_code", "bracelet__device_id", "person__first_name", "person__last_name"]
    filterset_fields = ["organization", "alert_code", "processing_status", "bracelet", "person"]
    ordering_fields = ["received_at", "created_at"]

    def get_queryset(self):
        user = self.request.user
        qs = Alert.objects.select_related(
            "bracelet", "person", "organization", "incident"
        )
        if user.is_platform_admin:
            return qs
        org_ids = user_org_ids(user)
        return qs.filter(Q(organization_id__in=org_ids) | Q(owner_user=user))


class AlertCodeViewSet(viewsets.ModelViewSet):
    serializer_class = AlertCodeSerializer
    queryset = AlertCode.objects.all()
    search_fields = ["code", "label"]

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [permissions.IsAuthenticated()]
        return [permissions.IsAuthenticated()]

    def perform_create(self, serializer):
        if not self.request.user.is_platform_admin:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Platform admin only.")
        serializer.save()

    def perform_update(self, serializer):
        if not self.request.user.is_platform_admin:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Platform admin only.")
        serializer.save()

    def perform_destroy(self, instance):
        if not self.request.user.is_platform_admin:
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Platform admin only.")
        instance.delete()
