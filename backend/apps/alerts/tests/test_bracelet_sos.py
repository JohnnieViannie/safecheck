from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.alerts.geo import GeoError
from apps.alerts.models import Alert
from apps.devices.models import Bracelet, BraceletStatus
from apps.notifications.models import Notification
from apps.organizations.models import Organization
from apps.people.models import Person, TrustedContact


@override_settings(
    BRACELET_API_SECRET="test-secret",
    DEBUG=True,
    AT_API_KEY="",
    AT_USERNAME="",
    OPENCELLID_API_KEY="",
)
class BraceletSosApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name="Demo School", slug="demo-school")
        self.person = Person.objects.create(
            organization=self.org,
            first_name="Ada",
            last_name="Okello",
            phone="+254711000001",
        )
        self.bracelet = Bracelet.objects.create(
            device_id="SB-TEST-001",
            status=BraceletStatus.IN_USE,
            organization=self.org,
            current_person=self.person,
        )
        self.contact = TrustedContact.objects.create(
            person=self.person,
            organization=self.org,
            name="Next of Kin",
            phone="+254722000002",
            notify_sms=True,
            notify_email=False,
        )
        self.headers = {"HTTP_X_BRACELET_SECRET": "test-secret"}

    @patch(
        "apps.alerts.services.reverse_geocode_place",
        return_value={"label": "Nairobi CBD, Nairobi, Kenya", "area": "Nairobi CBD, Nairobi"},
    )
    def test_gps_sos_creates_alert_and_sms(self, _geo):
        resp = self.client.post(
            "/api/bracelets/sos/gps/",
            {
                "device_id": "SB-TEST-001",
                "latitude": "-1.292100",
                "longitude": "36.821900",
                "timestamp": "2026-09-09T12:00:00Z",
                "phone": "+254711000001",
                "alert_code": "SOS",
            },
            format="json",
            **self.headers,
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertIn("alert_id", resp.data)
        alert = Alert.objects.get(id=resp.data["alert_id"])
        self.assertEqual(alert.location_source, Alert.LocationSource.GPS)
        self.assertEqual(alert.location_label, "Nairobi CBD, Nairobi, Kenya")
        self.assertEqual(alert.location_area, "Nairobi CBD, Nairobi")
        sms = Notification.objects.filter(
            channel=Notification.Channel.SMS, recipient="+254722000002"
        ).first()
        self.assertIsNotNone(sms)
        self.assertIn("SOS! Ada Okello needs help near Nairobi CBD, Nairobi at", sms.message)
        self.assertIn("EAT", sms.message)
        self.assertIn("https://maps.google.com/?q=-1.29210,36.82190", sms.message)
        self.assertLessEqual(len(sms.message), 160)
        self.assertNotIn("Within", sms.message)

    def test_gps_sos_rejects_bad_secret(self):
        resp = self.client.post(
            "/api/bracelets/sos/gps/",
            {
                "device_id": "SB-TEST-001",
                "latitude": "-1.292100",
                "longitude": "36.821900",
                "phone": "+254711000001",
            },
            format="json",
            HTTP_X_BRACELET_SECRET="wrong",
        )
        self.assertEqual(resp.status_code, 403)

    def test_gps_sos_unknown_device(self):
        resp = self.client.post(
            "/api/bracelets/sos/gps/",
            {
                "device_id": "MISSING",
                "latitude": "-1.292100",
                "longitude": "36.821900",
                "phone": "+254711000001",
            },
            format="json",
            **self.headers,
        )
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.data["code"], "unknown_bracelet")

    @patch(
        "apps.alerts.services.reverse_geocode_place",
        return_value={"label": "Nairobi CBD, Nairobi, Kenya", "area": "Nairobi CBD, Nairobi"},
    )
    def test_gps_sos_idempotent(self, _geo):
        payload = {
            "device_id": "SB-TEST-001",
            "latitude": "-1.292100",
            "longitude": "36.821900",
            "timestamp": "2026-09-09T12:00:00Z",
            "phone": "+254711000001",
        }
        r1 = self.client.post(
            "/api/bracelets/sos/gps/",
            payload,
            format="json",
            HTTP_X_BRACELET_SECRET="test-secret",
            HTTP_IDEMPOTENCY_KEY="same-key-1",
        )
        r2 = self.client.post(
            "/api/bracelets/sos/gps/",
            payload,
            format="json",
            HTTP_X_BRACELET_SECRET="test-secret",
            HTTP_IDEMPOTENCY_KEY="same-key-1",
        )
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 200)
        self.assertTrue(r2.data["duplicate"])
        self.assertEqual(Alert.objects.count(), 1)

    @patch("apps.alerts.views.opencellid_lookup")
    @patch(
        "apps.alerts.services.reverse_geocode_place",
        return_value={"label": "Westlands, Nairobi, Kenya", "area": "Westlands, Nairobi"},
    )
    def test_cell_sos_happy_path(self, _geo, mock_cell):
        mock_cell.return_value = {
            "latitude": Decimal("-1.267000"),
            "longitude": Decimal("36.810000"),
            "accuracy_m": 750,
        }
        resp = self.client.post(
            "/api/bracelets/sos/cell/",
            {
                "device_id": "SB-TEST-001",
                "mcc": 639,
                "mnc": 2,
                "lac": 1234,
                "cellid": 56789,
                "radio": "LTE",
                "timestamp": "2026-09-09T12:05:00Z",
                "phone": "+254711000001",
            },
            format="json",
            **self.headers,
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        alert = Alert.objects.get(id=resp.data["alert_id"])
        self.assertEqual(alert.location_source, Alert.LocationSource.OPENCELLID)
        self.assertEqual(alert.location_accuracy_m, 750)
        sms = Notification.objects.filter(channel=Notification.Channel.SMS).first()
        self.assertIsNotNone(sms)
        self.assertIn("near Westlands, Nairobi", sms.message)
        self.assertIn("Within 750m.", sms.message)
        self.assertLessEqual(len(sms.message), 160)

    @patch("apps.alerts.views.opencellid_lookup")
    def test_cell_sos_not_found(self, mock_cell):
        mock_cell.side_effect = GeoError(
            "Cell tower not found in OpenCellID.", "cell_not_found"
        )
        resp = self.client.post(
            "/api/bracelets/sos/cell/",
            {
                "device_id": "SB-TEST-001",
                "mcc": 639,
                "mnc": 2,
                "lac": 1,
                "cellid": 1,
                "phone": "+254711000001",
            },
            format="json",
            **self.headers,
        )
        # The emergency still goes out, saying the location is unavailable.
        self.assertEqual(resp.status_code, 201, resp.content)
        alert = Alert.objects.get()
        self.assertIsNone(alert.latitude)
        sms = Notification.objects.get(channel=Notification.Channel.SMS)
        self.assertIn("SOS! Ada Okello needs help. Location unavailable. Sent", sms.message)

    @patch(
        "apps.alerts.services.reverse_geocode_place", return_value={"label": "", "area": ""}
    )
    @patch("apps.notifications.services.SmsProvider.send")
    def test_africastalking_sms_provider_called(self, mock_send, _geo):
        mock_send.return_value = {"ok": True, "provider_message_id": "AT123"}
        resp = self.client.post(
            "/api/bracelets/sos/gps/",
            {
                "device_id": "SB-TEST-001",
                "latitude": "-1.292100",
                "longitude": "36.821900",
                "phone": "+254711000001",
            },
            format="json",
            **self.headers,
        )
        self.assertEqual(resp.status_code, 201)
        self.assertTrue(mock_send.called)
        phone, message = mock_send.call_args[0]
        self.assertEqual(phone, "+254722000002")
        self.assertTrue(message.startswith("SOS! Ada Okello needs help at "))
        self.assertIn("https://maps.google.com/", message)
