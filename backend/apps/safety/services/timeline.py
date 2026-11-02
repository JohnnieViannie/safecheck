from apps.safety.models import UserTimelineEvent


def log_timeline_event(user, event_type, source="backend", status="info", payload=None):
    from apps.safety.models import SafetyProfile

    account = user.user if isinstance(user, SafetyProfile) else user
    UserTimelineEvent.objects.create(
        user=account,
        event_type=event_type,
        source=source,
        status=status,
        payload_json=payload or {},
    )
