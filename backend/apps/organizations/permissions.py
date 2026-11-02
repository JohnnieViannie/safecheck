from rest_framework.permissions import BasePermission, SAFE_METHODS

from apps.organizations.models import MembershipRole, OrganizationMembership

ADMIN_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN}
MANAGE_ROLES = {MembershipRole.OWNER, MembershipRole.ADMIN, MembershipRole.STAFF}
RESPONDER_ROLES = {
    MembershipRole.OWNER,
    MembershipRole.ADMIN,
    MembershipRole.STAFF,
    MembershipRole.RESPONDER,
}


def get_membership(user, organization_id):
    if not user or not user.is_authenticated:
        return None
    return (
        OrganizationMembership.objects.filter(
            user=user, organization_id=organization_id, is_active=True
        )
        .select_related("organization")
        .first()
    )


def user_org_ids(user):
    if not user or not user.is_authenticated:
        return []
    return list(
        OrganizationMembership.objects.filter(user=user, is_active=True).values_list(
            "organization_id", flat=True
        )
    )


class IsPlatformAdmin(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.is_platform_admin
        )


class IsPlatformStaff(BasePermission):
    """Super admins and registrars."""

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user and user.is_authenticated and (user.is_platform_admin or user.is_registrar)
        )


class IsOrgMember(BasePermission):
    """Requires organization_id in view.kwargs or query/body."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if request.user.is_platform_admin:
            return True
        org_id = view.kwargs.get("organization_id") or request.query_params.get(
            "organization"
        )
        if not org_id:
            return True  # object-level will filter
        return get_membership(request.user, org_id) is not None


class CanManageOrg(BasePermission):
    def has_object_permission(self, request, view, obj):
        if request.user.is_platform_admin:
            return True
        org = getattr(obj, "organization", obj)
        m = get_membership(request.user, org.id)
        return m is not None and m.role in ADMIN_ROLES


class CanWriteOrgData(BasePermission):
    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return True
        if not request.user or not request.user.is_authenticated:
            return False
        if request.user.is_platform_admin:
            return True
        org_id = (
            view.kwargs.get("organization_id")
            or request.query_params.get("organization")
            or request.data.get("organization")
        )
        if not org_id:
            return True
        m = get_membership(request.user, org_id)
        return m is not None and m.role in MANAGE_ROLES
