import uuid
import json
import csv
import io

from django.core.cache import cache
from django.http import FileResponse, HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status
from rest_framework.decorators import api_view, throttle_classes
from rest_framework.response import Response

from rest_framework.decorators import permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.throttling import AnonRateThrottle

from apps.accounts.phone import normalize_phone
from apps.notifications.sms_text import sms_name
from apps.checkins.models import CallAttempt, Checkin
from apps.journeys.models import JourneySession
from apps.mobile_compat.identity import (
    get_profile,
    profile_for_existing_account,
    sync_legacy_primary_to_trusted,
    sync_trusted_contacts_from_json,
)
from apps.mobile_compat.serializers import (
    AlertEventSerializer as EscalationAlertSerializer,
    CallAttemptSerializer,
    CheckinSerializer,
    JourneySessionSerializer,
    LocationSnapshotSerializer,
    SafetyProfileSerializer,
    UserTimelineEventSerializer,
)
from apps.safety.models import (
    EscalationAlert,
    LocationSnapshot,
    SafetyProfile,
    SmsMessage,
    UserTimelineEvent,
)
from apps.vault.models import VaultDocument, VaultReleaseToken
from django.conf import settings

from apps.safety.services.email_config import EmailConfig
from apps.safety.services.email_provider import EmailProvider
from apps.safety.services.schedule_engine import (
    ensure_next_scheduled_checkin,
    recompute_next_scheduled_checkin,
)
from apps.safety.services.safety_engine import escalate_to_next_of_kin, is_safe_phrase, mark_user_safe
from apps.safety.services.sms_provider import SmsProvider
from apps.safety.services.verification_store import (
    create_verification_id,
    generate_code,
    store_code,
    verify_code,
)
from apps.safety.services.voice_provider import VoiceProvider
from apps.push.push_provider import PushProvider, new_call_kit_id
from apps.vault import services as vault_service


class OtpThrottle(AnonRateThrottle):
    scope = 'auth'


def _first_present(data, keys):
    for key in keys:
        if key in data:
            return data.get(key)
    return None


def _log_timeline_event(user, event_type, source='backend', status='info', payload=None):
    account = user.user if isinstance(user, SafetyProfile) else user
    UserTimelineEvent.objects.create(
        user=account,
        event_type=event_type,
        source=source,
        status=status,
        payload_json=payload or {},
    )


def _account(profile):
    return profile.user if isinstance(profile, SafetyProfile) else profile


def _normalize_local_phone_to_e164(raw_value, country_code):
    """Accept local digits (779697569) or E164 (+256779697569) from mobile clients."""
    return normalize_phone(raw_value, country_code or 'UG')

@api_view(['GET'])
@permission_classes([AllowAny])
def health(_request):
    return Response({'status': 'ok'})

# --------------------------------------------------------------------------- #
# Email-based authentication
# --------------------------------------------------------------------------- #

from django.contrib.auth.hashers import make_password, check_password

@api_view(['POST'])
@permission_classes([AllowAny])
def send_email_code(request):
    """Send a verification code to the given email address."""
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')
    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)

    # Accounts are created by staff. Unknown emails get the same response and no message.
    user = profile_for_existing_account(email, email=email)
    verification_id = create_verification_id('email')
    if user is None:
        return Response({'verificationId': verification_id, 'message': 'Verification code sent'})
    if user.user.has_usable_password() and password:
        if not check_password(password, user.user.password):
            return Response({'error': 'Invalid email or password'}, status=status.HTTP_400_BAD_REQUEST)

    code = generate_code()
    store_code(verification_id, code, email)

    message, error_response = _send_auth_code_email(email, code, purpose='verify')
    if error_response is not None:
        return error_response

    return Response({'verificationId': verification_id, 'message': message})


def _send_auth_code_email(email: str, code: str, *, purpose: str = 'verify') -> tuple[str, Response | None]:
    """Send a verification/reset code email. Returns (message, error_response)."""
    if EmailConfig.is_configured():
        send_result = EmailProvider().send_verification_code(
            email,
            code,
            purpose=purpose,
        )
        if not send_result.get('success'):
            return '', Response(
                {'error': send_result.get('error', 'Failed to send email')},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return 'Verification code sent', None
    if settings.SAFECHECK_ALLOW_MOCK_AUTH:
        return f'Verification code sent (dev, no SMTP): {code}', None
    return '', Response(
        {'error': 'Email delivery is not configured on the server.'},
        status=status.HTTP_503_SERVICE_UNAVAILABLE,
    )


@api_view(['POST'])
@permission_classes([AllowAny])
def send_password_reset_code(request):
    """Send a password reset code to an existing email account."""
    email = (request.data.get('email') or '').strip().lower()
    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)

    # Staff-registered people use this to set their first password, so a missing one is fine.
    verification_id = create_verification_id('reset')
    if profile_for_existing_account(email, email=email) is None:
        return Response({'verificationId': verification_id, 'message': 'Verification code sent'})

    code = generate_code()
    store_code(verification_id, code, email)

    message, error_response = _send_auth_code_email(email, code, purpose='reset')
    if error_response is not None:
        return error_response

    return Response({'verificationId': verification_id, 'message': message})


@api_view(['POST'])
@permission_classes([AllowAny])
def reset_password(request):
    """Verify reset code and set a new password."""
    verification_id = request.data.get('verificationId')
    email = (request.data.get('email') or '').strip().lower()
    code = request.data.get('code')
    new_password = request.data.get('newPassword') or request.data.get('password')

    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not new_password or len(str(new_password)) < 6:
        return Response(
            {'error': 'Password must be at least 6 characters'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not verify_code(verification_id, code, subject=email):
        return Response({'error': 'Invalid code'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = get_profile(email)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.user.set_password(str(new_password))
    user.user.save(update_fields=['password'])

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = SafetyProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})


@api_view(['POST'])
@permission_classes([AllowAny])
def verify_email_code(request):
    """Verify the code the user received via email."""
    verification_id = request.data.get('verificationId')
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')
    code = request.data.get('code')

    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)

    if not verify_code(verification_id, code, subject=email):
        return Response({'error': 'Invalid code'}, status=status.HTTP_400_BAD_REQUEST)

    user = profile_for_existing_account(email, email=email)
    if user is None:
        return Response({'error': 'Invalid code'}, status=status.HTTP_400_BAD_REQUEST)

    account = user.user
    if password and not account.has_usable_password():
        account.set_password(password)
        account.save(update_fields=['password'])

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = SafetyProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Social sign-in (Google / Apple)
# --------------------------------------------------------------------------- #

@api_view(['POST'])
@permission_classes([AllowAny])
def social_sign_in(request):
    """Handle social provider sign-in.

    In production you would verify the ``idToken`` from the native SDK
    against Google / Apple and extract the user's email.  For now we trust
    the email sent by the Flutter client.
    """
    provider = request.data.get('provider', 'unknown')
    id_token = (request.data.get('idToken') or '').strip()
    email = (request.data.get('email') or '').strip().lower()
    _display_name = (request.data.get('displayName') or '').strip()

    if not settings.DEBUG and not settings.SAFECHECK_ALLOW_MOCK_AUTH:
        if not id_token:
            return Response(
                {'error': 'idToken is required for social sign-in'},
                status=status.HTTP_400_BAD_REQUEST,
            )

    if not email:
        return Response({'error': 'email is required for social sign-in'}, status=status.HTTP_400_BAD_REQUEST)

    user = profile_for_existing_account(email, email=email)
    if user is None:
        return Response(
            {'error': 'We could not sign you in. Contact SafeBangle if you need an account.'},
            status=status.HTTP_403_FORBIDDEN,
        )

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = SafetyProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Legacy phone-based OTP (kept for backward compat)
# --------------------------------------------------------------------------- #

@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OtpThrottle])
def send_otp(request):
    phone_number = normalize_phone(
        request.data.get('phoneNumber'), request.data.get('countryCode')
    )
    if not phone_number:
        return Response({'error': 'A valid phoneNumber is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not cache.add(f'otp-cooldown:{phone_number}', 1, timeout=30):
        return Response(
            {'error': 'Please wait a moment before requesting another code.'},
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    # Unknown numbers get the same response and no SMS, so nobody can check who's registered.
    verification_id = create_verification_id('otp')
    if profile_for_existing_account(phone_number, phone=phone_number) is None:
        return Response({'verificationId': verification_id, 'message': 'OTP sent'})

    code = generate_code()
    store_code(verification_id, code, phone_number)

    if settings.DEBUG or settings.SAFECHECK_ALLOW_MOCK_AUTH:
        print(f'\n*** DEBUG mobile OTP for {phone_number}: {code} ***\n', flush=True)
        message = 'OTP sent'
    else:
        sms_result = SmsProvider().send_sms(
            phone_number,
            f'Your SafeBangle verification code is {code}. It expires in 10 minutes.',
            purpose='otp',
        )
        if not sms_result.get('success'):
            return Response(
                {'error': sms_result.get('error', 'Failed to send OTP')},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        message = 'OTP sent'

    return Response({'verificationId': verification_id, 'message': message})

@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OtpThrottle])
def verify_otp(request):
    verification_id = request.data.get('verificationId')
    phone_number = normalize_phone(request.data.get('phoneNumber'))
    sms_code = request.data.get('smsCode')

    if not phone_number:
        return Response({'error': 'A valid phoneNumber is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not verify_code(verification_id, sms_code, subject=phone_number):
        return Response({'error': 'Invalid OTP'}, status=status.HTTP_400_BAD_REQUEST)

    user = profile_for_existing_account(phone_number, phone=phone_number)
    if user is None:
        return Response({'error': 'Invalid OTP'}, status=status.HTTP_400_BAD_REQUEST)

    if not user.user.phone_verified:
        user.user.phone_verified = True
        user.user.save(update_fields=['phone_verified'])

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = SafetyProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Profile & check-ins
# --------------------------------------------------------------------------- #

@api_view(['GET'])
@permission_classes([AllowAny])
def user_profile(request, uid):
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    serializer = SafetyProfileSerializer(user)
    return Response(serializer.data)

@api_view(['POST'])
@permission_classes([AllowAny])
def upsert_user_profile(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)

    user = profile_for_existing_account(str(uid))
    if user is None:
        return Response({'error': 'Account not found'}, status=status.HTTP_404_NOT_FOUND)
    alias_map = {
        'onboarding_completed': ['onboarding_completed', 'onboardingCompleted'],
        'user_type': ['user_type', 'userType'],
        'checkin_frequency': ['checkin_frequency', 'checkinFrequency'],
        'grace_period_hours': ['grace_period_hours', 'gracePeriodHours'],
        'grace_period_minutes': ['grace_period_minutes', 'gracePeriodMinutes'],
        'emergency_contact_name': ['emergency_contact_name', 'emergencyContactName'],
        'emergency_contact_relationship': [
            'emergency_contact_relationship',
            'emergencyContactRelationship',
        ],
        'emergency_contact_country_code': [
            'emergency_contact_country_code',
            'emergencyContactCountryCode',
        ],
        # emergency_contact_phone handled below (normalize local or E164)
        'emergency_contact_email': ['emergency_contact_email', 'emergencyContactEmail'],
        'emergency_contacts_json': [
            'emergency_contacts_json',
            'emergencyContactsJson',
        ],
        'trigger_actions_json': [
            'trigger_actions_json',
            'triggerActionsJson',
        ],
        'notification_prefs_json': [
            'notification_prefs_json',
            'notificationPrefsJson',
        ],
        'timezone': ['timezone', 'timeZone'],
        'max_retry_attempts': ['max_retry_attempts', 'maxRetryAttempts'],
        'last_call_status': ['last_call_status', 'lastCallStatus'],
        'escalation_status': ['escalation_status', 'escalationStatus'],
    }
    changed_fields = {}
    for field, aliases in alias_map.items():
        value = _first_present(request.data, aliases)
        if value is not None:
            setattr(user, field, value)
            changed_fields[field] = value

    emergency_phone_raw = _first_present(
        request.data, ['emergency_contact_phone', 'emergencyContactPhone']
    )
    if emergency_phone_raw is not None:
        country_code = _first_present(
            request.data, ['emergency_contact_country_code', 'emergencyContactCountryCode']
        ) or user.emergency_contact_country_code or 'UG'
        normalized_phone = _normalize_local_phone_to_e164(
            emergency_phone_raw,
            country_code,
        )
        if not normalized_phone:
            return Response(
                {'error': 'emergency_contact_phone must be a valid local number for selected country'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.emergency_contact_country_code = str(country_code).upper()
        changed_fields['emergency_contact_country_code'] = user.emergency_contact_country_code
        user.emergency_contact_phone = normalized_phone
        changed_fields['emergency_contact_phone'] = normalized_phone

    raw_pin = _first_present(request.data, ['pin'])
    if raw_pin is not None:
        pin_value = str(raw_pin).strip()
        if pin_value:
            if not pin_value.isdigit() or len(pin_value) != 4:
                return Response({'error': 'pin must be exactly 4 digits'}, status=status.HTTP_400_BAD_REQUEST)
            user.pin = make_password(pin_value)
            changed_fields['pin'] = 'updated'

    checkin_time = _first_present(request.data, ['checkin_time', 'checkinTime'])
    if checkin_time:
        try:
            user.checkin_time = timezone.datetime.strptime(checkin_time, '%H:%M').time()
            changed_fields['checkin_time'] = checkin_time
        except ValueError:
            return Response({'error': 'checkin_time must be HH:MM'}, status=status.HTTP_400_BAD_REQUEST)

    last_check_in_at = _first_present(request.data, ['last_check_in_at', 'lastCheckInAt'])
    if last_check_in_at:
        dt = parse_datetime(last_check_in_at) if isinstance(last_check_in_at, str) else None
        if dt:
            user.last_check_in_at = dt
            changed_fields['last_check_in_at'] = last_check_in_at

    schedule_fields = {'checkin_time', 'timezone', 'checkin_frequency'}
    if schedule_fields.intersection(changed_fields.keys()):
        recompute_next_scheduled_checkin(user)

    user.save()

    contacts_raw = _first_present(
        request.data, ['emergency_contacts_json', 'emergencyContactsJson']
    )
    if contacts_raw is not None:
        sync_trusted_contacts_from_json(
            user,
            contacts_raw if isinstance(contacts_raw, str) else json.dumps(contacts_raw),
        )
    else:
        sync_legacy_primary_to_trusted(user)

    account = user.user
    full_name = _first_present(request.data, ['full_name', 'fullName'])
    if full_name:
        parts = str(full_name).strip().split(None, 1)
        account.first_name = parts[0] if parts else ''
        account.last_name = parts[1] if len(parts) > 1 else ''
        account.save(update_fields=['first_name', 'last_name'])
    phone_number = _normalize_local_phone_to_e164(
        _first_present(request.data, ['phone_number', 'phoneNumber']),
        account.country_code,
    )
    # Blank or invalid values never overwrite a stored number, and numbers can't be taken over.
    if phone_number and phone_number != account.phone:
        if type(account).objects.filter(phone=phone_number).exclude(pk=account.pk).exists():
            return Response(
                {'error': 'This phone number belongs to another account.'},
                status=status.HTTP_409_CONFLICT,
            )
        account.phone = phone_number
        account.phone_verified = False
        account.save(update_fields=['phone', 'phone_verified'])

    onboarding_completed_val = _first_present(
        request.data, ['onboarding_completed', 'onboardingCompleted']
    )
    if onboarding_completed_val in (True, 'true', 'True', 1, '1'):
        if user.onboarding_step is not None or user.onboarding_draft_json:
            user.onboarding_step = None
            user.onboarding_draft_json = None
            user.save(update_fields=['onboarding_step', 'onboarding_draft_json'])
            changed_fields['onboarding_draft_cleared'] = True

    if changed_fields:
        _log_timeline_event(
            user=user,
            event_type='profile_updated',
            source='app',
            status='success',
            payload={'fields': changed_fields},
        )
    return Response(SafetyProfileSerializer(user).data, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([AllowAny])
def verify_pin(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    raw_pin = _first_present(request.data, ['pin'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    if raw_pin is None:
        return Response({'error': 'pin is required'}, status=status.HTTP_400_BAD_REQUEST)

    pin_value = str(raw_pin).strip()
    if not pin_value.isdigit() or len(pin_value) != 4:
        return Response({'error': 'pin must be exactly 4 digits'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    stored_pin = (user.pin or '').strip()
    if not stored_pin:
        return Response({'valid': False})

    return Response({'valid': check_password(pin_value, stored_pin)})


def _parse_onboarding_draft(raw_value):
    if raw_value is None:
        return None
    if isinstance(raw_value, dict):
        return raw_value
    if isinstance(raw_value, str):
        text = raw_value.strip()
        if not text:
            return None
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


@api_view(['GET'])
@permission_classes([AllowAny])
def get_onboarding_draft(request, uid):
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    if user.onboarding_completed:
        return Response(
            {
                'uid': user.uid,
                'onboarding_completed': True,
                'step': None,
                'draft': None,
            }
        )

    draft = _parse_onboarding_draft(user.onboarding_draft_json)
    return Response(
        {
            'uid': user.uid,
            'onboarding_completed': False,
            'step': user.onboarding_step,
            'draft': draft,
        }
    )


@api_view(['POST'])
@permission_classes([AllowAny])
def save_onboarding_draft(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)

    user = profile_for_existing_account(str(uid))
    if user is None:
        return Response({'error': 'Account not found'}, status=status.HTTP_404_NOT_FOUND)
    if user.onboarding_completed:
        return Response(
            {'error': 'Onboarding is already completed'},
            status=status.HTTP_409_CONFLICT,
        )

    step = _first_present(request.data, ['step', 'onboarding_step', 'onboardingStep'])
    draft_raw = _first_present(request.data, ['draft', 'onboarding_draft', 'onboardingDraft'])
    draft = _parse_onboarding_draft(draft_raw)
    if draft is None:
        return Response(
            {'error': 'draft must be a JSON object'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if step is not None:
        try:
            step_int = int(step)
        except (TypeError, ValueError):
            return Response(
                {'error': 'step must be an integer'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if step_int < 0:
            return Response(
                {'error': 'step must be >= 0'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.onboarding_step = step_int
    elif user.onboarding_step is None:
        user.onboarding_step = 0

    user.onboarding_draft_json = json.dumps(draft)
    user.save(update_fields=['onboarding_step', 'onboarding_draft_json'])

    _log_timeline_event(
        user=user,
        event_type='onboarding_draft_saved',
        source='app',
        status='success',
        payload={'step': user.onboarding_step},
    )

    return Response(
        {
            'uid': user.uid,
            'onboarding_completed': False,
            'step': user.onboarding_step,
            'draft': draft,
        },
        status=status.HTTP_200_OK,
    )


@api_view(['DELETE'])
@permission_classes([AllowAny])
def clear_onboarding_draft(request, uid):
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.onboarding_step = None
    user.onboarding_draft_json = None
    user.save(update_fields=['onboarding_step', 'onboarding_draft_json'])
    return Response({'uid': user.uid, 'cleared': True}, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([AllowAny])
def register_push_token(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    fcm_token = _first_present(request.data, ['fcm_token', 'fcmToken'])
    platform = _first_present(request.data, ['platform', 'fcm_platform', 'fcmPlatform'])

    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not fcm_token:
        return Response({'error': 'fcm_token is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.fcm_token = str(fcm_token).strip()
    user.fcm_token_updated_at = timezone.now()
    user.fcm_platform = str(platform or '').strip() or None
    ensure_next_scheduled_checkin(user)
    user.save(
        update_fields=[
            'fcm_token',
            'fcm_token_updated_at',
            'fcm_platform',
            'next_scheduled_checkin_at',
        ]
    )
    _log_timeline_event(
        user=user,
        event_type='fcm_token_registered',
        source='app',
        status='success',
        payload={'platform': user.fcm_platform},
    )
    return Response(
        {
            'ok': True,
            'next_scheduled_checkin_at': user.next_scheduled_checkin_at,
        },
        status=status.HTTP_200_OK,
    )


@api_view(['GET'])
@permission_classes([AllowAny])
def checkins(request):
    uid = request.query_params.get('uid')
    checks = Checkin.objects.all().order_by('-timestamp')
    if uid:
        checks = checks.filter(user_id=uid)
    serializer = CheckinSerializer(checks, many=True)
    return Response(serializer.data)

@api_view(['POST'])
@permission_classes([AllowAny])
def confirm_safe_checkin(request):
    uid = request.data.get('uid') or request.data.get('user_id')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    mark_user_safe(user)
    _log_timeline_event(
        user=user,
        event_type='safe_confirmed',
        source='app',
        status='safe_confirmed',
        payload={'uid': uid},
    )
    return Response({'ok': True, 'last_call_status': user.last_call_status})


@api_view(['POST'])
@permission_classes([AllowAny])
def snooze_checkin(request):
    uid = request.data.get('uid') or request.data.get('user_id')
    snoozed_until_raw = request.data.get('snoozed_until') or request.data.get('snoozedUntil')
    if not uid or not snoozed_until_raw:
        return Response(
            {'error': 'uid and snoozed_until are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    dt = parse_datetime(str(snoozed_until_raw)) if isinstance(snoozed_until_raw, str) else None
    if dt is None:
        return Response({'error': 'snoozed_until must be ISO datetime'}, status=status.HTTP_400_BAD_REQUEST)

    user.snoozed_until = dt
    user.save(update_fields=['snoozed_until'])
    _log_timeline_event(
        user=user,
        event_type='checkin_snoozed',
        source='app',
        status='snoozed',
        payload={'snoozed_until': dt.isoformat()},
    )
    return Response({'ok': True, 'snoozed_until': user.snoozed_until})


@api_view(['POST'])
@permission_classes([AllowAny])
def unregister_push_token(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.fcm_token = None
    user.fcm_token_updated_at = timezone.now()
    user.save(update_fields=['fcm_token', 'fcm_token_updated_at'])
    _log_timeline_event(
        user=user,
        event_type='fcm_token_unregistered',
        source='app',
        status='success',
    )
    return Response({'ok': True})


@api_view(['POST'])
@permission_classes([AllowAny])
def create_checkin(request):
    user_uid = request.data.get('user_id')
    status_field = request.data.get('status', 'ok')

    try:
        user = get_profile(user_uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    if status_field == 'safe_confirmed':
        mark_user_safe(user, text='app_checkin')
        checkin = Checkin.objects.filter(user=_account(user)).order_by('-timestamp').first()
    else:
        checkin = Checkin.objects.create(user=_account(user), status=status_field)

    _log_timeline_event(
        user=user,
        event_type='checkin_recorded',
        source='app',
        status=status_field,
        payload={'checkin_id': checkin.id if checkin else None},
    )
    serializer = CheckinSerializer(checkin)
    return Response(serializer.data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([AllowAny])
def call_attempts(request, uid):
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    attempts = _account(user).call_attempts.all().order_by('-created_at')
    return Response(CallAttemptSerializer(attempts, many=True).data)


@api_view(['GET'])
@permission_classes([AllowAny])
def alerts(request, uid):
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    entries = EscalationAlert.objects.filter(user=_account(user)).order_by('-created_at')
    return Response(EscalationAlertSerializer(entries, many=True).data)


@api_view(['POST'])
@permission_classes([AllowAny])
def update_location(request):
    uid = request.data.get('uid')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    if not uid or latitude is None or longitude is None:
        return Response({'error': 'uid, latitude, longitude are required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    snapshot = LocationSnapshot.objects.create(
        user=_account(user),
        latitude=float(latitude),
        longitude=float(longitude),
        accuracy_meters=request.data.get('accuracy_meters'),
        address=request.data.get('address'),
    )
    return Response(LocationSnapshotSerializer(snapshot).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([AllowAny])
def trigger_checkin_call(request):
    uid = request.data.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    last_attempt = _account(user).call_attempts.order_by('-attempt_number').first()
    attempt_number = (last_attempt.attempt_number + 1) if last_attempt else 1
    if not user.phone_number:
        # Dev-friendly fallback: allow timeline/testing flows without a saved phone.
        attempt = CallAttempt.objects.create(
            user=user,
            attempt_number=attempt_number,
            provider_call_id=f"mock-no-phone-{attempt_number}",
            status='failed',
            recognized_text='Call not placed: user phone number missing',
            scheduled_for=timezone.now(),
            completed_at=timezone.now(),
        )
        user.last_call_status = attempt.status
        user.save(update_fields=['last_call_status'])
        _log_timeline_event(
            user=user,
            event_type='checkin_call_triggered',
            source='backend',
            status='failed',
            payload={'attempt_number': attempt_number, 'reason': 'missing_phone_number'},
        )
        return Response(
            {
                'warning': 'Phone number missing. Created mock failed call attempt.',
                'attempt': CallAttemptSerializer(attempt).data,
            },
            status=status.HTTP_201_CREATED,
        )

    result = VoiceProvider().place_checkin_call(user.phone_number, user.uid)

    attempt = CallAttempt.objects.create(
        user=_account(user),
        attempt_number=attempt_number,
        provider_call_id=result.get('provider_call_id'),
        status='in_progress' if result.get('success') else 'failed',
        scheduled_for=timezone.now(),
    )

    user.last_call_status = attempt.status
    user.save(update_fields=['last_call_status'])
    _log_timeline_event(
        user=user,
        event_type='checkin_call_triggered',
        source='backend',
        status=attempt.status,
        payload={'attempt_number': attempt_number, 'provider_call_id': attempt.provider_call_id},
    )

    if not result.get('success'):
        return Response({'error': result.get('error', 'Unable to place call')}, status=status.HTTP_502_BAD_GATEWAY)

    return Response(CallAttemptSerializer(attempt).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([AllowAny])
def escalate_missed_checkin(request):
    uid = request.data.get('uid')
    reason = (request.data.get('reason') or 'missed_or_declined').strip()
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.last_call_status = reason
    user.save(update_fields=['last_call_status'])
    escalate_to_next_of_kin(user)
    _log_timeline_event(
        user=user,
        event_type='checkin_escalated',
        source='backend',
        status='escalated',
        payload={'reason': reason, 'escalation_status': user.escalation_status},
    )
    return Response(
        {
            'ok': True,
            'result': 'escalation_attempted',
            'escalation_status': user.escalation_status,
            'last_call_status': user.last_call_status,
        }
    )


@api_view(['POST'])
@permission_classes([AllowAny])
def call_status_webhook(request):
    provider_call_id = request.data.get('providerCallId') or request.data.get('sessionId')
    status_text = (request.data.get('status') or '').lower()
    recognized_text = request.data.get('speechText') or request.data.get('recognizedText') or ''

    attempt = None
    if provider_call_id:
        attempt = CallAttempt.objects.filter(provider_call_id=provider_call_id).order_by('-created_at').first()

    if not attempt:
        return Response({'ok': True, 'message': 'No matching attempt found'})

    user = attempt.user
    if is_safe_phrase(recognized_text):
        mark_user_safe(user, text=recognized_text)
        _log_timeline_event(
            user=user,
            event_type='call_safe_confirmed',
            source='webhook',
            status='safe_confirmed',
            payload={'provider_call_id': provider_call_id, 'recognized_text': recognized_text},
        )
        return Response({'ok': True, 'result': 'safe_confirmed'})

    if status_text in ('no_answer', 'busy', 'failed', 'timeout') or not recognized_text:
        attempt.status = 'no_answer'
    else:
        attempt.status = 'unsafe_detected'
        attempt.recognized_text = recognized_text
    attempt.completed_at = timezone.now()
    attempt.save(update_fields=['status', 'recognized_text', 'completed_at'])
    _log_timeline_event(
        user=user,
        event_type='call_status_updated',
        source='webhook',
        status=attempt.status,
        payload={'provider_call_id': provider_call_id, 'recognized_text': recognized_text},
    )

    max_attempts = user.max_retry_attempts or 3
    completed_attempts = CallAttempt.objects.filter(user=_account(user)).count()
    if completed_attempts >= max_attempts:
        escalate_to_next_of_kin(user)
        _log_timeline_event(
            user=user,
            event_type='call_escalated_after_retries',
            source='webhook',
            status='escalated',
            payload={'completed_attempts': completed_attempts, 'max_attempts': max_attempts},
        )
        return Response({'ok': True, 'result': 'escalated'})

    # retry
    VoiceProvider().place_checkin_call(user.phone_number, user.uid)
    retry = CallAttempt.objects.create(
        user=_account(user),
        attempt_number=completed_attempts + 1,
        status='in_progress',
        scheduled_for=timezone.now(),
    )
    user.last_call_status = retry.status
    user.save(update_fields=['last_call_status'])
    _log_timeline_event(
        user=user,
        event_type='call_retry_scheduled',
        source='webhook',
        status='in_progress',
        payload={'attempt_number': retry.attempt_number},
    )
    return Response({'ok': True, 'result': 'retrying', 'attempt': retry.attempt_number})


def _extract_inbound_sms_fields(data: dict) -> tuple[str, str, str, str]:
    """Normalize KaCyber / Africa's Talking inbound SMS webhook payloads."""
    phone = (
        data.get('from')
        or data.get('sender')
        or data.get('msisdn')
        or data.get('phoneNumber')
        or data.get('phone')
        or ''
    )
    text = (
        data.get('text')
        or data.get('message')
        or data.get('body')
        or data.get('sms')
        or ''
    )
    provider_id = (
        data.get('id')
        or data.get('messageId')
        or data.get('kacyberReference')
        or data.get('provider_message_id')
        or ''
    )
    provider = (data.get('provider') or '').strip().lower()
    if not provider:
        if data.get('kacyberReference') or 'kacyber' in str(data).lower():
            provider = 'kacyber'
        elif data.get('shortCode') or data.get('linkId'):
            provider = 'africastalking'
        else:
            from apps.safety.services.provider_config import ProviderConfig

            provider = ProviderConfig.sms_provider_name()
    return str(phone).strip(), str(text).strip(), str(provider_id).strip(), provider


@api_view(['POST'])
@permission_classes([AllowAny])
def sms_inbound_webhook(request):
    """Receive inbound SMS callbacks from KaCyber or Africa's Talking."""
    data = request.data if isinstance(request.data, dict) else {}
    phone, text, provider_id, provider = _extract_inbound_sms_fields(data)
    if not phone and not text:
        return Response(
            {'error': 'from/phone and message/text are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = None
    digits = ''.join(ch for ch in phone if ch.isdigit())
    if digits:
        from django.contrib.auth import get_user_model

        Account = get_user_model()
        account = Account.objects.filter(phone__endswith=digits[-9:]).first()
        profile = None
        if account and hasattr(account, "safety_profile"):
            profile = account.safety_profile
        if profile is None:
            profile = SafetyProfile.objects.filter(legacy_uid__endswith=digits[-9:]).first()
        user = profile.user if profile else None

    entry = SmsProvider.record_inbound(
        phone_number=phone or digits,
        message=text,
        provider=provider,
        provider_message_id=provider_id,
        raw_payload=data,
        user=user,
    )
    return Response(
        {
            'ok': True,
            'id': entry.id,
            'direction': entry.direction,
            'status': entry.status,
        }
    )


@api_view(['GET'])
@permission_classes([AllowAny])
def list_sms_messages(request):
    """List tracked SMS for admin/app. Optional filters: uid, phone, direction."""
    from apps.safety.models import SmsMessage

    qs = SmsMessage.objects.all().order_by('-created_at')
    uid = request.query_params.get('uid')
    phone = request.query_params.get('phone')
    direction = request.query_params.get('direction')
    if uid:
        profile = SafetyProfile.objects.filter(legacy_uid=uid).select_related('user').first()
        if profile and profile.user_id:
            qs = qs.filter(user_id=profile.user_id)
        else:
            qs = qs.none()
    if phone:
        digits = ''.join(ch for ch in phone if ch.isdigit())
        qs = qs.filter(phone_number__icontains=digits or phone)
    if direction in ('inbound', 'outbound'):
        qs = qs.filter(direction=direction)

    limit = min(int(request.query_params.get('limit') or 100), 500)
    rows = list(qs[:limit])
    return Response(
        {
            'count': qs.count(),
            'results': [
                {
                    'id': row.id,
                    'direction': row.direction,
                    'provider': row.provider,
                    'purpose': row.purpose,
                    'phone_number': row.phone_number,
                    'message': row.message,
                    'status': row.status,
                    'provider_message_id': row.provider_message_id,
                    'cost': row.cost,
                    'error': row.error,
                    'uid': getattr(row.user, 'email', None) or row.user_id,
                    'created_at': row.created_at.isoformat() if row.created_at else None,
                }
                for row in rows
            ],
        }
    )


@api_view(['POST'])
@permission_classes([AllowAny])
def send_sms_message(request):
    """App/API send path — same SmsProvider used by escalation/OTP (logged to admin)."""
    phone = (
        request.data.get('phone')
        or request.data.get('phoneNumber')
        or request.data.get('to')
        or ''
    ).strip()
    message = (request.data.get('message') or request.data.get('text') or '').strip()
    purpose = (request.data.get('purpose') or 'general').strip() or 'general'
    uid = request.data.get('uid')

    if not phone or not message:
        return Response(
            {'error': 'phone and message are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = None
    if uid:
        profile = SafetyProfile.objects.filter(legacy_uid=uid).first()
        user = profile.user if profile else None

    result = SmsProvider().send_sms(phone, message, purpose=purpose, user=user)
    from apps.safety.services.provider_config import ProviderConfig

    status_code = status.HTTP_200_OK if result.get('success') else status.HTTP_503_SERVICE_UNAVAILABLE
    return Response(
        {
            'ok': bool(result.get('success')),
            'provider_message_id': result.get('provider_message_id'),
            'cost': result.get('cost'),
            'error': result.get('error'),
            'provider': ProviderConfig.sms_provider_name(),
        },
        status=status_code,
    )


@api_view(['GET', 'POST'])
@permission_classes([AllowAny])
def timeline_events_collection(request):
    if request.method == 'GET':
        uid = request.query_params.get('uid')
        entries = UserTimelineEvent.objects.all().order_by('-created_at')
        if uid:
            entries = entries.filter(user_id=uid)
        return Response(UserTimelineEventSerializer(entries, many=True).data)

    uid = _first_present(request.data, ['uid', 'user_id', 'userId'])
    event_type = request.data.get('event_type')
    if not uid or not event_type:
        return Response({'error': 'uid and event_type are required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    event = UserTimelineEvent.objects.create(
        user=_account(user),
        event_type=event_type,
        source=request.data.get('source') or 'app',
        status=request.data.get('status') or 'info',
        payload_json=request.data.get('payload_json') or {},
    )
    return Response(UserTimelineEventSerializer(event).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([AllowAny])
def journey_active(request):
    uid = request.query_params.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    journey = JourneySession.objects.filter(user_id=uid, status='active').first()
    if journey is None:
        return Response({'active': False})
    return Response({'active': True, 'journey': JourneySessionSerializer(journey).data})


@api_view(['POST'])
@permission_classes([AllowAny])
def journey_start(request):
    uid = request.data.get('uid')
    from_location = (request.data.get('from_location') or '').strip()
    to_location = (request.data.get('to_location') or '').strip()
    duration_minutes = request.data.get('duration_minutes')
    checkin_frequency = request.data.get('checkin_frequency') or 'none'

    if not uid or not from_location or not to_location or duration_minutes is None:
        return Response(
            {'error': 'uid, from_location, to_location, duration_minutes are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if checkin_frequency not in {'none', '30', '60'}:
        return Response({'error': 'Invalid checkin_frequency'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    JourneySession.objects.filter(user=user, status='active').update(status='cancelled')

    try:
        duration_minutes = int(duration_minutes)
    except (TypeError, ValueError):
        return Response({'error': 'duration_minutes must be an integer'}, status=status.HTTP_400_BAD_REQUEST)
    if duration_minutes < 10 or duration_minutes > 480:
        return Response({'error': 'duration_minutes must be between 10 and 480'}, status=status.HTTP_400_BAD_REQUEST)

    expected_arrival_at = timezone.now() + timezone.timedelta(minutes=duration_minutes)
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')

    journey = JourneySession.objects.create(
        user=_account(user),
        from_location=from_location,
        to_location=to_location,
        duration_minutes=duration_minutes,
        checkin_frequency=checkin_frequency,
        expected_arrival_at=expected_arrival_at,
        last_latitude=float(latitude) if latitude is not None else None,
        last_longitude=float(longitude) if longitude is not None else None,
    )

    if latitude is not None and longitude is not None:
        LocationSnapshot.objects.create(
            user=user,
            latitude=float(latitude),
            longitude=float(longitude),
            address=from_location,
        )

    _log_timeline_event(
        user=user,
        event_type='journey_mode_started',
        source='backend',
        status='success',
        payload={
            'journey_id': str(journey.id),
            'from_location': from_location,
            'to_location': to_location,
            'duration_minutes': duration_minutes,
            'checkin_frequency': checkin_frequency,
            'expected_arrival_at': expected_arrival_at.isoformat(),
        },
    )
    return Response(JourneySessionSerializer(journey).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([AllowAny])
def journey_confirm_arrival(request, journey_id):
    uid = request.data.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        journey = JourneySession.objects.get(id=journey_id, user_id=uid, status='active')
    except JourneySession.DoesNotExist:
        return Response({'error': 'Active journey not found'}, status=status.HTTP_404_NOT_FOUND)

    now = timezone.now()
    journey.status = 'completed'
    journey.arrived_at = now
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    if latitude is not None and longitude is not None:
        journey.last_latitude = float(latitude)
        journey.last_longitude = float(longitude)
        LocationSnapshot.objects.create(
            user=journey.user,
            latitude=float(latitude),
            longitude=float(longitude),
            address=journey.to_location,
        )
    journey.save()

    mark_user_safe(journey.user)
    _log_timeline_event(
        user=journey.user,
        event_type='journey_arrival_confirmed',
        source='backend',
        status='success',
        payload={'journey_id': str(journey.id)},
    )
    return Response(JourneySessionSerializer(journey).data)


@api_view(['POST'])
@permission_classes([AllowAny])
def journey_end(request, journey_id):
    uid = request.data.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    reason = (request.data.get('reason') or 'cancelled').strip()
    try:
        journey = JourneySession.objects.get(id=journey_id, user_id=uid, status='active')
    except JourneySession.DoesNotExist:
        return Response({'error': 'Active journey not found'}, status=status.HTTP_404_NOT_FOUND)

    journey.status = 'missed' if reason == 'missed' else 'cancelled'
    journey.save(update_fields=['status'])

    event_type = 'journey_missed' if reason == 'missed' else 'journey_mode_ended'
    _log_timeline_event(
        user=journey.user,
        event_type=event_type,
        source='backend',
        status='success',
        payload={'journey_id': str(journey.id), 'reason': reason},
    )
    if reason == 'missed':
        escalate_to_next_of_kin(journey.user)
    return Response(JourneySessionSerializer(journey).data)


@api_view(['POST'])
@permission_classes([AllowAny])
def journey_ping(request, journey_id):
    uid = request.data.get('uid')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    if not uid or latitude is None or longitude is None:
        return Response(
            {'error': 'uid, latitude, longitude are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        journey = JourneySession.objects.get(id=journey_id, user_id=uid, status='active')
    except JourneySession.DoesNotExist:
        return Response({'error': 'Active journey not found'}, status=status.HTTP_404_NOT_FOUND)

    journey.last_latitude = float(latitude)
    journey.last_longitude = float(longitude)
    journey.save(update_fields=['last_latitude', 'last_longitude'])
    LocationSnapshot.objects.create(
        user=journey.user,
        latitude=float(latitude),
        longitude=float(longitude),
        address=journey.to_location,
    )
    return Response(JourneySessionSerializer(journey).data)


# --------------------------------------------------------------------------- #
# Compatibility endpoints (avoid 404s from legacy frontend routes)
# --------------------------------------------------------------------------- #

@api_view(['GET'])
@permission_classes([AllowAny])
def alerts_collection(request):
    uid = request.query_params.get('uid')
    entries = EscalationAlert.objects.all().order_by('-created_at')
    if uid:
        entries = entries.filter(user_id=uid)
    return Response(EscalationAlertSerializer(entries, many=True).data)


@api_view(['GET'])
@permission_classes([AllowAny])
def incidents_collection(request):
    uid = request.query_params.get('uid')
    attempts = CallAttempt.objects.all().order_by('-created_at')
    if uid:
        attempts = attempts.filter(user_id=uid)
    data = [
        {
            'id': row.id,
            'user_id': row.user_id,
            'incident_type': 'unsafe_checkin' if row.status == 'unsafe_detected' else row.status,
            'status': row.status,
            'created_at': row.created_at,
            'details': row.recognized_text or '',
        }
        for row in attempts
    ]
    return Response(data)


@api_view(['GET'])
@permission_classes([AllowAny])
def patrol_logs_collection(request):
    checks = Checkin.objects.all().order_by('-timestamp')
    data = [
        {
            'id': row.id,
            'user_id': row.user_id,
            'status': row.status,
            'timestamp': row.timestamp,
        }
        for row in checks
    ]
    return Response(data)


@api_view(['GET'])
@permission_classes([AllowAny])
def checkpoints_collection(_request):
    # Placeholder structure for clients expecting checkpoint resources.
    return Response([])


@api_view(['GET'])
@permission_classes([AllowAny])
def guards_collection(_request):
    # Placeholder structure for clients expecting guards resources.
    return Response([])


@api_view(['GET', 'POST'])
@permission_classes([AllowAny])
def location_pings_collection(request):
    if request.method == 'GET':
        uid = request.query_params.get('uid')
        snapshots = LocationSnapshot.objects.all().order_by('-captured_at')
        if uid:
            snapshots = snapshots.filter(user_id=uid)
        return Response(LocationSnapshotSerializer(snapshots, many=True).data)

    # POST behavior compatible with /user/location/
    uid = request.data.get('uid')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    if not uid or latitude is None or longitude is None:
        return Response({'error': 'uid, latitude, longitude are required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    snapshot = LocationSnapshot.objects.create(
        user=_account(user),
        latitude=float(latitude),
        longitude=float(longitude),
        accuracy_meters=request.data.get('accuracy_meters'),
        address=request.data.get('address'),
    )
    return Response(LocationSnapshotSerializer(snapshot).data, status=status.HTTP_201_CREATED)


def _checkin_export_status(user: SafetyProfile, when) -> str:
    if user.checkin_time is None:
        return 'on_time'
    scheduled = when.replace(
        hour=user.checkin_time.hour,
        minute=user.checkin_time.minute,
        second=0,
        microsecond=0,
    )
    grace = user.grace_period_timedelta()
    if when > scheduled + grace:
        return 'missed'
    if when > scheduled:
        return 'late'
    return 'on_time'


@api_view(['GET'])
@permission_classes([AllowAny])
def export_checkins_csv(request):
    uid = request.query_params.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    checks = Checkin.objects.filter(user=_account(user)).order_by('-timestamp')
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(['timestamp', 'status', 'derived_status'])
    for checkin in checks:
        derived = _checkin_export_status(user, checkin.timestamp)
        writer.writerow([
            checkin.timestamp.isoformat(),
            checkin.status,
            derived,
        ])

    response = HttpResponse(buffer.getvalue(), content_type='text/csv')
    response['Content-Disposition'] = f'attachment; filename="safecheck-history-{uid}.csv"'
    return response


def _update_contact_opt_in(user: SafetyProfile, contact_id: str, status_value: str) -> bool:
    raw = (user.emergency_contacts_json or '').strip()
    if not raw:
        return False
    try:
        contacts = json.loads(raw)
    except json.JSONDecodeError:
        return False
    if not isinstance(contacts, list):
        return False
    updated = False
    for item in contacts:
        if not isinstance(item, dict):
            continue
        if str(item.get('id') or '') == contact_id:
            item['opt_in_status'] = status_value
            updated = True
            break
    if updated:
        user.emergency_contacts_json = json.dumps(contacts)
        user.save(update_fields=['emergency_contacts_json'])
    return updated


@api_view(['POST'])
@permission_classes([AllowAny])
def send_contact_opt_in(request):
    uid = request.data.get('uid')
    contact_id = request.data.get('contact_id') or request.data.get('contactId')
    if not uid or not contact_id:
        return Response(
            {'error': 'uid and contact_id are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    raw = (user.emergency_contacts_json or '').strip()
    if not raw:
        return Response({'error': 'No contacts found'}, status=status.HTTP_404_NOT_FOUND)
    try:
        contacts = json.loads(raw)
    except json.JSONDecodeError:
        return Response({'error': 'Invalid contacts data'}, status=status.HTTP_400_BAD_REQUEST)

    target = None
    for item in contacts:
        if isinstance(item, dict) and str(item.get('id') or '') == str(contact_id):
            target = item
            break
    if target is None:
        return Response({'error': 'Contact not found'}, status=status.HTTP_404_NOT_FOUND)

    phone = _normalize_local_phone_to_e164(
        str(target.get('phone') or ''),
        str(target.get('country_code') or user.emergency_contact_country_code or 'UG'),
    )
    if not phone:
        return Response({'error': 'Invalid contact phone'}, status=status.HTTP_400_BAD_REQUEST)

    owner_name = sms_name(user.full_name or user.uid, fallback='A SafeBangle user')
    message = (
        f"{owner_name} added you as an emergency contact on SafeBangle. "
        "You'll get a text if they need help. Reply STOP to opt out."
    )
    sms_result = SmsProvider().send_sms(phone, message, purpose='contact_opt_in', user=user)
    sent = bool(sms_result.get('success'))
    if sent:
        _update_contact_opt_in(user, str(contact_id), 'sent')
    EscalationAlert.objects.create(
        user=_account(user),
        channel='sms',
        recipient=phone,
        message=message,
        provider_message_id=sms_result.get('provider_message_id'),
        status='sent' if sent else 'failed',
    )
    return Response({'ok': sent, 'opt_in_status': 'sent' if sent else 'failed'})


@api_view(['GET'])
@permission_classes([AllowAny])
def list_vault_documents(request):
    uid = request.query_params.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    docs = VaultDocument.objects.filter(user_id=uid).order_by('uploaded_at')
    payload = [
        {
            'doc_id': doc.doc_id,
            'title': doc.title,
            'format': doc.format,
            'size_bytes': doc.size_bytes,
            'status': doc.status,
            'uploaded_at': doc.uploaded_at.isoformat() if doc.uploaded_at else None,
        }
        for doc in docs
    ]
    return Response(payload)


@api_view(['POST'])
@permission_classes([AllowAny])
def upload_vault_document(request):
    uid = request.data.get('uid') or request.POST.get('uid')
    doc_id = request.data.get('doc_id') or request.POST.get('doc_id') or f'doc_{uuid.uuid4().hex[:12]}'
    title = (request.data.get('title') or request.POST.get('title') or 'Document').strip()
    slot_id = request.data.get('slot_id') or request.POST.get('slot_id')
    upload = request.FILES.get('file')
    if not uid or upload is None:
        return Response(
            {'error': 'uid and file are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        user = get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    if slot_id:
        doc_id = str(slot_id)
    extension = upload.name.split('.')[-1].upper() if '.' in upload.name else 'FILE'
    doc, _ = VaultDocument.objects.update_or_create(
        user=user,
        doc_id=doc_id,
        defaults={
            'title': title,
            'format': extension,
            'size_bytes': upload.size or 0,
            'status': 'active',
        },
    )
    doc.file.save(upload.name, upload, save=True)
    doc.size_bytes = upload.size or doc.file.size
    doc.save(update_fields=['file', 'size_bytes'])
    return Response(
        {
            'doc_id': doc.doc_id,
            'title': doc.title,
            'format': doc.format,
            'size_bytes': doc.size_bytes,
            'status': doc.status,
            'uploaded_at': doc.uploaded_at.isoformat(),
        },
        status=status.HTTP_201_CREATED,
    )


@api_view(['GET'])
@permission_classes([AllowAny])
def download_vault_document(request, doc_id):
    from django.http import FileResponse

    uid = request.query_params.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        doc = VaultDocument.objects.get(user_id=uid, doc_id=doc_id)
    except VaultDocument.DoesNotExist:
        return Response({'error': 'Document not found'}, status=status.HTTP_404_NOT_FOUND)
    if not doc.file:
        return Response({'error': 'No file stored for this document'}, status=status.HTTP_404_NOT_FOUND)
    return FileResponse(doc.file.open('rb'), as_attachment=True, filename=doc.file.name.split('/')[-1])


@api_view(['DELETE', 'POST'])
@permission_classes([AllowAny])
def delete_vault_document(request, doc_id):
    uid = request.query_params.get('uid') or request.data.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    deleted, _ = VaultDocument.objects.filter(user_id=uid, doc_id=doc_id).delete()
    if not deleted:
        return Response({'error': 'Document not found'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'ok': True})


@api_view(['GET'])
@permission_classes([AllowAny])
def release_vault_documents(request, token):
    try:
        release = VaultReleaseToken.objects.select_related('user').get(token=token)
    except VaultReleaseToken.DoesNotExist:
        return Response({'error': 'Invalid release link'}, status=status.HTTP_404_NOT_FOUND)
    if release.used_at is not None or release.expires_at < timezone.now():
        return Response({'error': 'Release link expired'}, status=status.HTTP_410_GONE)

    docs = VaultDocument.objects.filter(user=release.user, status='active').exclude(file='')
    payload = [
        {
            'doc_id': doc.doc_id,
            'title': doc.title,
            'format': doc.format,
            'size_bytes': doc.size_bytes,
            'download_url': f'/api/vault/release/{token}/{doc.doc_id}/download/',
        }
        for doc in docs
    ]
    return Response({'documents': payload, 'expires_at': release.expires_at.isoformat()})


@api_view(['GET'])
@permission_classes([AllowAny])
def download_released_vault_document(request, token, doc_id):
    try:
        release = VaultReleaseToken.objects.select_related('user').get(token=token)
    except VaultReleaseToken.DoesNotExist:
        return Response({'error': 'Invalid release link'}, status=status.HTTP_404_NOT_FOUND)
    if release.used_at is not None or release.expires_at < timezone.now():
        return Response({'error': 'Release link expired'}, status=status.HTTP_410_GONE)
    try:
        doc = VaultDocument.objects.get(user=release.user, doc_id=doc_id, status='active')
    except VaultDocument.DoesNotExist:
        return Response({'error': 'Document not found'}, status=status.HTTP_404_NOT_FOUND)
    if not doc.file:
        return Response({'error': 'File unavailable'}, status=status.HTTP_404_NOT_FOUND)
    release.used_at = timezone.now()
    release.save(update_fields=['used_at'])
    return FileResponse(doc.file.open('rb'), as_attachment=True, filename=doc.file.name.split('/')[-1])
