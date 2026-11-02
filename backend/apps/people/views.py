from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from apps.audit.services import AuditService
from apps.devices.models import Bracelet
from apps.devices.services import BraceletAssignmentService
from apps.organizations.permissions import MANAGE_ROLES, get_membership, user_org_ids

from .models import Person, TrustedContact
from .serializers import PersonSerializer, TrustedContactSerializer

User = get_user_model()


class PersonViewSet(viewsets.ModelViewSet):
    serializer_class = PersonSerializer
    search_fields = ["first_name", "last_name", "email", "phone", "external_id"]
    filterset_fields = ["organization", "is_active"]
    ordering_fields = ["first_name", "created_at"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return Person.objects.all().select_related("organization")
        org_ids = user_org_ids(user)
        visible = Q(organization_id__in=org_ids) | Q(owner_user=user)
        if user.is_registrar:
            visible |= Q(linked_user__registered_by=user)
        return Person.objects.filter(visible).select_related("organization")

    def perform_create(self, serializer):
        # People are registered through Add user, which also issues their bracelet.
        if not self.request.user.is_platform_admin:
            raise PermissionDenied("People are registered by SafeBangle staff.")
        org_id = self.request.data.get("organization")
        ownership = {} if self.request.data.get("owner_user") else {
            "owner_user": None if org_id else self.request.user
        }
        if org_id:
            serializer.save(organization_id=org_id, **ownership)
        else:
            serializer.save(organization=None, **ownership)

    def perform_update(self, serializer):
        person = self.get_object()
        if not self.request.user.is_platform_admin:
            self._ensure_registrar_or_owner(person)
            # Only admins may move a person or attach them to other accounts.
            serializer.save(
                organization=person.organization,
                owner_user=person.owner_user,
                linked_user=person.linked_user,
            )
        else:
            serializer.save()

    def perform_destroy(self, instance):
        if not self.request.user.is_platform_admin:
            raise PermissionDenied("People are removed by SafeBangle staff.")
        instance.delete()

    def _ensure_registrar_or_owner(self, person):
        user = self.request.user
        if person.owner_user_id == user.id:
            return
        if user.is_registrar and person.linked_user and person.linked_user.registered_by_id == user.id:
            return
        raise PermissionDenied()


    @action(detail=True, methods=["post"], url_path="remove-from-organization")
    def remove_from_organization(self, request, pk=None):
        """Someone with an account becomes independent. A record with no account is removed."""
        if not request.user.is_platform_admin:
            raise PermissionDenied("Members are managed by SafeBangle staff.")
        person = self.get_object()
        if not person.organization_id:
            raise ValidationError({"detail": "This person isn't in an organization."})
        organization = person.organization
        with transaction.atomic():
            if person.linked_user_id:
                person.organization = None
                person.owner_user = person.linked_user
                person.save(update_fields=["organization", "owner_user", "updated_at"])
                person.trusted_contacts.update(organization=None, owner_user=person.linked_user)
                for bracelet in Bracelet.objects.filter(current_person=person):
                    bracelet.organization = None
                    bracelet.owner_user = person.linked_user
                    bracelet.save(update_fields=["organization", "owner_user", "updated_at"])
                outcome = "independent"
            else:
                for bracelet in Bracelet.objects.filter(current_person=person):
                    BraceletAssignmentService.unassign(bracelet, reason="Removed from organization")
                person.delete()
                outcome = "deleted"
            AuditService.log(
                actor=request.user,
                action="person.removed_from_organization",
                object_type="Person",
                object_id=str(pk),
                organization=organization,
                metadata={"outcome": outcome},
                request=request,
            )
        return Response({"outcome": outcome})


class TrustedContactViewSet(viewsets.ModelViewSet):
    serializer_class = TrustedContactSerializer
    search_fields = ["name", "email", "phone"]
    filterset_fields = ["organization", "person", "owner_user", "is_active"]

    def get_queryset(self):
        user = self.request.user
        if user.is_platform_admin:
            return TrustedContact.objects.all()
        org_ids = user_org_ids(user)
        visible = (
            Q(organization_id__in=org_ids)
            | Q(person__organization_id__in=org_ids)
            | Q(owner_user=user)
            | Q(person__owner_user=user)
        )
        if user.is_registrar:
            visible |= Q(person__linked_user__registered_by=user) | Q(owner_user__registered_by=user)
        return TrustedContact.objects.filter(visible)

    def _can_manage_person(self, person):
        user = self.request.user
        if user.is_platform_admin or person.owner_user_id == user.id:
            return True
        if user.is_registrar and person.linked_user and person.linked_user.registered_by_id == user.id:
            return True
        if person.organization_id:
            m = get_membership(user, person.organization_id)
            return bool(m and m.role in MANAGE_ROLES)
        return False

    @staticmethod
    def _links_for_person(person):
        """Attach to the person's org and account so SOS and check-in alerts both find it."""
        return {
            "person": person,
            "organization": person.organization,
            "owner_user": person.owner_user or person.linked_user,
        }

    def perform_create(self, serializer):
        user = self.request.user
        data = serializer.validated_data
        org = data.get("organization")
        person = data.get("person")
        if person:
            if not self._can_manage_person(person):
                raise PermissionDenied()
            serializer.save(**self._links_for_person(person))
        elif org:
            if not user.is_platform_admin:
                m = get_membership(user, org.id)
                if not m or m.role not in MANAGE_ROLES:
                    raise PermissionDenied()
            serializer.save()
        else:
            owner_id = self.request.data.get("owner_user")
            allowed = user.is_platform_admin or (
                user.is_registrar
                and owner_id
                and User.objects.filter(id=owner_id, registered_by=user).exists()
            )
            if owner_id and allowed:
                serializer.save(owner_user_id=owner_id)
            else:
                serializer.save(owner_user=user)

    def _ensure_write(self, contact):
        user = self.request.user
        if user.is_platform_admin or contact.owner_user_id == user.id:
            return
        if user.is_registrar and contact.owner_user and contact.owner_user.registered_by_id == user.id:
            return
        if contact.person and self._can_manage_person(contact.person):
            return
        if contact.organization_id:
            m = get_membership(user, contact.organization_id)
            if m and m.role in MANAGE_ROLES:
                return
        raise PermissionDenied()

    def perform_update(self, serializer):
        self._ensure_write(serializer.instance)
        person = serializer.validated_data.get("person")
        if person:
            if not self._can_manage_person(person):
                raise PermissionDenied()
            serializer.save(**self._links_for_person(person))
        else:
            serializer.save()

    def perform_destroy(self, instance):
        self._ensure_write(instance)
        instance.delete()
