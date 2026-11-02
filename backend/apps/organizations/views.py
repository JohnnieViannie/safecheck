from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.response import Response

from apps.accounts.access import send_access_sms
from apps.accounts.backends import find_user
from apps.accounts.phone import normalize_phone
from apps.audit.services import AuditService
from apps.notifications.sms_text import sms_name
from apps.organizations.permissions import ADMIN_ROLES, IsPlatformAdmin, get_membership, user_org_ids
from apps.safety.services.sms_provider import SmsProvider

from .models import Invitation, MembershipRole, Organization, OrganizationMembership
from .serializers import (
    InvitationAcceptSerializer,
    InvitationCreateSerializer,
    InvitationSerializer,
    MembershipSerializer,
    OrganizationCreateSerializer,
    OrganizationOnboardSerializer,
    OrganizationSerializer,
)
from .services import OrganizationService

User = get_user_model()


class OrganizationViewSet(viewsets.ModelViewSet):
    serializer_class = OrganizationSerializer
    search_fields = ["name", "slug", "email"]
    ordering_fields = ["name", "created_at"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return Organization.objects.all()
        # Registrars pick an organization when registering someone, and can't do more with it.
        if user.is_registrar and self.action in ("list", "retrieve"):
            return Organization.objects.all()
        return Organization.objects.filter(id__in=user_org_ids(user))

    def create(self, request, *args, **kwargs):
        if not request.user.is_platform_admin:
            return Response({"error": "Only platform admins can add organizations."}, status=403)
        ser = OrganizationCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        org = OrganizationService.create_organization(owner=request.user, **ser.validated_data)
        AuditService.log(
            actor=request.user,
            action="organization.created",
            object_type="Organization",
            object_id=str(org.id),
            metadata={"name": org.name},
            request=request,
        )
        return Response(OrganizationSerializer(org).data, status=201)

    @action(
        detail=False,
        methods=["post"],
        permission_classes=[permissions.IsAuthenticated, IsPlatformAdmin],
    )
    def onboard(self, request):
        ser = OrganizationOnboardSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        data = ser.validated_data
        org, owner, created_owner = OrganizationService.onboard(
            name=data["name"],
            description=data["description"],
            email=data["email"],
            phone=data["phone"],
            address=data["address"],
            existing_owner=data["existing_owner"],
            owner_fields={
                "first_name": data["owner_first_name"],
                "last_name": data["owner_last_name"],
                "phone": data["owner_phone"],
                "email": data["owner_email"],
                "country_code": data["country_code"],
                "registered_by": request.user,
            },
        )
        AuditService.log(
            actor=request.user,
            action="organization.onboarded",
            object_type="Organization",
            object_id=str(org.id),
            organization=org,
            metadata={"name": org.name, "owner": str(owner.id), "new_owner": created_owner},
            request=request,
        )
        sms_sent, sms_error = OrganizationService.notify_owner(org, owner)
        return Response(
            {
                "organization": OrganizationSerializer(org).data,
                "owner": {
                    "id": str(owner.id),
                    "full_name": owner.full_name,
                    "phone": owner.phone,
                    "email": owner.email,
                    "is_new": created_owner,
                },
                "sms_sent": sms_sent,
                "sms_error": sms_error,
            },
            status=201,
        )

    def perform_update(self, serializer):
        org = self.get_object()
        if not self.request.user.is_platform_admin:
            m = get_membership(self.request.user, org.id)
            if not m or m.role not in ADMIN_ROLES:
                from rest_framework.exceptions import PermissionDenied

                raise PermissionDenied("Admin role required.")
        serializer.save()
        AuditService.log(
            actor=self.request.user,
            action="organization.updated",
            object_type="Organization",
            object_id=str(org.id),
            request=self.request,
        )

    def destroy(self, request, *args, **kwargs):
        if not request.user.is_platform_admin:
            return Response({"error": "Only platform admins can delete organizations."}, status=403)
        org = self.get_object()
        org_id = str(org.id)
        name = org.name
        response = super().destroy(request, *args, **kwargs)
        AuditService.log(
            actor=request.user,
            action="organization.deleted",
            object_type="Organization",
            object_id=org_id,
            metadata={"name": name},
            request=request,
        )
        return response

    @action(detail=True, methods=["post"])
    def deactivate(self, request, pk=None):
        if not request.user.is_platform_admin:
            return Response({"error": "Only platform admins can deactivate organizations."}, status=403)
        org = self.get_object()
        org.is_active = False
        org.save(update_fields=["is_active", "updated_at"])
        AuditService.log(
            actor=request.user,
            action="organization.deactivated",
            object_type="Organization",
            object_id=str(org.id),
            organization=org,
            request=request,
        )
        return Response(OrganizationSerializer(org).data)

    @action(detail=True, methods=["post"])
    def activate(self, request, pk=None):
        if not request.user.is_platform_admin:
            return Response({"error": "Only platform admins can activate organizations."}, status=403)
        org = self.get_object()
        org.is_active = True
        org.save(update_fields=["is_active", "updated_at"])
        AuditService.log(
            actor=request.user,
            action="organization.activated",
            object_type="Organization",
            object_id=str(org.id),
            organization=org,
            request=request,
        )
        return Response(OrganizationSerializer(org).data)

    @action(detail=True, methods=["get", "post"])
    def members(self, request, pk=None):
        org = self.get_object()
        if request.method == "GET":
            qs = org.memberships.select_related("user").filter(is_active=True)
            return Response(MembershipSerializer(qs, many=True).data)
        if not request.user.is_platform_admin:
            m = get_membership(request.user, org.id)
            if not m or m.role not in ADMIN_ROLES:
                return Response({"error": "Forbidden"}, status=403)
        role = request.data.get("role", MembershipRole.STAFF)
        if role not in MembershipRole.values:
            return Response({"error": "Invalid role."}, status=400)
        identifier = (
            request.data.get("identifier") or request.data.get("phone") or request.data.get("email")
        )
        if not identifier:
            return Response({"error": "Enter a phone number or email."}, status=400)
        user = find_user(identifier, request.data.get("country_code"))
        if not user:
            return Response({"error": "User not found. Invite them instead."}, status=404)
        membership, created = OrganizationMembership.objects.update_or_create(
            organization=org,
            user=user,
            defaults={"role": role, "is_active": True},
        )
        AuditService.log(
            actor=request.user,
            action="membership.created" if created else "membership.updated",
            object_type="OrganizationMembership",
            object_id=str(membership.id),
            organization=org,
            request=request,
        )
        return Response(MembershipSerializer(membership).data, status=201 if created else 200)

    @action(
        detail=True,
        methods=["patch", "delete"],
        url_path=r"members/(?P<membership_id>[^/.]+)",
    )
    def member_detail(self, request, pk=None, membership_id=None):
        """Change a staff member's role, or remove them from this organization."""
        org = self.get_object()
        if not request.user.is_platform_admin:
            m = get_membership(request.user, org.id)
            if not m or m.role not in ADMIN_ROLES:
                return Response({"error": "Forbidden"}, status=403)
        try:
            membership = org.memberships.select_related("user").get(pk=membership_id)
        except (OrganizationMembership.DoesNotExist, ValueError, DjangoValidationError):
            return Response({"error": "Staff member not found."}, status=404)

        is_last_owner = (
            membership.role == MembershipRole.OWNER
            and org.memberships.filter(role=MembershipRole.OWNER, is_active=True).count() == 1
        )
        if request.method == "DELETE":
            if is_last_owner:
                return Response({"error": "An organization needs at least one owner."}, status=400)
            membership_ref = str(membership.id)
            membership.delete()
            action_name = "membership.removed"
            response = Response(status=204)
        else:
            role = request.data.get("role")
            if role not in MembershipRole.values:
                return Response({"error": "Invalid role."}, status=400)
            if is_last_owner and role != MembershipRole.OWNER:
                return Response({"error": "An organization needs at least one owner."}, status=400)
            membership.role = role
            membership.save(update_fields=["role", "updated_at"])
            membership_ref = str(membership.id)
            action_name = "membership.updated"
            response = Response(MembershipSerializer(membership).data)
        AuditService.log(
            actor=request.user,
            action=action_name,
            object_type="OrganizationMembership",
            object_id=membership_ref,
            organization=org,
            request=request,
        )
        return response

    def _create_staff_account(self, request, org, data):
        with transaction.atomic():
            user = User.objects.create_user(
                email=data["email"].lower() or None,
                phone=data["phone"] or None,
                password=None,
                first_name=data["first_name"],
                last_name=data["last_name"],
                country_code=data["country_code"].upper(),
                account_type="organization",
                registered_by=request.user,
            )
            membership = OrganizationMembership.objects.create(
                organization=org, user=user, role=data["role"]
            )
        intro = f"You've joined {sms_name(org.name)} on SafeBangle as {membership.get_role_display()}."
        if user.phone:
            send_access_sms(user, intro)
        else:
            send_mail(
                subject=f"You've been added to {org.name} on SafeBangle",
                message=(
                    f"{intro} Your username is {user.username}. "
                    f"Set your password: {settings.FRONTEND_URL}/forgot-password"
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[user.email],
                fail_silently=True,
            )
        AuditService.log(
            actor=request.user,
            action="membership.created",
            object_type="OrganizationMembership",
            object_id=str(membership.id),
            organization=org,
            request=request,
        )
        return Response(
            {"joined": True, "membership": MembershipSerializer(membership).data}, status=201
        )

    @action(detail=True, methods=["get", "post"])
    def invitations(self, request, pk=None):
        org = self.get_object()
        if not request.user.is_platform_admin:
            m = get_membership(request.user, org.id)
            if not m or m.role not in ADMIN_ROLES:
                return Response({"error": "Forbidden"}, status=403)
        if request.method == "GET":
            qs = org.invitations.all()[:50]
            return Response(InvitationSerializer(qs, many=True).data)
        ser = InvitationCreateSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        # Sign-up is closed, so someone new gets their account and staff place straight away.
        if not _existing_account(ser.validated_data):
            return self._create_staff_account(request, org, ser.validated_data)
        inv = Invitation.create_invitation(
            organization=org,
            phone=ser.validated_data["phone"],
            email=ser.validated_data["email"],
            role=ser.validated_data["role"],
            invited_by=request.user,
        )
        link = f"{settings.FRONTEND_URL}/accept-invite?token={inv.token}"
        message = f"Join {sms_name(org.name)} on SafeBangle: {link}"
        if inv.phone:
            SmsProvider().send_sms(inv.phone, message, purpose="invite")
        if inv.email:
            send_mail(
                subject=f"Invitation to join {org.name} on SafeBangle",
                message=message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[inv.email],
                fail_silently=True,
            )
        AuditService.log(
            actor=request.user,
            action="invitation.created",
            object_type="Invitation",
            object_id=str(inv.id),
            organization=org,
            metadata={"email": inv.email, "phone": inv.phone, "role": inv.role},
            request=request,
        )
        return Response(InvitationSerializer(inv).data, status=201)


def _existing_account(data):
    account = None
    if data["phone"]:
        account = User.objects.filter(phone=data["phone"]).first()
    if account is None and data["email"]:
        account = User.objects.filter(email__iexact=data["email"]).first()
    return account


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def accept_invitation(request):
    ser = InvitationAcceptSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    try:
        inv = Invitation.objects.select_related("organization").get(
            token=ser.validated_data["token"]
        )
    except Invitation.DoesNotExist:
        return Response({"error": "Invalid invitation."}, status=400)
    if not inv.is_valid:
        return Response({"error": "Invitation expired or already used."}, status=400)
    account_email = (request.user.email or "").lower()
    email_matches = bool(inv.email) and account_email == inv.email.lower()
    phone_matches = bool(inv.phone) and normalize_phone(request.user.phone) == inv.phone
    if not email_matches and not phone_matches:
        return Response(
            {"error": "This invitation was sent to a different phone number or email."},
            status=403,
        )
    membership, _ = OrganizationMembership.objects.update_or_create(
        organization=inv.organization,
        user=request.user,
        defaults={"role": inv.role, "is_active": True},
    )
    inv.accepted_at = timezone.now()
    inv.save(update_fields=["accepted_at"])
    AuditService.log(
        actor=request.user,
        action="invitation.accepted",
        object_type="Invitation",
        object_id=str(inv.id),
        organization=inv.organization,
        request=request,
    )
    return Response(
        {
            "membership": MembershipSerializer(membership).data,
            "organization": OrganizationSerializer(inv.organization).data,
        }
    )


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def revoke_invitation(request, invitation_id):
    try:
        inv = Invitation.objects.select_related("organization").get(id=invitation_id)
    except Invitation.DoesNotExist:
        return Response({"error": "Not found"}, status=404)
    if not request.user.is_platform_admin:
        m = get_membership(request.user, inv.organization_id)
        if not m or m.role not in ADMIN_ROLES:
            return Response({"error": "Forbidden"}, status=403)
    inv.revoked_at = timezone.now()
    inv.save(update_fields=["revoked_at"])
    return Response({"message": "Invitation revoked."})
