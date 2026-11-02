from apps.audit.models import AuditLog


class AuditService:
    @staticmethod
    def log(
        *,
        actor=None,
        action: str,
        object_type: str = "",
        object_id: str = "",
        organization=None,
        metadata=None,
        request=None,
    ):
        ip = None
        if request is not None:
            xff = request.META.get("HTTP_X_FORWARDED_FOR")
            if xff:
                ip = xff.split(",")[0].strip()
            else:
                ip = request.META.get("REMOTE_ADDR")
        user = None
        if actor is not None and getattr(actor, "is_authenticated", True):
            user = actor
        return AuditLog.objects.create(
            actor=user,
            action=action,
            object_type=object_type,
            object_id=str(object_id) if object_id else "",
            organization=organization,
            ip_address=ip,
            metadata=metadata or {},
        )
