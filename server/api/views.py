import uuid
import re
import phonenumbers

from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .models import AlertEvent, CallAttempt, Checkin, LocationSnapshot, UserProfile, UserTimelineEvent
from .serializers import (
    AlertEventSerializer,
    CallAttemptSerializer,
    CheckinSerializer,
    LocationSnapshotSerializer,
    UserTimelineEventSerializer,
    UserProfileSerializer,
)
from django.conf import settings

from .services.email_config import EmailConfig
from .services.email_provider import EmailProvider
from .services.schedule_engine import (
    ensure_next_scheduled_checkin,
    recompute_next_scheduled_checkin,
)
from .services.safety_engine import escalate_to_next_of_kin, is_safe_phrase, mark_user_safe
from .services.sms_provider import SmsProvider
from .services.verification_store import (
    create_verification_id,
    generate_code,
    store_code,
    verify_code,
)
from .services.voice_provider import VoiceProvider


def _first_present(data, keys):
    for key in keys:
        if key in data:
            return data.get(key)
    return None


def _log_timeline_event(user, event_type, source='backend', status='info', payload=None):
    UserTimelineEvent.objects.create(
        user=user,
        event_type=event_type,
        source=source,
        status=status,
        payload_json=payload or {},
    )


def _normalize_local_phone_to_e164(raw_value, country_code):
    """Accept local digits (779697569) or E164 (+256779697569) from mobile clients."""
    text = str(raw_value or '').strip()
    if not text:
        return None

    if text.startswith('+'):
        try:
            parsed = phonenumbers.parse(text, None)
        except phonenumbers.NumberParseException:
            return None
        if not phonenumbers.is_valid_number(parsed):
            return None
        return phonenumbers.format_number(
            parsed,
            phonenumbers.PhoneNumberFormat.E164,
        )

    digits = ''.join(ch for ch in text if ch.isdigit())
    if not digits:
        return None
    region = str(country_code or 'UG').strip().upper()
    if not re.fullmatch(r'[A-Z]{2}', region):
        return None
    try:
        parsed = phonenumbers.parse(digits, region)
    except phonenumbers.NumberParseException:
        return None
    if not phonenumbers.is_valid_number(parsed):
        return None
    return phonenumbers.format_number(
        parsed,
        phonenumbers.PhoneNumberFormat.E164,
    )

@api_view(['GET'])
def health(_request):
    return Response({'status': 'ok'})

# --------------------------------------------------------------------------- #
# Email-based authentication
# --------------------------------------------------------------------------- #

from django.contrib.auth.hashers import make_password, check_password

@api_view(['POST'])
def send_email_code(request):
    """Send a verification code to the given email address."""
    email = (request.data.get('email') or '').strip().lower()
    password = request.data.get('password')
    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)

    # Check password if user already exists
    try:
        user = UserProfile.objects.get(uid=email)
        if user.password and password:
            if not check_password(password, user.password):
                return Response({'error': 'Invalid email or password'}, status=status.HTTP_400_BAD_REQUEST)
    except UserProfile.DoesNotExist:
        pass

    UserProfile.objects.get_or_create(uid=email, defaults={'email': email})

    code = generate_code()
    verification_id = create_verification_id('email')
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
def send_password_reset_code(request):
    """Send a password reset code to an existing email account."""
    email = (request.data.get('email') or '').strip().lower()
    if not email:
        return Response({'error': 'email is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = UserProfile.objects.get(uid=email)
    except UserProfile.DoesNotExist:
        return Response(
            {'error': 'No account found with this email'},
            status=status.HTTP_404_NOT_FOUND,
        )

    if not user.password:
        return Response(
            {
                'error': 'This account uses Google sign-in. Log in with Google instead.',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    code = generate_code()
    verification_id = create_verification_id('reset')
    store_code(verification_id, code, email)

    message, error_response = _send_auth_code_email(email, code, purpose='reset')
    if error_response is not None:
        return error_response

    return Response({'verificationId': verification_id, 'message': message})


@api_view(['POST'])
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
        user = UserProfile.objects.get(uid=email)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    user.password = make_password(str(new_password))
    user.save(update_fields=['password'])

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = UserProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})


@api_view(['POST'])
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

    uid = email
    
    defaults = {'email': email, 'onboarding_completed': False}
    if password:
        defaults['password'] = make_password(password)

    user, _created = UserProfile.objects.get_or_create(
        uid=uid,
        defaults=defaults,
    )
    
    # Make sure email and password are saved even for pre-existing profiles
    update_fields = []
    if not user.email:
        user.email = email
        update_fields.append('email')
        
    if password and not user.password:
        user.password = make_password(password)
        update_fields.append('password')
        
    if update_fields:
        user.save(update_fields=update_fields)

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = UserProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Social sign-in (Google / Apple)
# --------------------------------------------------------------------------- #

@api_view(['POST'])
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

    uid = email  # Use email as the unique identifier.

    user, _created = UserProfile.objects.get_or_create(
        uid=uid,
        defaults={'email': email, 'onboarding_completed': False},
    )

    token = 'token-' + uuid.uuid4().hex[:16]
    serializer = UserProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Legacy phone-based OTP (kept for backward compat)
# --------------------------------------------------------------------------- #

@api_view(['POST'])
def send_otp(request):
    phone_number = request.data.get('phoneNumber')
    if not phone_number:
        return Response({'error': 'phoneNumber is required'}, status=status.HTTP_400_BAD_REQUEST)

    code = generate_code()
    verification_id = create_verification_id('otp')
    store_code(verification_id, code, phone_number)
    UserProfile.objects.get_or_create(uid=phone_number, defaults={'phone_number': phone_number})

    if settings.DEBUG or settings.SAFECHECK_ALLOW_MOCK_AUTH:
        message = 'OTP sent (dev): 123456'
    else:
        sms_result = SmsProvider().send_sms(
            phone_number,
            f'Your SafeBangle verification code is {code}. It expires in 10 minutes.',
        )
        if not sms_result.get('success'):
            return Response(
                {'error': sms_result.get('error', 'Failed to send OTP')},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        message = 'OTP sent'

    return Response({'verificationId': verification_id, 'message': message})

@api_view(['POST'])
def verify_otp(request):
    verification_id = request.data.get('verificationId')
    phone_number = request.data.get('phoneNumber')
    sms_code = request.data.get('smsCode')

    if not verify_code(verification_id, sms_code):
        return Response({'error': 'Invalid OTP'}, status=status.HTTP_400_BAD_REQUEST)

    user, _created = UserProfile.objects.get_or_create(
        uid=phone_number,
        defaults={'phone_number': phone_number, 'onboarding_completed': False},
    )

    token = 'token-' + phone_number.replace('+', '')
    serializer = UserProfileSerializer(user)
    return Response({'token': token, 'user': serializer.data})

# --------------------------------------------------------------------------- #
# Profile & check-ins
# --------------------------------------------------------------------------- #

@api_view(['GET'])
def user_profile(request, uid):
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    serializer = UserProfileSerializer(user)
    return Response(serializer.data)

@api_view(['POST'])
def upsert_user_profile(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)

    user, _ = UserProfile.objects.get_or_create(uid=uid)
    alias_map = {
        'full_name': ['full_name', 'fullName'],
        'email': ['email'],
        'phone_number': ['phone_number', 'phoneNumber'],
        'onboarding_completed': ['onboarding_completed', 'onboardingCompleted'],
        'user_type': ['user_type', 'userType'],
        'checkin_frequency': ['checkin_frequency', 'checkinFrequency'],
        'grace_period_hours': ['grace_period_hours', 'gracePeriodHours'],
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

    if changed_fields:
        _log_timeline_event(
            user=user,
            event_type='profile_updated',
            source='app',
            status='success',
            payload={'fields': changed_fields},
        )
    return Response(UserProfileSerializer(user).data, status=status.HTTP_200_OK)


@api_view(['POST'])
def register_push_token(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    fcm_token = _first_present(request.data, ['fcm_token', 'fcmToken'])
    platform = _first_present(request.data, ['platform', 'fcm_platform', 'fcmPlatform'])

    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    if not fcm_token:
        return Response({'error': 'fcm_token is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
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
def checkins(request):
    uid = request.query_params.get('uid')
    checks = Checkin.objects.all().order_by('-timestamp')
    if uid:
        checks = checks.filter(user_id=uid)
    serializer = CheckinSerializer(checks, many=True)
    return Response(serializer.data)

@api_view(['POST'])
def confirm_safe_checkin(request):
    uid = request.data.get('uid') or request.data.get('user_id')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
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
def snooze_checkin(request):
    uid = request.data.get('uid') or request.data.get('user_id')
    snoozed_until_raw = request.data.get('snoozed_until') or request.data.get('snoozedUntil')
    if not uid or not snoozed_until_raw:
        return Response(
            {'error': 'uid and snoozed_until are required'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
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
def unregister_push_token(request):
    uid = _first_present(request.data, ['uid', 'userId', 'user_id'])
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
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
def create_checkin(request):
    user_uid = request.data.get('user_id')
    status_field = request.data.get('status', 'ok')

    try:
        user = UserProfile.objects.get(uid=user_uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    if status_field == 'safe_confirmed':
        mark_user_safe(user, text='app_checkin')
        checkin = Checkin.objects.filter(user=user).order_by('-timestamp').first()
    else:
        checkin = Checkin.objects.create(user=user, status=status_field)

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
def call_attempts(request, uid):
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    attempts = user.call_attempts.all().order_by('-created_at')
    return Response(CallAttemptSerializer(attempts, many=True).data)


@api_view(['GET'])
def alerts(request, uid):
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    entries = AlertEvent.objects.filter(user=user).order_by('-created_at')
    return Response(AlertEventSerializer(entries, many=True).data)


@api_view(['POST'])
def update_location(request):
    uid = request.data.get('uid')
    latitude = request.data.get('latitude')
    longitude = request.data.get('longitude')
    if not uid or latitude is None or longitude is None:
        return Response({'error': 'uid, latitude, longitude are required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    snapshot = LocationSnapshot.objects.create(
        user=user,
        latitude=float(latitude),
        longitude=float(longitude),
        accuracy_meters=request.data.get('accuracy_meters'),
        address=request.data.get('address'),
    )
    return Response(LocationSnapshotSerializer(snapshot).data, status=status.HTTP_201_CREATED)


@api_view(['POST'])
def trigger_checkin_call(request):
    uid = request.data.get('uid')
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    last_attempt = user.call_attempts.order_by('-attempt_number').first()
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
        user=user,
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
def escalate_missed_checkin(request):
    uid = request.data.get('uid')
    reason = (request.data.get('reason') or 'missed_or_declined').strip()
    if not uid:
        return Response({'error': 'uid is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
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
    completed_attempts = CallAttempt.objects.filter(user=user).count()
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
        user=user,
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


@api_view(['GET', 'POST'])
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
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    event = UserTimelineEvent.objects.create(
        user=user,
        event_type=event_type,
        source=request.data.get('source') or 'app',
        status=request.data.get('status') or 'info',
        payload_json=request.data.get('payload_json') or {},
    )
    return Response(UserTimelineEventSerializer(event).data, status=status.HTTP_201_CREATED)


# --------------------------------------------------------------------------- #
# Compatibility endpoints (avoid 404s from legacy frontend routes)
# --------------------------------------------------------------------------- #

@api_view(['GET'])
def alerts_collection(request):
    uid = request.query_params.get('uid')
    entries = AlertEvent.objects.all().order_by('-created_at')
    if uid:
        entries = entries.filter(user_id=uid)
    return Response(AlertEventSerializer(entries, many=True).data)


@api_view(['GET'])
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
def checkpoints_collection(_request):
    # Placeholder structure for clients expecting checkpoint resources.
    return Response([])


@api_view(['GET'])
def guards_collection(_request):
    # Placeholder structure for clients expecting guards resources.
    return Response([])


@api_view(['GET', 'POST'])
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
        user = UserProfile.objects.get(uid=uid)
    except UserProfile.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    snapshot = LocationSnapshot.objects.create(
        user=user,
        latitude=float(latitude),
        longitude=float(longitude),
        accuracy_meters=request.data.get('accuracy_meters'),
        address=request.data.get('address'),
    )
    return Response(LocationSnapshotSerializer(snapshot).data, status=status.HTTP_201_CREATED)
