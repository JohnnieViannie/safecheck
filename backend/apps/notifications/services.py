import logging

from django.conf import settings
from django.core.mail import send_mail
from django.db.models import Q
from django.utils import timezone

from apps.accounts.phone import is_placeholder_email
from apps.notifications.models import Notification
from apps.notifications.sms_text import format_radius, local_time, map_link, sos_sms
from apps.organizations.models import MembershipRole, OrganizationMembership
from apps.people.models import TrustedContact

logger = logging.getLogger(__name__)


class SmsProvider:
    """Outbound SMS for bracelet/org alerts — uses SMS_PROVIDER (kacyber | africastalking)."""

    @staticmethod
    def send(phone: str, message: str) -> dict:
        from apps.safety.services.sms_provider import SmsProvider as CoreSmsProvider

        result = CoreSmsProvider().send_sms(phone, message, purpose="escalation")
        ok = bool(result.get("success"))
        out = {
            "ok": ok,
            "provider_message_id": result.get("provider_message_id", ""),
            "error": result.get("error", ""),
            "raw": result,
        }
        if result.get("mocked"):
            out["mock"] = True
        if not ok:
            logger.warning("SMS failed for %s: %s", phone, result.get("error"))
        return out


class NotificationService:
    @classmethod
    def notify(
        cls,
        *,
        channel,
        recipient,
        message,
        subject="",
        user=None,
        organization=None,
        alert=None,
        incident=None,
    ):
        if user is not None and (getattr(user, "is_muted", False) or not getattr(user, "is_active", True)):
            return None
        n = Notification.objects.create(
            channel=channel,
            recipient=recipient,
            message=message,
            subject=subject,
            user=user,
            organization=organization,
            alert=alert,
            incident=incident,
        )
        try:
            if channel == Notification.Channel.EMAIL:
                send_mail(
                    subject=subject or "SafeBangle Alert",
                    message=message,
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[recipient],
                    fail_silently=False,
                )
                n.status = Notification.Status.SENT
                n.sent_at = timezone.now()
            elif channel == Notification.Channel.SMS:
                result = SmsProvider.send(recipient, message)
                if result.get("ok"):
                    n.status = Notification.Status.SENT
                    n.provider_message_id = result.get("provider_message_id", "")
                    n.sent_at = timezone.now()
                else:
                    n.status = Notification.Status.FAILED
                    n.error_message = result.get("error", "SMS failed")
            else:
                n.status = Notification.Status.SENT
                n.sent_at = timezone.now()
        except Exception as exc:
            n.status = Notification.Status.FAILED
            n.error_message = str(exc)
        n.save()
        return n


class AlertRoutingService:
    """Route alerts to org responders + trusted contacts. Authorities can be added later."""

    @classmethod
    def _wearer_phone(cls, alert) -> str:
        return (alert.person.phone if alert.person else "") or alert.raw_payload.get("phone", "")

    @classmethod
    def _build_message(cls, alert) -> str:
        """Fuller SOS message for email and in-app, which cost nothing extra."""
        person_name = (
            alert.person.full_name if alert.person else None
        ) or "Your contact"
        when = local_time(alert.received_at, cls._wearer_phone(alert))
        lines = [
            (
                f"Hello, you are receiving this message because {person_name} "
                "added you as their next of kin. They just triggered a "
                f"Save Our Souls (SOS) alert at {when}."
            ),
        ]
        if alert.latitude is not None and alert.longitude is not None:
            lines.append(
                f"Here is their last known location: {map_link(alert.latitude, alert.longitude)}"
            )
            radius = format_radius(alert.location_accuracy_m)
            if radius:
                lines.append(f"Located by cell tower, within about {radius}.")
        else:
            lines.append("Their last known location is unavailable.")
        place_name = (alert.location_label or "").strip()
        if place_name:
            lines.append(place_name)
        return "\n".join(lines)

    @classmethod
    def _build_sms(cls, alert) -> str:
        """Short SOS text: who, where, when and an exact map link in one SMS."""
        return sos_sms(
            alert.person.full_name if alert.person else "",
            alert.location_area,
            local_time(alert.received_at, cls._wearer_phone(alert)),
            alert.location_accuracy_m,
            alert.latitude,
            alert.longitude,
        )

    @classmethod
    def route_alert(cls, alert):
        body = cls._build_message(alert)
        sms_body = cls._build_sms(alert)
        incident = getattr(alert, "incident", None)
        recipients_seen: set[str] = set()

        if alert.organization_id:
            memberships = OrganizationMembership.objects.filter(
                organization_id=alert.organization_id,
                is_active=True,
                role__in=[
                    MembershipRole.OWNER,
                    MembershipRole.ADMIN,
                    MembershipRole.RESPONDER,
                    MembershipRole.STAFF,
                ],
            ).select_related("user")
            for m in memberships:
                user = m.user
                if getattr(user, "is_muted", False) or not user.is_active:
                    continue
                in_app_key = f"in_app:{user.id}"
                if in_app_key not in recipients_seen:
                    recipients_seen.add(in_app_key)
                    NotificationService.notify(
                        channel=Notification.Channel.IN_APP,
                        recipient=user.email or user.phone or str(user.id),
                        subject=f"Alert {alert.alert_code}",
                        message=body,
                        user=user,
                        organization=alert.organization,
                        alert=alert,
                        incident=incident,
                    )
                if (
                    user.email
                    and not is_placeholder_email(user.email)
                    and user.email not in recipients_seen
                ):
                    recipients_seen.add(user.email)
                    NotificationService.notify(
                        channel=Notification.Channel.EMAIL,
                        recipient=user.email,
                        subject=f"SafeBangle Alert: {alert.alert_code}",
                        message=body,
                        user=user,
                        organization=alert.organization,
                        alert=alert,
                        incident=incident,
                    )
                if user.phone:
                    key = f"sms:{user.phone}"
                    if key not in recipients_seen:
                        recipients_seen.add(key)
                        NotificationService.notify(
                            channel=Notification.Channel.SMS,
                            recipient=user.phone,
                            message=sms_body,
                            user=user,
                            organization=alert.organization,
                            alert=alert,
                            incident=incident,
                        )

        contact_filters = Q(pk__in=[])
        if alert.person_id:
            contact_filters |= Q(person_id=alert.person_id)
        if alert.organization_id:
            contact_filters |= Q(organization_id=alert.organization_id, person__isnull=True)
        if alert.owner_user_id:
            contact_filters |= Q(owner_user_id=alert.owner_user_id)

        contacts = TrustedContact.objects.filter(is_active=True).filter(contact_filters).distinct()
        for c in contacts:
            if c.notify_email and c.email and c.email not in recipients_seen:
                recipients_seen.add(c.email)
                NotificationService.notify(
                    channel=Notification.Channel.EMAIL,
                    recipient=c.email,
                    subject=f"SafeBangle Emergency: {alert.alert_code}",
                    message=body,
                    organization=alert.organization,
                    alert=alert,
                    incident=incident,
                )
            if c.notify_sms and c.phone:
                key = f"sms:{c.phone}"
                if key not in recipients_seen:
                    recipients_seen.add(key)
                    NotificationService.notify(
                        channel=Notification.Channel.SMS,
                        recipient=c.phone,
                        message=sms_body,
                        organization=alert.organization,
                        alert=alert,
                        incident=incident,
                    )

        if (
            alert.owner_user
            and alert.owner_user.is_active
            and not getattr(alert.owner_user, "is_muted", False)
        ):
            owner = alert.owner_user
            if f"in_app:{owner.id}" not in recipients_seen:
                NotificationService.notify(
                    channel=Notification.Channel.IN_APP,
                    recipient=owner.email or owner.phone or str(owner.id),
                    subject=f"Alert {alert.alert_code}",
                    message=body,
                    user=owner,
                    alert=alert,
                    incident=incident,
                )
