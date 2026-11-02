import importlib
import re
from unittest.mock import patch

from django.apps import apps as django_apps
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts.codes import MAX_CODE_ATTEMPTS
from apps.accounts.models import PasswordResetToken
from apps.accounts.phone import find_phone_issues, normalize_phone
from apps.safety.models import SmsMessage
from apps.safety.services.sms_provider import SmsProvider

User = get_user_model()
PHONE = "+254712345678"
PASSWORD = "Str0ng-Passw0rd!"
SEND_SMS = "apps.safety.services.sms_provider.SmsProvider.send_sms"


def code_from(sms_mock):
    return re.search(r"\b\d{6}\b", sms_mock.call_args.args[1]).group()


class PhoneHelpersTests(TestCase):
    def test_normalize(self):
        self.assertEqual(normalize_phone("+254 712 345678"), PHONE)
        self.assertEqual(normalize_phone("0712345678", "KE"), PHONE)
        self.assertIsNone(normalize_phone("0712345678"))
        self.assertIsNone(normalize_phone("not-a-phone", "KE"))

    def test_issues_list_duplicates_and_invalid(self):
        issues = find_phone_issues(
            [(1, PHONE, ""), (2, "0712345678", "KE"), (3, "12", "KE"), (4, "", "")]
        )
        self.assertEqual(len(issues), 2)
        self.assertIn("duplicate", issues[0])
        self.assertIn("invalid", issues[1])


class MigrationDataTests(TestCase):
    def setUp(self):
        self.migration = importlib.import_module(
            "apps.accounts.migrations.0005_phone_first_identity"
        )

    def test_blank_values_become_null_and_numbers_normalize(self):
        blank = User.objects.create_user(email="a@example.com", password=PASSWORD)
        local = User.objects.create_user(email="b@example.com", password=PASSWORD)
        placeholder = User.objects.create_user(
            email="256700@phone.safebangle.local", password=PASSWORD
        )
        User.objects.filter(pk=blank.pk).update(phone="")
        User.objects.filter(pk=local.pk).update(phone="0712345678", country_code="KE")

        self.migration.normalize_identity(django_apps, None)

        blank.refresh_from_db()
        local.refresh_from_db()
        placeholder.refresh_from_db()
        self.assertIsNone(blank.phone)
        self.assertEqual(local.phone, PHONE)
        self.assertIsNone(placeholder.email)

    def test_bad_number_stops_the_migration(self):
        user = User.objects.create_user(email="a@example.com", password=PASSWORD)
        User.objects.filter(pk=user.pk).update(phone="12345")
        with self.assertRaisesMessage(RuntimeError, "Fix these phone numbers"):
            self.migration.check_phones(django_apps, None)


class RegisterAndLoginTests(TestCase):
    def setUp(self):
        cache.clear()  # Auth rate limits would otherwise carry over between tests.
        self.client = APIClient()

    @patch(SEND_SMS, return_value={"success": True})
    def test_unverified_account_verifies_by_sms_then_logs_in(self, sms):
        user = User.objects.create_user(phone=PHONE, password=PASSWORD)
        resp = self.client.post(
            "/api/auth/login/", {"identifier": PHONE, "password": PASSWORD}, format="json"
        )
        self.assertEqual(resp.status_code, 403)
        self.assertTrue(resp.data["requires_verification"])

        resp = self.client.post(
            "/api/auth/verify-phone/", {"identifier": PHONE, "code": code_from(sms)}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        user.refresh_from_db()
        self.assertTrue(user.phone_verified)

        resp = self.client.post(
            "/api/auth/login/",
            {"identifier": "0712345678", "country_code": "KE", "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertIn("tokens", resp.data)

    def test_existing_email_account_still_logs_in(self):
        User.objects.create_user(
            email="old@example.com", password=PASSWORD, email_verified=True
        )
        for identifier in ({"email": "old@example.com"}, {"identifier": "OLD@example.com"}):
            resp = self.client.post(
                "/api/auth/login/", {**identifier, "password": PASSWORD}, format="json"
            )
            self.assertEqual(resp.status_code, 200, resp.content)

    def test_wrong_password_rejected(self):
        User.objects.create_user(phone=PHONE, password=PASSWORD, phone_verified=True)
        resp = self.client.post(
            "/api/auth/login/", {"identifier": PHONE, "password": "wrong"}, format="json"
        )
        self.assertEqual(resp.status_code, 401)


class PasswordResetTests(TestCase):
    def setUp(self):
        cache.clear()  # Auth rate limits would otherwise carry over between tests.
        self.client = APIClient()

    @patch(SEND_SMS, return_value={"success": True})
    def test_sms_reset_sets_password_and_verifies_phone(self, sms):
        user = User.objects.create_user(phone=PHONE, password=None)
        self.assertFalse(user.has_usable_password())
        resp = self.client.post(
            "/api/auth/forgot-password/", {"identifier": PHONE}, format="json"
        )
        self.assertEqual(resp.status_code, 200)
        resp = self.client.post(
            "/api/auth/reset-password/",
            {"identifier": PHONE, "code": code_from(sms), "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        user.refresh_from_db()
        self.assertTrue(user.phone_verified)
        resp = self.client.post(
            "/api/auth/login/", {"identifier": PHONE, "password": PASSWORD}, format="json"
        )
        self.assertEqual(resp.status_code, 200)

    @patch(SEND_SMS, return_value={"success": True})
    def test_unknown_account_gets_same_response(self, sms):
        User.objects.create_user(phone=PHONE, password=None)
        known = self.client.post("/api/auth/forgot-password/", {"identifier": PHONE}, format="json")
        unknown = self.client.post(
            "/api/auth/forgot-password/", {"identifier": "+254712345679"}, format="json"
        )
        self.assertEqual(unknown.status_code, 200)
        self.assertEqual(set(known.data), set(unknown.data))
        self.assertEqual(sms.call_count, 1)

    @patch(SEND_SMS, return_value={"success": True})
    def test_code_locks_after_too_many_wrong_attempts(self, sms):
        User.objects.create_user(phone=PHONE, password=None)
        self.client.post("/api/auth/forgot-password/", {"identifier": PHONE}, format="json")
        code = code_from(sms)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(MAX_CODE_ATTEMPTS):
            resp = self.client.post(
                "/api/auth/reset-password/",
                {"identifier": PHONE, "code": wrong, "password": PASSWORD},
                format="json",
            )
            self.assertEqual(resp.status_code, 400)
        resp = self.client.post(
            "/api/auth/reset-password/",
            {"identifier": PHONE, "code": code, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    @patch(SEND_SMS, return_value={"success": True})
    def test_repeat_requests_are_rate_limited(self, sms):
        user = User.objects.create_user(phone=PHONE, password=None)
        for _ in range(3):
            self.client.post("/api/auth/forgot-password/", {"identifier": PHONE}, format="json")
        self.assertEqual(sms.call_count, 1)
        self.assertEqual(PasswordResetToken.objects.filter(user=user).count(), 1)

    def test_otp_codes_are_not_kept_in_the_sms_log(self):
        with patch.object(SmsProvider, "_send_africastalking", return_value={"success": True}):
            SmsProvider().send_sms(PHONE, "Your code is 123456.", purpose="otp")
        self.assertEqual(SmsMessage.objects.get().message, "Your code is [code].")
