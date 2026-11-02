"""Phone normalization shared by accounts, organizations and the mobile API."""
from __future__ import annotations

import re

import phonenumbers

PLACEHOLDER_EMAIL_DOMAIN = "@phone.safebangle.local"


def normalize_phone(raw_value, country_code=None) -> str | None:
    """Accept local digits (779697569) or E164 (+256779697569). Local digits need a country."""
    text = str(raw_value or "").strip()
    if not text:
        return None

    if text.startswith("+"):
        try:
            parsed = phonenumbers.parse(text, None)
        except phonenumbers.NumberParseException:
            return None
    else:
        digits = "".join(ch for ch in text if ch.isdigit())
        region = str(country_code or "").strip().upper()
        if not digits or not re.fullmatch(r"[A-Z]{2}", region):
            return None
        try:
            parsed = phonenumbers.parse(digits, region)
        except phonenumbers.NumberParseException:
            return None

    if not phonenumbers.is_valid_number(parsed):
        return None
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)


def is_email_identifier(identifier) -> bool:
    return "@" in str(identifier or "")


def is_username_identifier(identifier) -> bool:
    """Usernames always start with a letter; phone numbers never do."""
    text = str(identifier or "").strip()
    return bool(text) and text[0].isalpha() and "@" not in text


def is_placeholder_email(email) -> bool:
    return str(email or "").lower().endswith(PLACEHOLDER_EMAIL_DOMAIN)


def find_phone_issues(rows) -> list[str]:
    """Describe stored phones that can't become unique E164 values.

    ``rows`` holds (user_id, phone, country_code). Used by the audit command and migration.
    """
    issues = []
    seen: dict[str, object] = {}
    for user_id, phone, country_code in rows:
        if not (phone or "").strip():
            continue
        normalized = normalize_phone(phone, country_code)
        if not normalized:
            issues.append(f"invalid: user {user_id} has {phone!r}")
        elif normalized in seen:
            issues.append(f"duplicate: users {seen[normalized]} and {user_id} share {normalized}")
        else:
            seen[normalized] = user_id
    return issues
