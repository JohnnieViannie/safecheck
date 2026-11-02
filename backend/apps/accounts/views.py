import secrets
from datetime import timedelta

from django.contrib.auth import authenticate, get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework_simplejwt.tokens import RefreshToken

from apps.audit.services import AuditService
from apps.devices.services import BraceletAssignmentService, person_for_user, sync_people_from_user
from apps.notifications.birthdays import celebrated_on, days_until_birthday

from .access import send_access_sms
from .backends import find_user
from .codes import can_send_code, consume_code, send_code_email, send_code_sms, send_verification_code
from .geo import dial_codes_payload, dial_for_iso
from .models import EmailVerificationToken, PasswordResetToken, PhoneVerificationToken, PlatformRole
from .phone import is_email_identifier, is_username_identifier
from .photos import remove_user_photo, save_user_photo
from .serializers import (
    AdminUserCreateSerializer,
    AdminUserUpdateSerializer,
    ChangePasswordSerializer,
    LoginSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    ProfileUpdateSerializer,
    ResendCodeSerializer,
    StaffInviteSerializer,
    StaffSerializer,
    UserDetailSerializer,
    UserSerializer,
    VerifyCodeSerializer,
)
from apps.organizations.permissions import IsPlatformAdmin, IsPlatformStaff
from apps.people.models import Person
from django.db.models import Count, Exists, OuterRef, Q, Subquery
from django.db.models.functions import Coalesce
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated

User = get_user_model()


class AuthThrottle(AnonRateThrottle):
    scope = "auth"


def tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def _channel_for(identifier, user=None) -> str:
    """Where a code goes: the channel named, or for a username, the account's phone first."""
    if is_email_identifier(identifier):
        return "email"
    if is_username_identifier(identifier) and user is not None and not user.phone:
        return "email"
    return "sms"


def _client_ip(request) -> str:
    xff = request.META.get("HTTP_X_FORWARDED_FOR")
    if xff:
        return xff.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR") or ""


@api_view(["GET"])
@permission_classes([permissions.AllowAny])
def detect_country(request):
    """Detect visitor country for phone dial-code autofill."""
    import logging

    import requests as http

    from .geo import COUNTRY_DIAL_CODES

    logger = logging.getLogger(__name__)
    iso = (
        request.headers.get("CF-IPCountry")
        or request.META.get("HTTP_CF_IPCOUNTRY")
        or request.headers.get("X-Country-Code")
        or ""
    ).upper()
    if iso in {"", "XX", "T1"}:
        iso = ""

    ip = _client_ip(request)
    if not iso and ip and ip not in {"127.0.0.1", "::1"}:
        try:
            resp = http.get(f"http://ip-api.com/json/{ip}?fields=status,countryCode", timeout=3)
            payload = resp.json()
            if payload.get("status") == "success":
                iso = (payload.get("countryCode") or "").upper()
        except Exception:
            logger.info("Geo lookup failed for %s", ip)

    if not iso:
        iso = "KE"  # default for SafeBangle primary market

    dial = dial_for_iso(iso) or "+254"
    name = next((n for c, n, _d in COUNTRY_DIAL_CODES if c == iso), iso)
    return Response(
        {
            "country_code": iso,
            "country_name": name,
            "dial_code": dial,
            "dial_codes": dial_codes_payload(),
        }
    )


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def register(request):
    return Response(
        {"error": "Accounts are created by SafeBangle staff. Please contact us to register."},
        status=status.HTTP_403_FORBIDDEN,
    )


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def login(request):
    ser = LoginSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    user = authenticate(
        request,
        username=ser.validated_data["identifier"],
        password=ser.validated_data["password"],
        country_code=ser.validated_data.get("country_code"),
    )
    if not user:
        return Response({"error": "Invalid login details."}, status=401)
    if not user.is_active:
        return Response({"error": "Account is disabled."}, status=403)
    if not (user.phone_verified or user.email_verified or user.is_platform_admin):
        channel = "sms" if user.phone else "email"
        identifier = user.phone if channel == "sms" else user.email
        pending = {
            "requires_verification": True,
            "identifier": identifier,
            "phone": user.phone,
            "email": user.email,
            "channel": channel,
        }
        model = PhoneVerificationToken if channel == "sms" else EmailVerificationToken
        if not can_send_code(model, user):
            return Response(
                {"error": "Account not verified. Use the code we already sent you.", **pending},
                status=403,
            )
        try:
            send_verification_code(user, channel)
        except RuntimeError as exc:
            return Response({"error": str(exc), **pending}, status=503)
        return Response(
            {
                "error": "Account not verified. We sent you a new code.",
                "code_resent": True,
                **pending,
            },
            status=403,
        )
    AuditService.log(
        actor=user,
        action="user.login",
        object_type="User",
        object_id=str(user.id),
        request=request,
    )
    return Response({"user": UserSerializer(user, context={"request": request}).data, "tokens": tokens_for_user(user)})


@api_view(["GET", "PATCH"])
@permission_classes([permissions.IsAuthenticated])
def me(request):
    if request.method == "GET":
        return Response(UserSerializer(request.user, context={"request": request}).data)
    ser = ProfileUpdateSerializer(request.user, data=request.data, partial=True)
    ser.is_valid(raise_exception=True)
    ser.save()
    sync_people_from_user(request.user)
    return Response(UserSerializer(request.user, context={"request": request}).data)


@api_view(["POST", "DELETE"])
@permission_classes([permissions.IsAuthenticated])
def my_photo(request):
    if request.method == "DELETE":
        remove_user_photo(request.user)
    else:
        save_user_photo(request.user, request.FILES.get("photo"))
    return Response(UserSerializer(request.user, context={"request": request}).data)


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def verify_code(request):
    """Confirm a phone number or email with the code sent to it."""
    ser = VerifyCodeSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    identifier = ser.validated_data["identifier"]
    user = find_user(identifier, ser.validated_data.get("country_code"))
    channel = _channel_for(identifier, user)
    model = PhoneVerificationToken if channel == "sms" else EmailVerificationToken
    if not user or not consume_code(model, user, ser.validated_data["code"]):
        return Response({"error": "Invalid or expired verification code."}, status=400)

    field = "phone_verified" if channel == "sms" else "email_verified"
    setattr(user, field, True)
    user.save(update_fields=[field])
    AuditService.log(
        actor=user,
        action=f"user.{field}",
        object_type="User",
        object_id=str(user.id),
        request=request,
    )
    return Response(
        {
            "message": "Verified. You can sign in now.",
            "user": UserSerializer(user, context={"request": request}).data,
            "tokens": tokens_for_user(user),
        }
    )


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def resend_verification(request):
    ser = ResendCodeSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    identifier = ser.validated_data["identifier"]
    message = "If that account exists, a new code was sent."
    user = find_user(identifier, ser.validated_data.get("country_code"))
    if not user:
        return Response({"message": message})
    channel = _channel_for(identifier, user)
    if user.phone_verified if channel == "sms" else user.email_verified:
        return Response({"message": "Already verified. You can sign in."})
    model = PhoneVerificationToken if channel == "sms" else EmailVerificationToken
    if can_send_code(model, user):
        try:
            send_verification_code(user, channel)
        except RuntimeError as exc:
            return Response({"error": str(exc)}, status=503)
    return Response({"message": message})


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def forgot_password(request):
    ser = PasswordResetRequestSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    identifier = ser.validated_data["identifier"]
    # Same response whether or not the account exists, so this can't be used to look people up.
    payload = {
        "message": "If that account exists, a code was sent.",
        "identifier": identifier,
        "verificationId": f"reset-{secrets.token_hex(6)}",
    }
    if is_email_identifier(identifier):
        payload["email"] = identifier.lower()
    user = find_user(identifier, ser.validated_data.get("country_code"))
    if not user or not can_send_code(PasswordResetToken, user):
        return Response(payload)
    token = PasswordResetToken.create_for_user(user)
    try:
        if _channel_for(identifier, user) == "sms":
            send_code_sms(phone=user.phone, code=token.token, purpose="password reset", user=user)
        else:
            send_code_email(email=user.email, code=token.token, purpose="password reset")
    except RuntimeError as exc:
        return Response({"error": str(exc)}, status=503)
    return Response(payload)


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
@throttle_classes([AuthThrottle])
def reset_password(request):
    ser = PasswordResetConfirmSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    identifier = ser.validated_data["identifier"]
    user = find_user(identifier, ser.validated_data.get("country_code"))
    if not user or not consume_code(PasswordResetToken, user, ser.validated_data["code"]):
        return Response({"error": "Invalid or expired reset code."}, status=400)

    user.set_password(ser.validated_data["password"])
    # The code reached this phone or inbox, which proves the person controls it.
    if _channel_for(identifier, user) == "sms":
        user.phone_verified = True
    else:
        user.email_verified = True
    user.save()
    AuditService.log(
        actor=user,
        action="user.password_reset",
        object_type="User",
        object_id=str(user.id),
        request=request,
    )

    # Mobile clients expect opaque token + safety profile payload.
    wants_mobile = "newPassword" in request.data or "verificationId" in request.data
    if wants_mobile:
        import uuid

        from apps.mobile_compat.identity import get_or_create_profile
        from apps.mobile_compat.serializers import SafetyProfileSerializer

        profile, _ = get_or_create_profile(
            user.email or user.phone, email=user.email, phone=user.phone
        )
        return Response(
            {
                "token": "token-" + uuid.uuid4().hex[:16],
                "user": SafetyProfileSerializer(profile).data,
                "message": "Password updated. You can sign in now.",
            }
        )
    return Response({"message": "Password updated. You can sign in now."})


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def change_password(request):
    ser = ChangePasswordSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    user = request.user
    if not user.check_password(ser.validated_data["current_password"]):
        return Response({"error": "Current password is incorrect."}, status=400)
    user.set_password(ser.validated_data["new_password"])
    user.save()
    AuditService.log(
        actor=user,
        action="user.password_changed",
        object_type="User",
        object_id=str(user.id),
        request=request,
    )
    return Response({"message": "Password updated."})


class UserViewSet(viewsets.ModelViewSet):
    """Platform user management — list/edit/mute/block/delete accounts."""

    search_fields = [
        "username",
        "email",
        "first_name",
        "last_name",
        "phone",
        "city",
        "person_profiles__current_bracelets__device_id",
    ]
    filterset_fields = ["account_type", "is_active", "is_muted", "email_verified", "is_platform_admin"]
    ordering_fields = ["created_at", "email", "first_name"]
    http_method_names = ["get", "patch", "delete", "post", "head", "options"]

    def get_permissions(self):
        if self.action in ("destroy", "mute", "unmute", "block", "unblock", "upcoming_birthdays"):
            return [IsAuthenticated(), IsPlatformAdmin()]
        return [IsAuthenticated(), IsPlatformStaff()]

    def get_serializer_class(self):
        if self.action in ("partial_update", "update"):
            return AdminUserUpdateSerializer
        if self.action == "retrieve":
            return UserDetailSerializer
        return UserSerializer

    def get_queryset(self):
        user = self.request.user
        qs = User.objects.all()
        if not user.is_platform_admin:
            # Registrars manage the people they registered.
            qs = qs.filter(registered_by=user)

        from apps.devices.models import Bracelet
        from apps.safety.models import SafetyProfile

        qs = qs.annotate(
            _bracelet_count=Count("bracelets", distinct=True),
            _owned_people=Count("owned_people", distinct=True),
            _linked_people=Count("person_profiles", distinct=True),
            _has_app_profile=Exists(
                SafetyProfile.objects.filter(user_id=OuterRef("pk"))
            ),
            _person_organization=Subquery(
                Person.objects.filter(
                    linked_user=OuterRef("pk"), organization__isnull=False
                ).values("organization__name")[:1]
            ),
            _device_id=Coalesce(
                Subquery(
                    Bracelet.objects.filter(current_person__linked_user=OuterRef("pk")).values(
                        "device_id"
                    )[:1]
                ),
                Subquery(
                    Bracelet.objects.filter(current_person__owner_user=OuterRef("pk")).values(
                        "device_id"
                    )[:1]
                ),
            ),
        )

        source = (self.request.query_params.get("source") or "").strip().lower()
        if source == "app":
            qs = qs.filter(_has_app_profile=True)
        elif source == "watch":
            qs = qs.filter(_bracelet_count__gt=0)
        elif source == "org":
            qs = qs.filter(
                Q(account_type="organization")
                | Q(memberships__is_active=True)
                | Q(person_profiles__organization__isnull=False)
            ).distinct()
        elif source == "independent":
            qs = qs.exclude(memberships__is_active=True).exclude(
                person_profiles__organization__isnull=False
            )

        status_filter = (self.request.query_params.get("status") or "").strip().lower()
        if status_filter == "active":
            qs = qs.filter(is_active=True, is_muted=False)
        elif status_filter == "muted":
            qs = qs.filter(is_muted=True, is_active=True)
        elif status_filter == "blocked":
            qs = qs.filter(is_active=False)

        organization = (self.request.query_params.get("organization") or "").strip()
        if organization:
            qs = qs.filter(
                Q(memberships__organization_id=organization, memberships__is_active=True)
                | Q(person_profiles__organization_id=organization)
            ).distinct()

        return qs.order_by("-created_at")

    def create(self, request, *args, **kwargs):
        ser = AdminUserCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        data = ser.validated_data
        org = data["organization"]
        with transaction.atomic():
            user = User.objects.create_user(
                email=data["email"],
                password=None,
                phone=data["phone"],
                country_code=data["country_code"],
                first_name=data["first_name"],
                last_name=data["last_name"],
                city=data["city"].strip(),
                date_of_birth=data["date_of_birth"],
                address=data["address"].strip(),
                registered_by=request.user,
            )
            person = Person.objects.create(
                organization=org,
                owner_user=None if org else user,
                linked_user=user,
                first_name=user.first_name,
                last_name=user.last_name,
                email=user.email or "",
                phone=user.phone,
            )
            bracelet = BraceletAssignmentService.issue(
                person, data["device_id"], assigned_by=request.user
            )
            AuditService.log(
                actor=request.user,
                action="user.created",
                object_type="User",
                object_id=str(user.id),
                organization=org,
                metadata={
                    "organization": str(org.id) if org else None,
                    "device_id": bracelet.device_id,
                },
                request=request,
            )
        sms_sent, sms_error = send_access_sms(user, "Welcome to SafeBangle.")
        return Response(
            {
                **UserSerializer(user, context={"request": request}).data,
                "sms_sent": sms_sent,
                "sms_error": sms_error,
            },
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=["get"], url_path="upcoming-birthdays")
    def upcoming_birthdays(self, request):
        today = timezone.localdate()
        upcoming = []
        people = User.objects.filter(is_active=True, date_of_birth__isnull=False)
        for person in people:
            days = days_until_birthday(person.date_of_birth, today)
            if days <= 7:
                when = celebrated_on(person.date_of_birth, (today + timedelta(days=days)).year)
                upcoming.append(
                    {
                        "id": str(person.id),
                        "full_name": person.full_name,
                        "photo_url": UserSerializer(person, context={"request": request}).get_photo_url(person),
                        "days_away": days,
                        "date": when.isoformat(),
                    }
                )
        return Response(sorted(upcoming, key=lambda item: item["days_away"]))

    @action(detail=True, methods=["post"], url_path="replace-device")
    def replace_device(self, request, pk=None):
        user = self.get_object()
        device_id = (request.data.get("device_id") or "").strip()
        if not device_id:
            raise ValidationError({"device_id": "Enter the new device ID."})
        old_state = request.data.get("old_device_state", "spare")
        if old_state not in ("broken", "spare"):
            raise ValidationError({"old_device_state": "Choose broken or spare."})
        reason = (request.data.get("reason") or "").strip()[:255]
        with transaction.atomic():
            person = person_for_user(user) or Person.objects.create(
                owner_user=user,
                linked_user=user,
                first_name=user.first_name or user.username,
                last_name=user.last_name,
                email=user.email or "",
                phone=user.phone or "",
            )
            new, old = BraceletAssignmentService.replace(
                person,
                device_id,
                assigned_by=request.user,
                reason=reason,
                old_device_state=old_state,
            )
            AuditService.log(
                actor=request.user,
                action="user.device_replaced",
                object_type="User",
                object_id=str(user.id),
                organization=person.organization,
                metadata={
                    "new_device": new.device_id,
                    "old_device": old.device_id if old else None,
                    "old_device_state": old_state if old else None,
                },
                request=request,
            )
        return Response(UserDetailSerializer(user, context={"request": request}).data)

    @action(detail=True, methods=["post", "delete"])
    def photo(self, request, pk=None):
        user = self.get_object()
        if request.method == "DELETE":
            remove_user_photo(user)
        else:
            save_user_photo(user, request.FILES.get("photo"))
        return Response(UserDetailSerializer(user, context={"request": request}).data)

    def perform_update(self, serializer):
        if not self.request.user.is_platform_admin and (
            {"is_active", "is_muted"} & set(serializer.validated_data)
        ):
            raise PermissionDenied("Only super admins can block or mute users.")
        user = serializer.save()
        sync_people_from_user(user)
        AuditService.log(
            actor=self.request.user,
            action="user.updated",
            object_type="User",
            object_id=str(user.id),
            metadata={"fields": list(serializer.validated_data.keys())},
        )

    def perform_destroy(self, instance):
        if instance.id == self.request.user.id:
            raise ValidationError("You cannot delete your own account.")
        if instance.is_platform_admin:
            raise ValidationError("Cannot delete another platform admin from this screen.")
        user_id = str(instance.id)
        email = instance.email or instance.phone
        with transaction.atomic():
            # Devices go back to spare stock. Alerts keep their records, without the person link.
            BraceletAssignmentService.release_for_user(instance)
            Person.objects.filter(linked_user=instance).delete()
            remove_user_photo(instance)
            instance.delete()
        AuditService.log(
            actor=self.request.user,
            action="user.deleted",
            object_type="User",
            object_id=user_id,
            metadata={"email": email},
        )

    def _set_flag(self, *, muted=None, active=None, action_name: str):
        user = self.get_object()
        if user.id == self.request.user.id and active is False:
            return Response({"error": "You cannot block your own account."}, status=400)
        update_fields = []
        if muted is not None:
            user.is_muted = muted
            update_fields.append("is_muted")
        if active is not None:
            user.is_active = active
            update_fields.append("is_active")
        if update_fields:
            user.save(update_fields=update_fields + ["updated_at"])
        AuditService.log(
            actor=self.request.user,
            action=action_name,
            object_type="User",
            object_id=str(user.id),
            metadata={"is_muted": user.is_muted, "is_active": user.is_active},
        )
        return Response(UserSerializer(user, context={"request": self.request}).data)

    @action(detail=True, methods=["post"])
    def mute(self, request, pk=None):
        return self._set_flag(muted=True, action_name="user.muted")

    @action(detail=True, methods=["post"])
    def unmute(self, request, pk=None):
        return self._set_flag(muted=False, action_name="user.unmuted")

    @action(detail=True, methods=["post"])
    def block(self, request, pk=None):
        return self._set_flag(active=False, action_name="user.blocked")

    @action(detail=True, methods=["post"])
    def unblock(self, request, pk=None):
        return self._set_flag(active=True, action_name="user.unblocked")


class StaffViewSet(viewsets.ViewSet):
    """Super admins invite and manage platform staff such as registrars."""

    permission_classes = [IsAuthenticated, IsPlatformAdmin]

    def _staff(self, pk):
        try:
            return User.objects.get(pk=pk, platform_role=PlatformRole.REGISTRAR)
        except (User.DoesNotExist, ValueError, DjangoValidationError) as exc:
            raise NotFound("Staff member not found.") from exc

    def list(self, request):
        staff = User.objects.filter(platform_role=PlatformRole.REGISTRAR).order_by("-created_at")
        return Response(StaffSerializer(staff, many=True).data)

    @action(detail=False, methods=["post"])
    def invite(self, request):
        ser = StaffInviteSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        data = ser.validated_data
        user = data["existing"]
        if user:
            user.platform_role = PlatformRole.REGISTRAR
            user.save(update_fields=["platform_role"])
        else:
            user = User.objects.create_user(
                email=data["email"],
                password=None,
                phone=data["phone"],
                country_code=data["country_code"],
                first_name=data["first_name"],
                last_name=data["last_name"],
                platform_role=PlatformRole.REGISTRAR,
                registered_by=request.user,
            )
        AuditService.log(
            actor=request.user,
            action="staff.invited",
            object_type="User",
            object_id=str(user.id),
            metadata={"role": user.platform_role},
            request=request,
        )
        sms_sent, sms_error = send_access_sms(
            user, "You've been invited to SafeBangle as a registrar."
        )
        return Response(
            {**StaffSerializer(user).data, "sms_sent": sms_sent, "sms_error": sms_error},
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["post"])
    def resend(self, request, pk=None):
        user = self._staff(pk)
        sms_sent, sms_error = send_access_sms(
            user, "You've been invited to SafeBangle as a registrar."
        )
        return Response({"sms_sent": sms_sent, "sms_error": sms_error})

    @action(detail=True, methods=["post"], url_path="remove-role")
    def remove_role(self, request, pk=None):
        user = self._staff(pk)
        user.platform_role = ""
        user.save(update_fields=["platform_role"])
        AuditService.log(
            actor=request.user,
            action="staff.role_removed",
            object_type="User",
            object_id=str(user.id),
            request=request,
        )
        return Response({"message": "Role removed."})
