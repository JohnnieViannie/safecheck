"""
Import SafeCheck UserProfile rows from the legacy server DB into the unified Blaces backend.

Usage (from blaces/backend, with both DBs reachable):

  # Set LEGACY_DATABASE_URL to the old SafeCheck Postgres/MySQL URL, then:
  python manage.py migrate_safecheck_users

Requires the legacy `api_userprofile` (and related) tables. Creates accounts.User +
SafetyProfile + TrustedContact for each profile. Idempotent on email/legacy_uid.
"""
from __future__ import annotations

import json
import os
from datetime import datetime

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import connections
from django.utils.dateparse import parse_datetime

from apps.mobile_compat.identity import get_or_create_profile, sync_trusted_contacts_from_json
from apps.safety.models import SafetyProfile

User = get_user_model()


class Command(BaseCommand):
    help = "Migrate SafeCheck UserProfile rows into accounts.User + SafetyProfile + TrustedContact"

    def add_arguments(self, parser):
        parser.add_argument(
            "--legacy-db",
            default=os.getenv("LEGACY_DATABASE_URL", ""),
            help="DATABASE_URL for the legacy SafeCheck server (or set LEGACY_DATABASE_URL).",
        )
        parser.add_argument("--dry-run", action="store_true")

    def handle(self, *args, **options):
        legacy = (options["legacy_db"] or "").strip()
        dry_run = options["dry_run"]
        if not legacy:
            self.stdout.write(
                self.style.WARNING(
                    "No LEGACY_DATABASE_URL / --legacy-db. "
                    "Skipping DB import. Use get_or_create_profile on first mobile login instead."
                )
            )
            return

        # Configure ephemeral connection alias.
        from urllib.parse import urlparse, unquote

        parsed = urlparse(legacy)
        engine = {
            "postgres": "django.db.backends.postgresql",
            "postgresql": "django.db.backends.postgresql",
            "mysql": "django.db.backends.mysql",
        }.get(parsed.scheme)
        if not engine:
            self.stderr.write(f"Unsupported scheme: {parsed.scheme}")
            return
        # Inherit Django's connection defaults (TIME_ZONE, CONN_MAX_AGE, ...).
        connections.databases["legacy"] = {
            **connections["default"].settings_dict,
            "OPTIONS": {},
            "ENGINE": engine,
            "NAME": unquote(parsed.path.lstrip("/")),
            "USER": unquote(parsed.username or ""),
            "PASSWORD": unquote(parsed.password or ""),
            "HOST": parsed.hostname or "",
            "PORT": str(parsed.port or ""),
        }

        with connections["legacy"].cursor() as cursor:
            cursor.execute(
                "SELECT uid, full_name, email, password, phone_number, "
                "onboarding_completed, onboarding_step, onboarding_draft_json, "
                "user_type, checkin_frequency, grace_period_hours, grace_period_minutes, "
                "emergency_contact_name, emergency_contact_relationship, "
                "emergency_contact_country_code, emergency_contact_phone, "
                "emergency_contact_email, emergency_contacts_json, "
                "trigger_actions_json, notification_prefs_json, pin, "
                "last_check_in_at, checkin_time, timezone, max_retry_attempts, "
                "last_call_status, escalation_status, last_escalated_at, "
                "next_scheduled_checkin_at, fcm_token, fcm_token_updated_at, "
                "fcm_platform, snoozed_until, last_push_sent_at, pending_call_kit_id "
                "FROM api_userprofile"
            )
            rows = cursor.fetchall()
            cols = [c[0] for c in cursor.description]

        created = 0
        updated = 0
        for row in rows:
            data = dict(zip(cols, row))
            uid = (data.get("uid") or "").strip()
            email = (data.get("email") or (uid if "@" in uid else "") or "").strip().lower()
            if not uid:
                continue
            if dry_run:
                self.stdout.write(f"[dry-run] would migrate {uid}")
                created += 1
                continue

            profile, was_created = get_or_create_profile(
                uid,
                email=email or None,
                phone=data.get("phone_number"),
            )
            account = profile.user
            if data.get("password") and data["password"].startswith(
                ("pbkdf2_", "argon2", "bcrypt")
            ):
                account.password = data["password"]
                account.save(update_fields=["password"])
            if data.get("full_name"):
                parts = str(data["full_name"]).split(None, 1)
                account.first_name = parts[0]
                account.last_name = parts[1] if len(parts) > 1 else ""
                account.save(update_fields=["first_name", "last_name"])
            if data.get("phone_number"):
                account.phone = data["phone_number"]
                account.save(update_fields=["phone"])

            field_map = [
                "onboarding_completed",
                "onboarding_step",
                "onboarding_draft_json",
                "user_type",
                "checkin_frequency",
                "grace_period_hours",
                "grace_period_minutes",
                "emergency_contact_name",
                "emergency_contact_relationship",
                "emergency_contact_country_code",
                "emergency_contact_phone",
                "emergency_contact_email",
                "emergency_contacts_json",
                "trigger_actions_json",
                "notification_prefs_json",
                "pin",
                "checkin_time",
                "timezone",
                "max_retry_attempts",
                "last_call_status",
                "escalation_status",
                "fcm_token",
                "fcm_platform",
                "pending_call_kit_id",
            ]
            for f in field_map:
                if data.get(f) is not None:
                    setattr(profile, f, data[f])
            for f in (
                "last_check_in_at",
                "last_escalated_at",
                "next_scheduled_checkin_at",
                "fcm_token_updated_at",
                "snoozed_until",
                "last_push_sent_at",
            ):
                val = data.get(f)
                if val is None:
                    continue
                if isinstance(val, str):
                    val = parse_datetime(val)
                if isinstance(val, datetime):
                    setattr(profile, f, val)
            profile.save()
            if data.get("emergency_contacts_json"):
                sync_trusted_contacts_from_json(profile, data["emergency_contacts_json"])
            if was_created:
                created += 1
            else:
                updated += 1

        self.stdout.write(
            self.style.SUCCESS(f"Migrated profiles: created={created}, updated={updated}")
        )
