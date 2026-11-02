from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.organizations.models import Invitation, MembershipRole, Organization, OrganizationMembership

User = get_user_model()
OWNER_PHONE = "+254712345678"
SEND_SMS = "apps.safety.services.sms_provider.SmsProvider.send_sms"


def onboard_payload(**extra):
    return {
        "name": "Mastercard",
        "owner_first_name": "Lena",
        "owner_phone": OWNER_PHONE,
        **extra,
    }


class OnboardTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_authenticate(self.admin)

    def test_non_admin_is_forbidden(self):
        self.client.force_authenticate(User.objects.create_user(phone="+254712345679"))
        for url in ("/api/organizations/onboard/", "/api/organizations/"):
            resp = self.client.post(url, onboard_payload(), format="json")
            self.assertEqual(resp.status_code, 403, url)

    @patch(SEND_SMS, return_value={"success": True})
    def test_representative_owns_it_and_admin_is_not_a_member(self, sms):
        resp = self.client.post("/api/organizations/onboard/", onboard_payload(), format="json")
        self.assertEqual(resp.status_code, 201, resp.content)
        org = Organization.objects.get(name="Mastercard")
        owner = User.objects.get(phone=OWNER_PHONE)
        self.assertFalse(owner.has_usable_password())
        self.assertEqual(owner.account_type, "organization")
        membership = OrganizationMembership.objects.get(organization=org)
        self.assertEqual(membership.user, owner)
        self.assertEqual(membership.role, MembershipRole.OWNER)
        self.assertFalse(OrganizationMembership.objects.filter(user=self.admin).exists())
        self.assertTrue(resp.data["sms_sent"])
        self.assertIn("/forgot-password", sms.call_args.args[1])

    @patch(SEND_SMS, return_value={"success": False, "error": "down"})
    def test_failed_sms_still_saves_and_reports(self, _sms):
        resp = self.client.post("/api/organizations/onboard/", onboard_payload(), format="json")
        self.assertEqual(resp.status_code, 201)
        self.assertFalse(resp.data["sms_sent"])
        self.assertEqual(resp.data["sms_error"], "down")
        self.assertTrue(Organization.objects.filter(name="Mastercard").exists())

    @patch(SEND_SMS, return_value={"success": True})
    def test_existing_account_becomes_owner(self, _sms):
        existing = User.objects.create_user(phone=OWNER_PHONE, password="Str0ng-Passw0rd!")
        resp = self.client.post("/api/organizations/onboard/", onboard_payload(), format="json")
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertFalse(resp.data["owner"]["is_new"])
        self.assertTrue(
            OrganizationMembership.objects.filter(
                user=existing, role=MembershipRole.OWNER
            ).exists()
        )

    def test_email_of_a_different_account_is_rejected(self):
        User.objects.create_user(email="taken@example.com", phone="+254712345679")
        resp = self.client.post(
            "/api/organizations/onboard/",
            onboard_payload(owner_email="taken@example.com"),
            format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("owner_email", resp.data["details"])
        self.assertFalse(Organization.objects.exists())

    def test_platform_admin_cannot_be_owner(self):
        self.admin.phone = OWNER_PHONE
        self.admin.save()
        resp = self.client.post("/api/organizations/onboard/", onboard_payload(), format="json")
        self.assertEqual(resp.status_code, 400)


class StaffByPhoneTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_authenticate(self.admin)
        self.org = Organization.objects.create(name="Acme", slug="acme")

    def test_add_member_by_phone_and_reject_bad_role(self):
        staff = User.objects.create_user(phone=OWNER_PHONE)
        url = f"/api/organizations/{self.org.id}/members/"
        resp = self.client.post(url, {"identifier": OWNER_PHONE, "role": "BOSS"}, format="json")
        self.assertEqual(resp.status_code, 400)
        resp = self.client.post(url, {"identifier": OWNER_PHONE, "role": "STAFF"}, format="json")
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertEqual(resp.data["user_phone"], OWNER_PHONE)
        self.assertTrue(self.org.memberships.filter(user=staff).exists())

    @patch(SEND_SMS, return_value={"success": True})
    def test_invite_for_new_person_creates_account_and_membership(self, sms):
        resp = self.client.post(
            f"/api/organizations/{self.org.id}/invitations/",
            {"phone": OWNER_PHONE, "role": "RESPONDER", "first_name": "Rita"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertTrue(resp.data["joined"])
        user = User.objects.get(phone=OWNER_PHONE)
        self.assertFalse(user.has_usable_password())
        self.assertTrue(self.org.memberships.filter(user=user, role="RESPONDER").exists())
        self.assertIn(user.username, sms.call_args.args[1])
        self.assertIn("/forgot-password", sms.call_args.args[1])

    @patch(SEND_SMS, return_value={"success": True})
    def test_invite_existing_account_and_accept(self, sms):
        invitee = User.objects.create_user(phone=OWNER_PHONE)
        resp = self.client.post(
            f"/api/organizations/{self.org.id}/invitations/",
            {"phone": OWNER_PHONE, "role": "RESPONDER"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        invitation = Invitation.objects.get()
        self.assertIn(invitation.token, sms.call_args.args[1])

        stranger = User.objects.create_user(phone="+254712345679")
        self.client.force_authenticate(stranger)
        resp = self.client.post(
            "/api/invitations/accept/", {"token": invitation.token}, format="json"
        )
        self.assertEqual(resp.status_code, 403)

        self.client.force_authenticate(invitee)
        resp = self.client.post(
            "/api/invitations/accept/", {"token": invitation.token}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertTrue(self.org.memberships.filter(user=invitee, role="RESPONDER").exists())

    def test_invite_needs_phone_or_email(self):
        resp = self.client.post(
            f"/api/organizations/{self.org.id}/invitations/", {"role": "STAFF"}, format="json"
        )
        self.assertEqual(resp.status_code, 400)
