from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils.text import slugify

from apps.accounts.access import send_access_sms
from apps.notifications.sms_text import sms_name
from apps.organizations.models import MembershipRole, Organization, OrganizationMembership


class OrganizationService:
    @staticmethod
    def _unique_slug(name: str) -> str:
        base = slugify(name) or "org"
        slug = base
        i = 1
        while Organization.objects.filter(slug=slug).exists():
            slug = f"{base}-{i}"
            i += 1
        return slug

    @classmethod
    def create_organization(cls, name: str, owner, **extra) -> Organization:
        org = Organization.objects.create(
            name=name, slug=cls._unique_slug(name), **extra
        )
        OrganizationMembership.objects.create(
            organization=org,
            user=owner,
            role=MembershipRole.OWNER,
        )
        return org

    @classmethod
    @transaction.atomic
    def onboard(cls, *, name, owner_fields, existing_owner=None, **org_fields):
        """Create an organization owned by its own representative, not the admin adding it."""
        owner = existing_owner
        created_owner = owner is None
        if created_owner:
            owner = get_user_model().objects.create_user(
                password=None, account_type="organization", **owner_fields
            )
        else:
            changed = []
            for field in ("phone", "email"):
                if owner_fields.get(field) and not getattr(owner, field):
                    setattr(owner, field, owner_fields[field])
                    changed.append(field)
            if changed:
                owner.save(update_fields=changed)
        return cls.create_organization(name=name, owner=owner, **org_fields), owner, created_owner

    @staticmethod
    def notify_owner(org, owner) -> tuple[bool, str]:
        """Text the owner how to get in. Failure is reported, because the organization is saved."""
        return send_access_sms(owner, f"You now own {sms_name(org.name)} on SafeBangle.")
