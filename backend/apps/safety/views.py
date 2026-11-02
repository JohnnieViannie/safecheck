from django.db.models import Count, Q
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
import re

from apps.organizations.permissions import IsPlatformAdmin

from .models import SmsMessage

# Where the send was triggered (app vs alert pipeline vs test/API vs inbound webhook).
PURPOSE_ORIGIN = {
    "otp": "app",
    "contact_opt_in": "app",
    "escalation": "alerts",
    "test": "api",
    "general": "api",
    "inbound": "webhook",
}


def _parse_cost(value: str) -> float:
    if not value:
        return 0.0
    text = str(value).strip().replace(",", "")
    nums = re.findall(r"\d+(?:\.\d+)?", text)
    if not nums:
        return 0.0
    try:
        return float(nums[-1])
    except ValueError:
        return 0.0


def _currency_hint(value: str) -> str:
    if not value:
        return ""
    m = re.search(r"[A-Za-z]{3}", str(value))
    return m.group(0).upper() if m else ""


class SmsMessageSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(source="user.email", read_only=True, default=None)
    origin = serializers.SerializerMethodField()
    source = serializers.SerializerMethodField()

    class Meta:
        model = SmsMessage
        fields = [
            "id",
            "direction",
            "provider",
            "purpose",
            "origin",
            "source",
            "phone_number",
            "message",
            "status",
            "provider_message_id",
            "cost",
            "error",
            "user",
            "user_email",
            "created_at",
        ]

    def get_origin(self, obj):
        return PURPOSE_ORIGIN.get((obj.purpose or "").strip().lower(), "other")

    def get_source(self, obj):
        # Product / channel that triggered the SMS (shown as "Source" in admin table).
        origin = self.get_origin(obj)
        return {
            "app": "App",
            "alerts": "Blaces",
            "api": "Blaces",
            "webhook": "Webhook",
            "other": "Other",
        }.get(origin, "Other")


class SmsMessageViewSet(viewsets.ReadOnlyModelViewSet):
    """Platform SMS ledger (KaCyber / Africa's Talking) for Blaces admin UI."""

    serializer_class = SmsMessageSerializer
    permission_classes = [IsAuthenticated, IsPlatformAdmin]
    search_fields = ["phone_number", "message", "provider_message_id", "error", "user__email"]
    filterset_fields = ["direction", "status", "provider", "purpose"]
    ordering_fields = ["created_at"]
    ordering = ["-created_at"]

    def get_queryset(self):
        return SmsMessage.objects.select_related("user").all()

    @action(detail=False, methods=["get"])
    def stats(self, request):
        qs = self.filter_queryset(self.get_queryset())
        data = qs.aggregate(
            total=Count("id"),
            outbound=Count("id", filter=Q(direction="outbound")),
            inbound=Count("id", filter=Q(direction="inbound")),
            sent=Count("id", filter=Q(status="sent")),
            failed=Count("id", filter=Q(status="failed")),
            received=Count("id", filter=Q(status="received")),
        )

        cost_rows = list(qs.values_list("cost", "purpose", "provider"))
        total_spent = 0.0
        currency = ""
        by_purpose: dict[str, dict] = {}
        by_provider: dict[str, dict] = {}
        by_origin: dict[str, dict] = {}

        for cost, purpose, provider in cost_rows:
            amount = _parse_cost(cost or "")
            total_spent += amount
            if not currency:
                currency = _currency_hint(cost or "")

            purpose_key = (purpose or "general").strip().lower() or "general"
            provider_key = (provider or "unknown").strip().lower() or "unknown"
            origin_key = PURPOSE_ORIGIN.get(purpose_key, "other")

            for bucket, key in (
                (by_purpose, purpose_key),
                (by_provider, provider_key),
                (by_origin, origin_key),
            ):
                entry = bucket.setdefault(key, {"key": key, "count": 0, "spent": 0.0})
                entry["count"] += 1
                entry["spent"] += amount

        def _sorted(bucket: dict) -> list:
            rows = list(bucket.values())
            for row in rows:
                row["spent"] = round(row["spent"], 4)
            rows.sort(key=lambda r: (-r["count"], r["key"]))
            return rows

        data["total_spent"] = round(total_spent, 4)
        data["currency"] = currency or "UGX"
        data["by_purpose"] = _sorted(by_purpose)
        data["by_provider"] = _sorted(by_provider)
        data["by_origin"] = _sorted(by_origin)
        return Response(data)
