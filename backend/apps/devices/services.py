from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.devices.models import Bracelet, BraceletAssignment, BraceletStatus
from apps.people.models import Person


def people_for_user(user):
    return Person.objects.filter(Q(linked_user=user) | Q(owner_user=user))


def person_for_user(user):
    """The person record for this account, preferring the one linked to their login."""
    linked = Person.objects.filter(linked_user=user).first()
    return linked or Person.objects.filter(owner_user=user).first()


def sync_people_from_user(user):
    """Keep a person's own record matching their account after details change."""
    Person.objects.filter(linked_user=user).update(
        first_name=user.first_name or user.username,
        last_name=user.last_name,
        email=user.email or "",
        phone=user.phone or "",
    )


def current_bracelet_for_user(user):
    return (
        Bracelet.objects.filter(current_person__in=people_for_user(user))
        .select_related("organization", "current_person")
        .first()
    )


def get_assignable_bracelet(device_id: str, person=None):
    """Return an existing spare bracelet, None if this ID is new, or raise if it can't be used."""
    bracelet = Bracelet.objects.filter(device_id__iexact=device_id.strip()).first()
    if bracelet is None:
        return None
    if bracelet.current_person_id and (person is None or bracelet.current_person_id != person.id):
        raise ValidationError({"device_id": "This bracelet is already assigned to someone else."})
    if bracelet.status == BraceletStatus.DEACTIVATED:
        raise ValidationError({"device_id": "This bracelet has been deactivated."})
    if person is not None and person.organization_id and bracelet.organization_id not in (
        None,
        person.organization_id,
    ):
        raise ValidationError({"device_id": "This bracelet belongs to another organization."})
    return bracelet


class BraceletAssignmentService:
    @staticmethod
    @transaction.atomic
    def assign(bracelet: Bracelet, person, assigned_by, reason: str = ""):
        if bracelet.status == BraceletStatus.DEACTIVATED:
            raise ValidationError("Cannot assign a deactivated bracelet.")
        # Close existing assignment
        BraceletAssignment.objects.filter(
            bracelet=bracelet, unassigned_at__isnull=True
        ).update(unassigned_at=timezone.now())
        # Unassign person from other bracelets
        for other in Bracelet.objects.filter(current_person=person).exclude(pk=bracelet.pk):
            BraceletAssignment.objects.filter(
                bracelet=other, unassigned_at__isnull=True
            ).update(unassigned_at=timezone.now())
            other.current_person = None
            other.status = BraceletStatus.UNASSIGNED
            other.save(update_fields=["current_person", "status", "updated_at"])

        assignment = BraceletAssignment.objects.create(
            bracelet=bracelet,
            person=person,
            organization=bracelet.organization or person.organization,
            assigned_by=assigned_by,
            reason=reason,
        )
        bracelet.current_person = person
        if person.organization_id and not bracelet.organization_id:
            bracelet.organization = person.organization
        if person.owner_user_id and not bracelet.owner_user_id:
            bracelet.owner_user = person.owner_user
        bracelet.status = BraceletStatus.IN_USE
        if not bracelet.activated_at:
            bracelet.activated_at = timezone.now()
            if bracelet.status == BraceletStatus.IN_USE:
                pass
        bracelet.save()
        return assignment

    @staticmethod
    @transaction.atomic
    def unassign(bracelet: Bracelet, reason: str = ""):
        BraceletAssignment.objects.filter(
            bracelet=bracelet, unassigned_at__isnull=True
        ).update(unassigned_at=timezone.now())
        bracelet.current_person = None
        bracelet.owner_user = None
        bracelet.status = BraceletStatus.UNASSIGNED
        bracelet.save(update_fields=["current_person", "owner_user", "status", "updated_at"])
        return bracelet

    @staticmethod
    def activate(bracelet: Bracelet):
        # Reactivate from DEACTIVATED / inventory / unassigned → ACTIVATED (unassigned until assign).
        bracelet.current_person = None
        bracelet.status = BraceletStatus.ACTIVATED
        bracelet.activated_at = timezone.now()
        bracelet.save(
            update_fields=["current_person", "status", "activated_at", "updated_at"]
        )
        return bracelet

    @staticmethod
    def deactivate(bracelet: Bracelet):
        BraceletAssignment.objects.filter(
            bracelet=bracelet, unassigned_at__isnull=True
        ).update(unassigned_at=timezone.now())
        bracelet.current_person = None
        bracelet.status = BraceletStatus.DEACTIVATED
        bracelet.save(update_fields=["current_person", "status", "updated_at"])
        return bracelet

    @classmethod
    @transaction.atomic
    def issue(cls, person, device_id: str, assigned_by, reason: str = ""):
        """Give a person a bracelet, registering the device if it's new."""
        device_id = device_id.strip()
        bracelet = get_assignable_bracelet(device_id, person)
        if bracelet is None:
            bracelet = Bracelet.objects.create(
                device_id=device_id,
                status=BraceletStatus.ACTIVATED,
                organization=person.organization,
            )
        cls.assign(bracelet, person, assigned_by=assigned_by, reason=reason or "Registered")
        return bracelet

    @classmethod
    @transaction.atomic
    def replace(cls, person, device_id: str, assigned_by, reason: str = "", old_device_state="spare"):
        """Swap a person's bracelet. A broken one is deactivated; a working one becomes spare."""
        old = Bracelet.objects.filter(current_person=person).first()
        if old and old.device_id.lower() == device_id.strip().lower():
            raise ValidationError({"device_id": "This person already has this bracelet."})
        new = cls.issue(person, device_id, assigned_by, reason or "Replacement")
        if old:
            old.refresh_from_db()
            old.owner_user = None
            if old_device_state == "broken":
                old.status = BraceletStatus.DEACTIVATED
            old.save(update_fields=["owner_user", "status", "updated_at"])
        return new, old

    @classmethod
    @transaction.atomic
    def release_for_user(cls, user):
        """Free every bracelet held by this account so the devices can be reused."""
        bracelets = Bracelet.objects.filter(
            Q(current_person__in=people_for_user(user)) | Q(owner_user=user)
        )
        for bracelet in bracelets:
            if bracelet.current_person_id:
                cls.unassign(bracelet, reason="Account deleted")
            bracelet.owner_user = None
            bracelet.save(update_fields=["owner_user", "updated_at"])
