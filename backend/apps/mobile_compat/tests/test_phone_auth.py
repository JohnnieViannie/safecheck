import re
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from apps.mobile_compat.identity import get_or_create_profile

User = get_user_model()
PHONE = "+254712345678"
OTHER_PHONE = "+254712345679"
SEND_SMS = "apps.mobile_compat.views.SmsProvider.send_sms"


class MobileOtpTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def send(self, phone=PHONE):
        with patch(SEND_SMS, return_value={"success": True}) as sms:
            resp = self.client.post("/api/auth/send-otp/", {"phoneNumber": phone}, format="json")
        self.assertEqual(resp.status_code, 200, resp.content)
        return resp.data["verificationId"], re.search(r"\b\d{6}\b", sms.call_args.args[1]).group()

    def verify(self, verification_id, phone, code):
        return self.client.post(
            "/api/auth/verify-otp/",
            {"verificationId": verification_id, "phoneNumber": phone, "smsCode": code},
            format="json",
        )

    def test_registered_number_logs_in_without_a_prior_app_profile(self):
        user = User.objects.create_user(phone=PHONE)
        verification_id, code = self.send()
        resp = self.verify(verification_id, PHONE, code)
        self.assertEqual(resp.status_code, 200, resp.content)
        user.refresh_from_db()
        self.assertTrue(user.phone_verified)
        self.assertIsNone(user.email)
        self.assertEqual(resp.data["user"]["email"], "")

    def test_unknown_number_gets_same_response_no_sms_and_no_account(self):
        with patch(SEND_SMS) as sms:
            resp = self.client.post("/api/auth/send-otp/", {"phoneNumber": PHONE}, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("verificationId", resp.data)
        sms.assert_not_called()
        self.assertEqual(self.verify(resp.data["verificationId"], PHONE, "123456").status_code, 400)
        self.assertFalse(User.objects.filter(phone=PHONE).exists())

    def test_email_code_and_social_do_not_create_accounts(self):
        resp = self.client.post(
            "/api/auth/send-email-code/", {"email": "new@example.com"}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        resp = self.client.post(
            "/api/auth/social-sign-in/",
            {"provider": "google", "email": "new@example.com", "idToken": "test"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403, resp.content)
        self.assertFalse(User.objects.filter(email="new@example.com").exists())

    def test_profile_save_for_unknown_uid_creates_nothing(self):
        resp = self.client.post("/api/user/profile/", {"uid": PHONE}, format="json")
        self.assertEqual(resp.status_code, 404)
        self.assertFalse(User.objects.filter(phone=PHONE).exists())

    def test_code_for_one_number_cannot_log_in_as_another(self):
        User.objects.create_user(phone=PHONE)
        victim = User.objects.create_user(phone=OTHER_PHONE)
        verification_id, code = self.send()
        resp = self.verify(verification_id, OTHER_PHONE, code)
        self.assertEqual(resp.status_code, 400)
        victim.refresh_from_db()
        self.assertFalse(victim.phone_verified)

    def test_code_dies_after_too_many_wrong_guesses(self):
        User.objects.create_user(phone=PHONE)
        verification_id, code = self.send()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(self.verify(verification_id, PHONE, wrong).status_code, 400)
        self.assertEqual(self.verify(verification_id, PHONE, code).status_code, 400)

    def test_second_request_for_same_number_waits(self):
        User.objects.create_user(phone=PHONE)
        self.send()
        with patch(SEND_SMS, return_value={"success": True}) as sms:
            resp = self.client.post("/api/auth/send-otp/", {"phoneNumber": PHONE}, format="json")
        self.assertEqual(resp.status_code, 429)
        sms.assert_not_called()


class MobileProfileSaveTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.profile, _ = get_or_create_profile(PHONE, phone=PHONE)

    def save(self, **extra):
        return self.client.post(
            "/api/user/profile/", {"uid": PHONE, **extra}, format="json"
        )

    def test_saving_name_phone_and_email_fields_succeeds(self):
        resp = self.save(full_name="Amina Otieno", phone_number=PHONE, email="", onboarding_completed=True)
        self.assertEqual(resp.status_code, 200, resp.content)
        user = User.objects.get(phone=PHONE)
        self.assertEqual(user.first_name, "Amina")

    def test_blank_or_invalid_phone_does_not_overwrite(self):
        for value in ("", "someone@example.com"):
            self.assertEqual(self.save(phone_number=value).status_code, 200)
            self.assertEqual(User.objects.get(pk=self.profile.user_id).phone, PHONE)

    def test_cannot_take_another_accounts_number(self):
        User.objects.create_user(phone=OTHER_PHONE)
        resp = self.save(phone_number=OTHER_PHONE)
        self.assertEqual(resp.status_code, 409)
        self.assertEqual(User.objects.get(pk=self.profile.user_id).phone, PHONE)
