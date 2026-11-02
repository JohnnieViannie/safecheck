from django.utils import timezone

from apps.audit.services import AuditService
from apps.incidents.models import Incident, IncidentEvent, IncidentStatus


class IncidentService:
    @staticmethod
    def create_from_alert(alert) -> Incident:
        incident = Incident.objects.create(
            alert=alert,
            organization=alert.organization,
            person=alert.person,
            owner_user=alert.owner_user,
            status=IncidentStatus.NEW,
        )
        IncidentEvent.objects.create(
            incident=incident,
            action="created",
            to_status=IncidentStatus.NEW,
            note="Incident created from alert.",
            metadata={"alert_id": str(alert.id)},
        )
        AuditService.log(
            actor=None,
            action="incident.created",
            object_type="Incident",
            object_id=str(incident.id),
            organization=incident.organization,
            metadata={"alert_id": str(alert.id)},
        )
        return incident

    @staticmethod
    def _transition(incident, actor, action, to_status, note="", **meta):
        from_status = incident.status
        incident.status = to_status
        now = timezone.now()
        if to_status == IncidentStatus.ACKNOWLEDGED and not incident.acknowledged_at:
            incident.acknowledged_at = now
        if to_status == IncidentStatus.RESPONDING and not incident.response_started_at:
            incident.response_started_at = now
        if to_status == IncidentStatus.RESOLVED and not incident.resolved_at:
            incident.resolved_at = now
            if note:
                incident.resolution = note
        if to_status == IncidentStatus.CLOSED and not incident.closed_at:
            incident.closed_at = now
        incident.save()
        IncidentEvent.objects.create(
            incident=incident,
            actor=actor,
            action=action,
            from_status=from_status,
            to_status=to_status,
            note=note,
            metadata=meta,
        )
        AuditService.log(
            actor=actor,
            action=f"incident.{action}",
            object_type="Incident",
            object_id=str(incident.id),
            organization=incident.organization,
            metadata={"from": from_status, "to": to_status},
        )
        return incident

    @classmethod
    def acknowledge(cls, incident, actor, note=""):
        return cls._transition(
            incident, actor, "acknowledged", IncidentStatus.ACKNOWLEDGED, note=note
        )

    @classmethod
    def assign(cls, incident, actor, responder, note=""):
        incident.assigned_responder = responder
        incident.save(update_fields=["assigned_responder", "updated_at"])
        return cls._transition(
            incident,
            actor,
            "assigned",
            IncidentStatus.ASSIGNED,
            note=note,
            responder_id=str(responder.id),
        )

    @classmethod
    def start_responding(cls, incident, actor, note=""):
        return cls._transition(
            incident, actor, "responding", IncidentStatus.RESPONDING, note=note
        )

    @classmethod
    def resolve(cls, incident, actor, resolution=""):
        return cls._transition(
            incident, actor, "resolved", IncidentStatus.RESOLVED, note=resolution
        )

    @classmethod
    def close(cls, incident, actor, note=""):
        return cls._transition(
            incident, actor, "closed", IncidentStatus.CLOSED, note=note
        )

    @classmethod
    def cancel(cls, incident, actor, note=""):
        return cls._transition(
            incident, actor, "cancelled", IncidentStatus.CANCELLED, note=note
        )

    @staticmethod
    def add_note(incident, actor, note):
        IncidentEvent.objects.create(
            incident=incident,
            actor=actor,
            action="note",
            from_status=incident.status,
            to_status=incident.status,
            note=note,
        )
        if note:
            incident.notes = (incident.notes + "\n" + note).strip() if incident.notes else note
            incident.save(update_fields=["notes", "updated_at"])
        return incident
