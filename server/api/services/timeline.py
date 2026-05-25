from api.models import UserProfile, UserTimelineEvent


def log_timeline_event(user, event_type, source='backend', status='info', payload=None):
    UserTimelineEvent.objects.create(
        user=user,
        event_type=event_type,
        source=source,
        status=status,
        payload_json=payload or {},
    )
