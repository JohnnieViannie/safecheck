from django.utils import timezone

from api.models import AlertEvent, CallAttempt, Checkin, LocationSnapshot, UserProfile
from api.services.sms_provider import SmsProvider


SAFE_PHRASES = ('i am fine', "i'm fine", 'im fine')
COUNTRY_DIAL_CODES = {
    'UG': '256',
    'MW': '265',
    'KE': '254',
    'TZ': '255',
    'RW': '250',
    'NG': '234',
    'ZA': '27',
    'GH': '233',
}


def is_safe_phrase(text: str) -> bool:
    normalized = (text or '').strip().lower()
    return any(phrase in normalized for phrase in SAFE_PHRASES)


def _normalize_phone_to_e164(phone_number: str, country_iso2: str = 'UG') -> str:
    raw = (phone_number or '').strip()
    if not raw:
        return ''

    compact = ''.join(ch for ch in raw if ch.isdigit() or ch == '+')
    if compact.startswith('+'):
        digits = ''.join(ch for ch in compact if ch.isdigit())
        return f'+{digits}' if digits else ''
    if compact.startswith('00'):
        digits = compact[2:]
        return f'+{digits}' if digits else ''

    digits = ''.join(ch for ch in compact if ch.isdigit())
    if not digits:
        return ''

    # Local format (e.g. 077xxxxxxx) -> +<country code><rest>
    if digits.startswith('0'):
        digits = digits[1:]
    dial = COUNTRY_DIAL_CODES.get((country_iso2 or 'UG').upper(), '256')
    return f'+{dial}{digits}'


def build_emergency_sms(user: UserProfile) -> str:
    latest_location = LocationSnapshot.objects.filter(user=user).order_by('-captured_at').first()
    maps_link = None
    if latest_location:
        maps_link = f"https://maps.google.com/?q={latest_location.latitude},{latest_location.longitude}"

    contact_name = user.emergency_contact_name or 'Next of kin'
    full_name = getattr(user, 'full_name', None) or user.uid or 'your loved one'
    last_status = (user.last_call_status or '').strip()

    if last_status == 'no_answer':
        status_sentence = f"they did not answer the call"
    elif last_status == 'declined':
        status_sentence = f"they rejected the call"
    elif last_status == 'no_safe_response':
        status_sentence = f"they did not confirm their safety"
    else:
        status_sentence = f"they did not confirm their safety"

    location_sentence = (
        f"Here is their last known location: {maps_link}"
        if maps_link
        else "Location unavailable."
    )

    return (
        f"Hello {contact_name}, "
        f"SafeCheck tried to check on {full_name} but {status_sentence}. "
        f"Please try to check on them. "
        f"{location_sentence}"
    )


def mark_user_safe(user: UserProfile, text: str = '') -> None:
    now = timezone.now()
    user.last_call_status = 'safe_confirmed'
    user.escalation_status = 'none'
    user.last_check_in_at = now
    user.last_push_sent_at = None
    user.pending_call_kit_id = None
    user.save(
        update_fields=[
            'last_call_status',
            'escalation_status',
            'last_check_in_at',
            'last_push_sent_at',
            'pending_call_kit_id',
        ]
    )
    Checkin.objects.create(user=user, status='ok')
    latest_attempt = CallAttempt.objects.filter(user=user).order_by('-created_at').first()
    if latest_attempt:
        latest_attempt.status = 'safe_confirmed'
        latest_attempt.recognized_text = text
        latest_attempt.completed_at = now
        latest_attempt.save(update_fields=['status', 'recognized_text', 'completed_at'])


def escalate_to_next_of_kin(user: UserProfile) -> None:
    message = build_emergency_sms(user)
    recipient = _normalize_phone_to_e164(
        user.emergency_contact_phone or '',
        user.emergency_contact_country_code or 'UG',
    )
    if not recipient:
        user.last_call_status = 'failed'
        user.escalation_status = 'failed_no_contact'
        user.save(update_fields=['last_call_status', 'escalation_status'])
        return

    sms_result = SmsProvider().send_sms(recipient, message)
    status = 'sent' if sms_result.get('success') else 'failed'
    AlertEvent.objects.create(
        user=user,
        channel='sms',
        recipient=recipient,
        message=message,
        provider_message_id=sms_result.get('provider_message_id'),
        status=status,
    )
    user.last_call_status = 'escalated'
    user.escalation_status = status
    user.last_escalated_at = timezone.now()
    user.save(update_fields=['last_call_status', 'escalation_status', 'last_escalated_at'])
