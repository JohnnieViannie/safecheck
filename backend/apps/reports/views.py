from datetime import date, timedelta

from django.contrib.auth import get_user_model
from django.db.models import Avg, Count, DurationField, ExpressionWrapper, F, Q
from django.db.models.functions import TruncDate, TruncMonth
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.alerts.models import Alert
from apps.devices.models import Bracelet, BraceletStatus
from apps.incidents.models import Incident, IncidentStatus
from apps.organizations.models import Organization
from apps.organizations.permissions import user_org_ids
from apps.people.models import Person
from apps.safety.models import SmsMessage

User = get_user_model()

OPEN_STATUSES = [
    IncidentStatus.NEW,
    IncidentStatus.ACKNOWLEDGED,
    IncidentStatus.ASSIGNED,
    IncidentStatus.RESPONDING,
]


def _scope(request):
    user = request.user
    org_id = request.query_params.get("organization")
    if user.is_platform_admin:
        return {"platform": True, "org_id": org_id, "org_ids": None}
    org_ids = user_org_ids(user)
    if org_id and str(org_id) not in [str(i) for i in org_ids]:
        return {"platform": False, "org_id": None, "org_ids": [], "forbidden": True}
    return {
        "platform": False,
        "org_id": org_id,
        "org_ids": org_ids,
        "user_id": user.id,
    }


def _filter_qs(qs, scope, org_field="organization_id", owner_field="owner_user_id"):
    if scope.get("forbidden"):
        return qs.none()
    if scope.get("platform"):
        if scope.get("org_id"):
            return qs.filter(**{org_field: scope["org_id"]})
        return qs
    q = Q(**{f"{org_field}__in": scope["org_ids"]})
    if owner_field:
        q |= Q(**{owner_field: scope["user_id"]})
    if scope.get("org_id"):
        return qs.filter(**{org_field: scope["org_id"]})
    return qs.filter(q)


def _month_starts(months=12):
    today = timezone.now().date().replace(day=1)
    y, m = today.year, today.month
    out = []
    for _ in range(months):
        out.append(date(y, m, 1))
        m -= 1
        if m == 0:
            m = 12
            y -= 1
    return list(reversed(out))


def _monthly_series(qs, field, months=12):
    from datetime import datetime, time

    buckets = _month_starts(months)
    start = timezone.make_aware(datetime.combine(buckets[0], time.min))
    rows = (
        qs.filter(**{f"{field}__gte": start})
        .annotate(month=TruncMonth(field))
        .values("month")
        .annotate(count=Count("id"))
    )
    by_month = {}
    for row in rows:
        month_val = row["month"]
        if month_val is None:
            continue
        if hasattr(month_val, "date"):
            key = month_val.date().replace(day=1)
        else:
            key = month_val.replace(day=1) if hasattr(month_val, "replace") else month_val
        by_month[key] = row["count"]
    return [
        {
            "month": b.strftime("%Y-%m"),
            "label": b.strftime("%b %Y"),
            "count": by_month.get(b, 0),
        }
        for b in buckets
    ]


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def dashboard_summary(request):
    scope = _scope(request)
    if scope.get("forbidden"):
        return Response({"error": "Forbidden"}, status=403)

    bracelets = _filter_qs(Bracelet.objects.all(), scope)
    alerts = _filter_qs(Alert.objects.all(), scope)
    incidents = _filter_qs(Incident.objects.all(), scope)
    people = _filter_qs(Person.objects.all(), scope)

    since = timezone.now() - timedelta(days=30)
    recent_alerts = alerts.filter(received_at__gte=since)

    resolved = incidents.filter(status=IncidentStatus.RESOLVED)
    response_times = (
        incidents.filter(acknowledged_at__isnull=False)
        .annotate(
            ack_delay=ExpressionWrapper(
                F("acknowledged_at") - F("created_at"), output_field=DurationField()
            )
        )
        .aggregate(avg=Avg("ack_delay"))
    )
    avg_ack = response_times["avg"]
    avg_ack_seconds = avg_ack.total_seconds() if avg_ack else None

    payload = {
        "bracelets": {
            "total": bracelets.count(),
            "active": bracelets.filter(
                status__in=[
                    BraceletStatus.ACTIVATED,
                    BraceletStatus.ASSIGNED,
                    BraceletStatus.IN_USE,
                ]
            ).count(),
            "unassigned": bracelets.filter(
                status__in=[BraceletStatus.UNASSIGNED, BraceletStatus.INVENTORY, BraceletStatus.ACTIVATED],
                current_person__isnull=True,
            ).count(),
            "in_use": bracelets.filter(status=BraceletStatus.IN_USE).count(),
        },
        "people": {"total": people.filter(is_active=True).count()},
        "alerts": {
            "total": alerts.count(),
            "last_30_days": recent_alerts.count(),
            "active": alerts.filter(processing_status=Alert.ProcessingStatus.PROCESSED).count(),
        },
        "incidents": {
            "open": incidents.filter(status__in=OPEN_STATUSES).count(),
            "resolved": resolved.count(),
            "total": incidents.count(),
            "avg_ack_seconds": avg_ack_seconds,
        },
    }

    if request.user.is_platform_admin and not scope.get("org_id"):
        payload["platform"] = {
            "organizations": Organization.objects.filter(is_active=True).count(),
            "users": User.objects.filter(is_active=True).count(),
            "individuals": User.objects.filter(
                account_type="individual", is_platform_admin=False
            ).count(),
        }
        payload["user_growth"] = _monthly_series(User.objects.all(), "created_at")
        payload["alerts_over_time"] = _monthly_series(Alert.objects.all(), "received_at")
        payload["sms_over_time"] = _monthly_series(SmsMessage.objects.all(), "created_at")
    else:
        payload["user_growth"] = []
        payload["alerts_over_time"] = _monthly_series(alerts, "received_at")
        payload["sms_over_time"] = []

    return Response(payload)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def reports_summary(request):
    scope = _scope(request)
    if scope.get("forbidden"):
        return Response({"error": "Forbidden"}, status=403)

    date_from = request.query_params.get("from")
    date_to = request.query_params.get("to")
    person_id = request.query_params.get("person")
    bracelet_id = request.query_params.get("bracelet")
    alert_code = request.query_params.get("alert_type")
    status_filter = request.query_params.get("status")

    alerts = _filter_qs(Alert.objects.all(), scope)
    incidents = _filter_qs(Incident.objects.all(), scope)
    bracelets = _filter_qs(Bracelet.objects.all(), scope)

    if date_from:
        alerts = alerts.filter(received_at__date__gte=date_from)
        incidents = incidents.filter(created_at__date__gte=date_from)
    if date_to:
        alerts = alerts.filter(received_at__date__lte=date_to)
        incidents = incidents.filter(created_at__date__lte=date_to)
    if person_id:
        alerts = alerts.filter(person_id=person_id)
        incidents = incidents.filter(person_id=person_id)
    if bracelet_id:
        alerts = alerts.filter(bracelet_id=bracelet_id)
    if alert_code:
        alerts = alerts.filter(alert_code__iexact=alert_code)
    if status_filter:
        incidents = incidents.filter(status=status_filter)

    alerts_by_date = list(
        alerts.annotate(day=TruncDate("received_at"))
        .values("day")
        .annotate(count=Count("id"))
        .order_by("day")
    )
    incidents_by_date = list(
        incidents.annotate(day=TruncDate("created_at"))
        .values("day")
        .annotate(count=Count("id"))
        .order_by("day")
    )
    alerts_by_person = list(
        alerts.exclude(person__isnull=True)
        .values("person_id", "person__first_name", "person__last_name")
        .annotate(count=Count("id"))
        .order_by("-count")[:20]
    )
    alerts_by_bracelet = list(
        alerts.exclude(bracelet__isnull=True)
        .values("bracelet_id", "bracelet__device_id")
        .annotate(count=Count("id"))
        .order_by("-count")[:20]
    )
    by_code = list(
        alerts.values("alert_code").annotate(count=Count("id")).order_by("-count")
    )

    resolved = incidents.filter(resolved_at__isnull=False)
    total_inc = incidents.count()
    resolution_rate = (resolved.count() / total_inc * 100) if total_inc else 0

    ack = incidents.filter(acknowledged_at__isnull=False).annotate(
        delay=ExpressionWrapper(
            F("acknowledged_at") - F("created_at"), output_field=DurationField()
        )
    ).aggregate(avg=Avg("delay"))
    avg_ack = ack["avg"].total_seconds() if ack["avg"] else None

    device_util = {
        "total": bracelets.count(),
        "in_use": bracelets.filter(status=BraceletStatus.IN_USE).count(),
        "inactive": bracelets.filter(
            status__in=[BraceletStatus.DEACTIVATED, BraceletStatus.INVENTORY]
        ).count(),
    }

    return Response(
        {
            "totals": {
                "alerts": alerts.count(),
                "incidents": total_inc,
                "resolution_rate": round(resolution_rate, 1),
                "avg_ack_seconds": avg_ack,
            },
            "alerts_by_date": [
                {"date": x["day"].isoformat() if x["day"] else None, "count": x["count"]}
                for x in alerts_by_date
            ],
            "incidents_by_date": [
                {"date": x["day"].isoformat() if x["day"] else None, "count": x["count"]}
                for x in incidents_by_date
            ],
            "alerts_by_person": [
                {
                    "person_id": str(x["person_id"]),
                    "name": f"{x['person__first_name']} {x['person__last_name']}".strip(),
                    "count": x["count"],
                }
                for x in alerts_by_person
            ],
            "alerts_by_bracelet": [
                {
                    "bracelet_id": str(x["bracelet_id"]),
                    "device_id": x["bracelet__device_id"],
                    "count": x["count"],
                }
                for x in alerts_by_bracelet
            ],
            "alerts_by_code": by_code,
            "device_utilization": device_util,
        }
    )
