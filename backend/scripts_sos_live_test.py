"""One-off SOS endpoint smoke test. Not for production."""
import os
from pathlib import Path

from dotenv import load_dotenv

BASE = Path(__file__).resolve().parent
load_dotenv(BASE / ".env", override=True)
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django

django.setup()

from django.conf import settings
from django.test import override_settings
from rest_framework.test import APIClient

from apps.devices.models import Bracelet, BraceletStatus
from apps.notifications.models import Notification
from apps.organizations.models import Organization
from apps.people.models import Person, TrustedContact

PHONE = "+256779697569"
DEVICE_ID = "SB-LIVE-TEST-001"


def ensure_fixture():
    org, _ = Organization.objects.get_or_create(
        slug="sos-live-test", defaults={"name": "SOS Live Test Org"}
    )
    person, _ = Person.objects.get_or_create(
        organization=org,
        external_id="wearer-1",
        defaults={
            "first_name": "Test",
            "last_name": "Wearer",
            "phone": "+256700000001",
        },
    )
    bracelet, _ = Bracelet.objects.get_or_create(
        device_id=DEVICE_ID,
        defaults={
            "status": BraceletStatus.IN_USE,
            "organization": org,
            "current_person": person,
        },
    )
    if bracelet.status != BraceletStatus.IN_USE or bracelet.current_person_id != person.id:
        bracelet.status = BraceletStatus.IN_USE
        bracelet.organization = org
        bracelet.current_person = person
        bracelet.save()

    contact, created = TrustedContact.objects.get_or_create(
        organization=org,
        person=person,
        phone=PHONE,
        defaults={
            "name": "Lane (test NOK)",
            "notify_sms": True,
            "notify_email": False,
            "priority": 1,
            "is_active": True,
        },
    )
    if not created:
        contact.notify_sms = True
        contact.is_active = True
        contact.save(update_fields=["notify_sms", "is_active"])
    return org, person, bracelet, contact


def _print_resp(label, resp):
    print(f"status: {resp.status_code}")
    body = getattr(resp, "data", None)
    if body is None:
        try:
            body = resp.content.decode("utf-8", errors="replace")[:800]
        except Exception:
            body = resp.content
    print(f"body: {body}")


def main():
    print("DEBUG=", settings.DEBUG)
    print("AT configured=", bool(settings.AT_API_KEY and settings.AT_USERNAME))
    print("OPENCELLID key=", "SET" if settings.OPENCELLID_API_KEY else "empty (mock in DEBUG)")
    print("BRACELET secret=", "SET" if settings.BRACELET_API_SECRET else "empty (DEBUG allows)")

    ensure_fixture()
    hosts = list(settings.ALLOWED_HOSTS) + ["testserver", "localhost", "127.0.0.1"]
    with override_settings(ALLOWED_HOSTS=hosts):
        client = APIClient()
        headers = {}
        if settings.BRACELET_API_SECRET:
            headers["HTTP_X_BRACELET_SECRET"] = settings.BRACELET_API_SECRET

        print("\n=== 1) GPS SOS (Nominatim reverse geocode) ===")
        gps = client.post(
            "/api/bracelets/sos/gps/",
            {
                "device_id": DEVICE_ID,
                "latitude": "0.347596",
                "longitude": "32.582520",
                "timestamp": "2026-09-25T17:00:00Z",
                "phone": "+256700000001",
                "alert_code": "SOS",
            },
            format="json",
            **headers,
        )
        _print_resp("gps", gps)

        print("\n=== 2) Cell SOS (OpenCellID) ===")
        cell = client.post(
            "/api/bracelets/sos/cell/",
            {
                "device_id": DEVICE_ID,
                "mcc": 641,
                "mnc": 1,
                "lac": 10101,
                "cellid": 12345678,
                "radio": "LTE",
                "timestamp": "2026-09-25T17:01:00Z",
                "phone": "+256700000001",
                "alert_code": "SOS",
            },
            format="json",
            **headers,
        )
        _print_resp("cell", cell)

    print("\n=== Notifications to", PHONE, "===")
    qs = Notification.objects.filter(recipient=PHONE).order_by("-created_at")[:5]
    for n in qs:
        print(
            f"- id={n.id} channel={n.channel} status={n.status} "
            f"error={n.error_message!r} msg={n.message[:160]!r}..."
        )
    if not qs.exists():
        print("(none yet — check routing / SMS provider)")


if __name__ == "__main__":
    main()
