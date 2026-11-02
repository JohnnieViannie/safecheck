from django.utils import timezone

from apps.alerts.geo import reverse_geocode_place
from apps.checkins.models import CallAttempt, Checkin
from apps.notifications.sms_text import checkin_sms, local_time
from apps.people.models import TrustedContact
from apps.safety.models import EscalationAlert, LocationSnapshot, SafetyProfile
from apps.safety.services.sms_provider import SmsProvider
from apps.vault.services import append_vault_links_to_message

SAFE_PHRASES = ("i am fine", "i'm fine", "im fine")
COUNTRY_DIAL_CODES = {
    "UG": "256",
    "MW": "265",
    "KE": "254",
    "TZ": "255",
    "RW": "250",
    "NG": "234",
    "ZA": "27",
    "GH": "233",
}


def is_safe_phrase(text: str) -> bool:
    normalized = (text or "").strip().lower()
    return any(phrase in normalized for phrase in SAFE_PHRASES)


def _normalize_phone_to_e164(phone_number: str, country_iso2: str = "UG") -> str:
    raw = (phone_number or "").strip()
    if not raw:
        return ""
    compact = "".join(ch for ch in raw if ch.isdigit() or ch == "+")
    if compact.startswith("+"):
        digits = "".join(ch for ch in compact if ch.isdigit())
        return f"+{digits}" if digits else ""
    if compact.startswith("00"):
        digits = compact[2:]
        return f"+{digits}" if digits else ""
    digits = "".join(ch for ch in compact if ch.isdigit())
    if not digits:
        return ""
    if digits.startswith("0"):
        digits = digits[1:]
    dial = COUNTRY_DIAL_CODES.get((country_iso2 or "UG").upper(), "256")
    return f"+{dial}{digits}"


def build_emergency_sms(profile: SafetyProfile) -> str:
    """Mobile missed-check-in / escalation SMS to next of kin."""
    user = profile.user
    latest_location = (
        LocationSnapshot.objects.filter(user=user).order_by("-captured_at").first()
    )
    name = (user.full_name or "").strip() or "Your contact"
    if not latest_location:
        return checkin_sms(name, "", "", None, None)

    area = (latest_location.address or "").strip()
    if not area:
        place = reverse_geocode_place(latest_location.latitude, latest_location.longitude)
        area = place["area"]
        if place["label"]:
            latest_location.address = place["label"][:256]
            latest_location.save(update_fields=["address"])
    return checkin_sms(
        name,
        area,
        local_time(latest_location.captured_at, user.phone),
        latest_location.latitude,
        latest_location.longitude,
    )


def mark_user_safe(profile: SafetyProfile, text: str = "") -> None:
    now = timezone.now()
    user = profile.user
    profile.last_call_status = "safe_confirmed"
    profile.escalation_status = "none"
    profile.last_check_in_at = now
    profile.last_push_sent_at = None
    profile.pending_call_kit_id = None
    profile.save(
        update_fields=[
            "last_call_status",
            "escalation_status",
            "last_check_in_at",
            "last_push_sent_at",
            "pending_call_kit_id",
        ]
    )
    Checkin.objects.create(user=user, status="ok")
    latest_attempt = CallAttempt.objects.filter(user=user).order_by("-created_at").first()
    if latest_attempt:
        latest_attempt.status = "safe_confirmed"
        latest_attempt.recognized_text = text
        latest_attempt.completed_at = now
        latest_attempt.save(update_fields=["status", "recognized_text", "completed_at"])


def _emergency_recipients(profile: SafetyProfile) -> list[tuple[str, str, str]]:
    recipients: list[tuple[str, str, str]] = []
    contacts = TrustedContact.objects.filter(
        owner_user=profile.user, is_active=True, notify_sms=True
    ).order_by("priority")
    for c in contacts:
        phone = _normalize_phone_to_e164(
            c.phone or "",
            profile.emergency_contact_country_code or "UG",
        )
        if phone:
            recipients.append((phone, c.name or "Contact", c.relationship or ""))
    if recipients:
        return recipients

    primary_phone = _normalize_phone_to_e164(
        profile.emergency_contact_phone or "",
        profile.emergency_contact_country_code or "UG",
    )
    if primary_phone:
        recipients.append(
            (
                primary_phone,
                profile.emergency_contact_name or "Next of kin",
                profile.emergency_contact_relationship or "",
            )
        )
    return recipients


def _document_vault_enabled(profile: SafetyProfile) -> bool:
    import json

    raw = (profile.trigger_actions_json or "").strip()
    if not raw:
        return False
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return False
    if not isinstance(parsed, list):
        return False
    for item in parsed:
        if not isinstance(item, dict):
            continue
        if str(item.get("type") or "") == "document_vault" and item.get("enabled", True):
            return True
    return False


def escalate_to_next_of_kin(profile: SafetyProfile) -> None:
    """Escalate missed check-in / journey to next of kin (TrustedContact)."""
    # Accept either SafetyProfile or User with safety_profile
    if not isinstance(profile, SafetyProfile):
        profile = profile.safety_profile

    message = build_emergency_sms(profile)
    if _document_vault_enabled(profile):
        message = append_vault_links_to_message(profile.user, message)
    recipients = _emergency_recipients(profile)
    if not recipients:
        profile.last_call_status = "failed"
        profile.escalation_status = "failed_no_contact"
        profile.save(update_fields=["last_call_status", "escalation_status"])
        return

    sms_provider = SmsProvider()
    sent_any = False
    for recipient, _name, _relationship in recipients:
        sms_result = sms_provider.send_sms(
            recipient, message, purpose="escalation", user=profile.user
        )
        status = "sent" if sms_result.get("success") else "failed"
        if status == "sent":
            sent_any = True
        EscalationAlert.objects.create(
            user=profile.user,
            channel="sms",
            recipient=recipient,
            message=message,
            provider_message_id=sms_result.get("provider_message_id"),
            status=status,
        )

    profile.last_call_status = "escalated"
    profile.escalation_status = "sent" if sent_any else "failed"
    profile.last_escalated_at = timezone.now()
    profile.save(
        update_fields=["last_call_status", "escalation_status", "last_escalated_at"]
    )
