"""Resolve / create accounts.User + SafetyProfile for mobile legacy_uid (email/phone)."""
from __future__ import annotations

import json

from django.contrib.auth import get_user_model
from django.db import transaction

from apps.accounts.phone import normalize_phone
from apps.people.models import TrustedContact
from apps.safety.models import SafetyProfile

User = get_user_model()


def get_profile(uid: str) -> SafetyProfile:
    uid = (uid or "").strip()
    return SafetyProfile.objects.select_related("user").get(legacy_uid=uid)


def get_profile_or_none(uid: str) -> SafetyProfile | None:
    try:
        return get_profile(uid)
    except SafetyProfile.DoesNotExist:
        return None


@transaction.atomic
def get_or_create_profile(
    uid: str,
    *,
    email: str | None = None,
    phone: str | None = None,
    password: str | None = None,
    defaults: dict | None = None,
) -> tuple[SafetyProfile, bool]:
    """Create User + SafetyProfile for a mobile uid (typically email)."""
    uid = (uid or "").strip()
    if not uid:
        raise ValueError("uid is required")

    existing = get_profile_or_none(uid)
    if existing:
        return existing, False

    email_norm = (email or (uid if "@" in uid else "")).strip().lower() or None
    phone_norm = normalize_phone(phone or (uid if uid.startswith("+") else ""))

    user = None
    if email_norm:
        user = User.objects.filter(email__iexact=email_norm).first()
    if user is None and phone_norm:
        user = User.objects.filter(phone=phone_norm).first()

    created_user = False
    if user is None:
        user = User(
            email=email_norm,
            phone=phone_norm,
            account_type="individual",
            email_verified=bool(email_norm),
        )
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save()
        created_user = True
    elif password and not user.has_usable_password():
        user.set_password(password)
        user.save(update_fields=["password"])

    profile_defaults = {
        "legacy_uid": uid,
        "onboarding_completed": False,
    }
    if defaults:
        profile_defaults.update({k: v for k, v in defaults.items() if k != "password"})

    profile, created = SafetyProfile.objects.get_or_create(
        user=user,
        defaults=profile_defaults,
    )
    if not created and profile.legacy_uid != uid:
        # Same Django user, different legacy key — keep existing.
        pass
    elif created and email_norm and profile.legacy_uid != email_norm:
        profile.legacy_uid = email_norm
        profile.save(update_fields=["legacy_uid"])

    return profile, created or created_user


def profile_for_existing_account(
    uid: str, *, email: str | None = None, phone: str | None = None
) -> SafetyProfile | None:
    """Mobile sign-in: find a registered account's profile. Never creates an account."""
    uid = (uid or "").strip()
    if not uid:
        return None
    existing = get_profile_or_none(uid)
    if existing:
        return existing
    email_norm = (email or (uid if "@" in uid else "")).strip().lower()
    phone_norm = normalize_phone(phone or (uid if uid.startswith("+") else ""))
    user = User.objects.filter(email__iexact=email_norm).first() if email_norm else None
    if user is None and phone_norm:
        user = User.objects.filter(phone=phone_norm).first()
    if user is None:
        return None
    # Staff-registered people have no app profile until their first sign-in.
    profile, _ = get_or_create_profile(uid, email=email_norm or None, phone=phone_norm)
    return profile


def contacts_json_for_profile(profile: SafetyProfile) -> str:
    """Serialize TrustedContact rows into the mobile emergency_contacts_json shape."""
    contacts = TrustedContact.objects.filter(
        owner_user=profile.user, is_active=True
    ).order_by("priority", "name")
    if contacts.exists():
        payload = []
        for c in contacts:
            payload.append(
                {
                    "name": c.name,
                    "relationship": c.relationship or "",
                    "phone": c.phone or "",
                    "email": c.email or "",
                    "notify_sms": c.notify_sms,
                    "notify_email": c.notify_email,
                }
            )
        # Preserve opt-in metadata from the write buffer when present.
        buffered = (profile.emergency_contacts_json or "").strip()
        if buffered:
            try:
                buf = json.loads(buffered)
                if isinstance(buf, list):
                    by_phone = {
                        str(i.get("phone") or ""): i for i in buf if isinstance(i, dict)
                    }
                    for item in payload:
                        extra = by_phone.get(item["phone"]) or {}
                        if "id" in extra:
                            item["id"] = extra["id"]
                        if "opt_in_status" in extra:
                            item["opt_in_status"] = extra["opt_in_status"]
                        if "country_code" in extra:
                            item["country_code"] = extra["country_code"]
            except json.JSONDecodeError:
                pass
        return json.dumps(payload)
    if (profile.emergency_contacts_json or "").strip():
        return profile.emergency_contacts_json
    if profile.emergency_contact_phone:
        return json.dumps(
            [
                {
                    "name": profile.emergency_contact_name or "Next of kin",
                    "relationship": profile.emergency_contact_relationship or "",
                    "phone": profile.emergency_contact_phone,
                    "email": profile.emergency_contact_email or "",
                    "country_code": profile.emergency_contact_country_code or "UG",
                }
            ]
        )
    return "[]"


def sync_trusted_contacts_from_json(profile: SafetyProfile, raw_json: str | None) -> None:
    """Replace the app's own TrustedContacts from mobile emergency_contacts_json.

    Contacts attached to a person (added by an admin or organization) are kept. The app
    receives them in its contact list and sends them back, so they're not created twice.
    """
    text = (raw_json or "").strip()
    if not text:
        return
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return
    if not isinstance(parsed, list):
        return

    profile.emergency_contacts_json = text
    profile.save(update_fields=["emergency_contacts_json"])

    TrustedContact.objects.filter(owner_user=profile.user, person__isnull=True).delete()
    person_contact_phones = set(
        TrustedContact.objects.filter(owner_user=profile.user, person__isnull=False)
        .exclude(phone="")
        .values_list("phone", flat=True)
    )
    for idx, item in enumerate(parsed):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        phone = str(item.get("phone") or "").strip()
        email = str(item.get("email") or "").strip()
        if not name and not phone and not email:
            continue
        if phone and phone in person_contact_phones:
            continue
        TrustedContact.objects.create(
            owner_user=profile.user,
            name=name or "Contact",
            phone=phone,
            email=email,
            relationship=str(item.get("relationship") or "").strip(),
            notify_sms=bool(item.get("notify_sms", True)),
            notify_email=bool(item.get("notify_email", True)),
            priority=idx + 1,
            is_active=True,
        )

    # Mirror first contact onto legacy columns for older clients.
    first = (
        TrustedContact.objects.filter(owner_user=profile.user, is_active=True)
        .order_by("priority")
        .first()
    )
    if first:
        profile.emergency_contact_name = first.name
        profile.emergency_contact_relationship = first.relationship
        profile.emergency_contact_phone = first.phone
        profile.emergency_contact_email = first.email or None
        profile.save(
            update_fields=[
                "emergency_contact_name",
                "emergency_contact_relationship",
                "emergency_contact_phone",
                "emergency_contact_email",
            ]
        )


def sync_legacy_primary_to_trusted(profile: SafetyProfile) -> None:
    """Ensure legacy single-contact fields exist as a TrustedContact."""
    phone = (profile.emergency_contact_phone or "").strip()
    if not phone:
        return
    if TrustedContact.objects.filter(owner_user=profile.user, is_active=True).exists():
        return
    TrustedContact.objects.create(
        owner_user=profile.user,
        name=profile.emergency_contact_name or "Next of kin",
        phone=phone,
        email=profile.emergency_contact_email or "",
        relationship=profile.emergency_contact_relationship or "",
        priority=1,
        is_active=True,
    )
