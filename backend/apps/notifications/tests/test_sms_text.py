from datetime import date, datetime, timedelta, timezone as dt_timezone
from io import StringIO
from unittest.mock import Mock, patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.alerts.geo import GeoError, area_from_address, opencellid_lookup, reverse_geocode_place
from apps.alerts.models import Alert
from apps.devices.models import Bracelet, BraceletStatus
from apps.notifications.birthdays import celebrated_on, days_until_birthday, is_birthday
from apps.notifications.models import BirthdayGreeting, Notification
from apps.notifications.services import AlertRoutingService
from apps.notifications.sms_text import (
    BIRTHDAY_MESSAGES,
    birthday_sms,
    checkin_sms,
    format_radius,
    gsm_safe,
    local_time,
    map_link,
    sos_sms,
    zone_for_phone,
)
from apps.people.models import Person, TrustedContact
from apps.safety.models import LocationSnapshot, SafetyProfile
from apps.safety.services.safety_engine import build_emergency_sms

User = get_user_model()
SEND_SMS = "apps.safety.services.sms_provider.SmsProvider.send_sms"
LONG_NAME = "Maximiliana Wilhelmina Featherstonehaugh-Cholmondeley"
LONG_AREA = "Northern Bypass Service Road Extension, Greater Kampala Metropolitan Area District"


class SmsTextTests(TestCase):
    def test_every_emergency_text_fits_one_sms(self):
        whens = ["14:32 EAT", "12 Nov 14:32 EAT"]
        cases = [
            (LONG_NAME, LONG_AREA, 12500, "-33.92490", "-151.20700"),
            (LONG_NAME, "", None, "0.3", "32.5"),
            ("\u0639\u0627\u0626\u0634\u0629", LONG_AREA, 750, "-1.2921", "36.8219"),
            ("Am\u00edna Ot\u00edeno", "Nak\u00e1sero, Kampala", 2000, "0.3476", "32.5825"),
        ]
        for when in whens:
            for name, area, radius, lat, lng in cases:
                for text in (
                    sos_sms(name, area, when, radius, lat, lng),
                    checkin_sms(name, area, when, lat, lng),
                ):
                    self.assertLessEqual(len(text), 160, text)
                    self.assertEqual(text, text.encode("ascii").decode())
                    self.assertIn(map_link(lat, lng), text)
                    self.assertIn(when, text)

    def test_sos_example_and_no_location(self):
        text = sos_sms("Amina Otieno", "Kampala Road, Kampala", "14:32 EAT", 750, "0.3476", "32.5825")
        self.assertEqual(
            text,
            "SOS! Amina Otieno needs help near Kampala Road, Kampala at 14:32 EAT. "
            "Within 750m. https://maps.google.com/?q=0.34760,32.58250",
        )
        self.assertEqual(
            sos_sms("Amina", "", "14:32 EAT", None, None, None),
            "SOS! Amina needs help. Location unavailable. Sent 14:32 EAT.",
        )

    def test_long_place_keeps_the_wider_place(self):
        text = sos_sms("Amina", "A" * 130 + " Road, Kampala", "14:32 EAT", None, "0.3", "32.5")
        self.assertIn("near Kampala at", text)

    def test_special_characters_never_inflate_the_cost(self):
        self.assertEqual(gsm_safe("Nak\u00e1sero ~[Road]\U0001F600  Hill"), "Nakasero Road Hill")
        self.assertEqual(sos_sms("\u0639\u0627", "", "14:32", None, None, None)[:18], "SOS! Your contact ")

    def test_format_radius(self):
        self.assertEqual(format_radius(750), "750m")
        self.assertEqual(format_radius(2000), "2km")
        self.assertEqual(format_radius(1500), "1.5km")
        self.assertEqual(format_radius(None), "")
        self.assertEqual(format_radius(0), "")

    def test_time_zone_comes_from_phone_with_default(self):
        self.assertEqual(str(zone_for_phone("+254712345678")), "Africa/Nairobi")
        self.assertEqual(str(zone_for_phone("+447700900000")), "Africa/Kampala")
        self.assertEqual(str(zone_for_phone("")), "Africa/Kampala")

    def test_local_time_adds_day_only_when_not_today(self):
        now = timezone.now()
        self.assertRegex(local_time(now, "+254712345678"), r"^\d\d:\d\d EAT$")
        self.assertRegex(
            local_time(now - timedelta(days=3), "+254712345678"), r"^\d+ [A-Z][a-z]{2} \d\d:\d\d EAT$"
        )


class GeocodeTests(TestCase):
    def test_area_prefers_road_then_city(self):
        self.assertEqual(
            area_from_address({"road": "Kampala Road", "suburb": "Nakasero", "city": "Kampala"}),
            "Kampala Road, Kampala",
        )
        self.assertEqual(area_from_address({"suburb": "Westlands", "city": "Nairobi"}), "Westlands, Nairobi")
        self.assertEqual(area_from_address({"village": "Kisaasi"}), "Kisaasi")
        self.assertEqual(area_from_address({"city": "Kampala", "suburb": "Kampala"}), "Kampala")
        self.assertEqual(area_from_address({}), "")
        self.assertEqual(area_from_address(None), "")

    @patch("apps.alerts.geo.requests.get", side_effect=OSError("down"))
    def test_failure_returns_empty_values(self, _get):
        self.assertEqual(reverse_geocode_place(0.3, 32.5), {"label": "", "area": ""})

    @patch("apps.alerts.geo.requests.get")
    def test_uses_address_details_in_english(self, get):
        get.return_value = Mock(
            ok=True,
            content=b"x",
            json=lambda: {
                "display_name": "Kampala Road, Nakasero, Kampala, Uganda",
                "address": {"road": "Kampala Road", "city": "Kampala"},
            },
        )
        place = reverse_geocode_place(0.3, 32.5)
        self.assertEqual(place["area"], "Kampala Road, Kampala")
        self.assertEqual(get.call_args.kwargs["params"]["accept-language"], "en")


@override_settings(OPENCELLID_API_KEY="secret-key-value")
class OpenCellIdRetryTests(TestCase):
    def lookup(self):
        return opencellid_lookup(mcc=641, mnc=10, lac=1, cellid=2)

    @patch("apps.alerts.geo.requests.get")
    def test_slow_connection_is_retried(self, get):
        good = Mock(
            ok=True,
            status_code=200,
            content=b"x",
            json=lambda: {"lat": 0.3, "lon": 32.5, "range": 900},
        )
        get.side_effect = [OSError("timed out"), good]
        cell = self.lookup()
        self.assertEqual(cell["accuracy_m"], 900)
        self.assertEqual(get.call_count, 2)

    @patch(
        "apps.alerts.geo.requests.get",
        side_effect=OSError("failed url /cell/get?key=secret-key-value"),
    )
    def test_gives_up_after_two_tries_without_logging_the_key(self, get):
        with self.assertLogs("apps.alerts.geo", level="ERROR") as logs:
            with self.assertRaises(GeoError) as caught:
                self.lookup()
        self.assertEqual(caught.exception.code, "opencellid_unreachable")
        self.assertEqual(get.call_count, 2)
        self.assertNotIn("secret-key-value", "".join(logs.output))
        for record in logs.records:
            self.assertIsNone(record.exc_info)


class RoutingTests(TestCase):
    def test_email_keeps_full_address_while_sms_is_short(self):
        person = Person.objects.create(first_name="Ada", phone="+254711000001")
        TrustedContact.objects.create(
            person=person, name="Kin", phone="+254722000002", email="kin@example.com"
        )
        alert = Alert.objects.create(
            person=person,
            alert_code="SOS",
            latitude="0.347600",
            longitude="32.582500",
            location_label="Kampala Road, Nakasero, Kampala Central, Kampala, Uganda",
            location_area="Kampala Road, Kampala",
            location_accuracy_m=750,
            received_at=timezone.now(),
        )
        alert.refresh_from_db()
        AlertRoutingService.route_alert(alert)
        sms = Notification.objects.get(channel=Notification.Channel.SMS)
        email = Notification.objects.get(channel=Notification.Channel.EMAIL)
        self.assertLessEqual(len(sms.message), 160)
        self.assertIn("near Kampala Road, Kampala", sms.message)
        self.assertIn("Within 750m", sms.message)
        self.assertIn("Kampala Central, Kampala, Uganda", email.message)
        self.assertIn("next of kin", email.message)
        self.assertIn("within about 750m", email.message)


class CheckinTextTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(phone="+256700000001", first_name="Amina")
        self.profile = SafetyProfile.objects.create(user=self.user, legacy_uid="+256700000001")

    @patch(
        "apps.safety.services.safety_engine.reverse_geocode_place",
        return_value={"label": "Kampala Road, Kampala, Uganda", "area": "Kampala Road, Kampala"},
    )
    def test_looks_up_missing_place_and_saves_it(self, _geo):
        snapshot = LocationSnapshot.objects.create(user=self.user, latitude=0.3476, longitude=32.5825)
        text = build_emergency_sms(self.profile)
        self.assertIn("SafeBangle: Amina missed a check-in. Last seen near Kampala Road, Kampala at", text)
        self.assertIn("https://maps.google.com/?q=0.34760,32.58250", text)
        self.assertLessEqual(len(text), 160)
        snapshot.refresh_from_db()
        self.assertEqual(snapshot.address, "Kampala Road, Kampala, Uganda")

    def test_no_location(self):
        self.assertEqual(
            build_emergency_sms(self.profile),
            "SafeBangle: Amina missed a check-in. Location unavailable.",
        )


class BirthdayDateTests(TestCase):
    def test_leap_day(self):
        leap = date(2000, 2, 29)
        self.assertTrue(is_birthday(leap, date(2027, 2, 28)))
        self.assertFalse(is_birthday(leap, date(2028, 2, 28)))
        self.assertTrue(is_birthday(leap, date(2028, 2, 29)))
        self.assertEqual(celebrated_on(leap, 2027), date(2027, 2, 28))

    def test_days_until(self):
        self.assertEqual(days_until_birthday(date(1990, 1, 2), date(2026, 12, 30)), 3)
        self.assertEqual(days_until_birthday(date(1990, 12, 30), date(2026, 12, 30)), 0)

    def test_every_message_fits_one_sms_and_is_plain(self):
        self.assertEqual(len(BIRTHDAY_MESSAGES), 4)
        for seed in range(4):
            text = birthday_sms(LONG_NAME, seed)
            self.assertLessEqual(len(text), 160, text)
            self.assertEqual(text, text.encode("ascii").decode())
        self.assertIn("friend", birthday_sms("", 0))


# 2026-07-15 09:00 in Kampala and Nairobi (UTC+3).
MORNING = datetime(2026, 7, 15, 6, 0, tzinfo=dt_timezone.utc)
EARLY = datetime(2026, 7, 15, 4, 0, tzinfo=dt_timezone.utc)


@patch(SEND_SMS, return_value={"success": True})
class BirthdayCommandTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            phone="+256700000001", first_name="Amina", date_of_birth=date(1995, 7, 15)
        )

    def run_at(self, moment, **options):
        out = StringIO()
        with patch("django.utils.timezone.now", return_value=moment):
            call_command("send_birthday_wishes", stdout=out, **options)
        return out.getvalue()

    def test_sends_once_after_8am_local(self, sms):
        self.run_at(EARLY)
        sms.assert_not_called()
        self.run_at(MORNING)
        self.assertEqual(sms.call_count, 1)
        self.assertIn("Amina", sms.call_args.args[1])
        self.assertEqual(sms.call_args.kwargs["purpose"], "birthday")
        self.assertEqual(BirthdayGreeting.objects.get().status, "SENT")
        self.run_at(MORNING + timedelta(hours=1))
        self.assertEqual(sms.call_count, 1)

    def test_not_on_other_days(self, sms):
        self.run_at(MORNING + timedelta(days=1))
        sms.assert_not_called()

    def test_skips_muted_blocked_and_no_phone(self, sms):
        for field in ("is_muted", "is_active"):
            User.objects.filter(pk=self.user.pk).update(
                is_muted=field == "is_muted", is_active=field != "is_active"
            )
            self.run_at(MORNING)
        User.objects.filter(pk=self.user.pk).update(is_muted=False, is_active=True, phone=None)
        self.run_at(MORNING)
        sms.assert_not_called()

    def test_failed_send_retries_up_to_three_times(self, sms):
        sms.return_value = {"success": False, "error": "down"}
        for hour in range(5):
            self.run_at(MORNING + timedelta(hours=hour))
        self.assertEqual(sms.call_count, 3)
        greeting = BirthdayGreeting.objects.get()
        self.assertEqual(greeting.status, "FAILED")
        self.assertEqual(greeting.error, "down")

    def test_retry_can_succeed(self, sms):
        sms.return_value = {"success": False, "error": "down"}
        self.run_at(MORNING)
        sms.return_value = {"success": True}
        self.run_at(MORNING + timedelta(hours=1))
        self.assertEqual(BirthdayGreeting.objects.get().status, "SENT")

    def test_dry_run_sends_nothing(self, sms):
        output = self.run_at(MORNING, dry_run=True)
        sms.assert_not_called()
        self.assertIn(self.user.username, output)
        self.assertFalse(BirthdayGreeting.objects.exists())

    def test_upcoming_birthdays_is_admin_only(self, sms):
        client = APIClient()
        client.force_authenticate(self.user)
        self.assertEqual(client.get("/api/auth/users/upcoming-birthdays/").status_code, 403)
        registrar = User.objects.create_user(phone="+256700000002", platform_role="registrar")
        client.force_authenticate(registrar)
        self.assertEqual(client.get("/api/auth/users/upcoming-birthdays/").status_code, 403)

        admin = User.objects.create_superuser(email="a@example.com", password="x")
        soon = timezone.localdate() + timedelta(days=3)
        far = timezone.localdate() + timedelta(days=30)
        User.objects.filter(pk=self.user.pk).update(date_of_birth=soon.replace(year=1990))
        User.objects.create_user(phone="+256700000003", date_of_birth=far.replace(year=1990))
        client.force_authenticate(admin)
        rows = client.get("/api/auth/users/upcoming-birthdays/").data
        self.assertEqual([r["id"] for r in rows], [str(self.user.id)])
        self.assertEqual(rows[0]["days_away"], 3)
        self.assertNotIn("date_of_birth", rows[0])
