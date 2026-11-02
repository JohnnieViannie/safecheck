import json
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.devices.models import Bracelet, BraceletStatus
from apps.mobile_compat.identity import get_or_create_profile, sync_trusted_contacts_from_json
from apps.notifications.models import Notification
from apps.organizations.models import MembershipRole, Organization, OrganizationMembership
from apps.people.models import Person, TrustedContact

User = get_user_model()
KIN_PHONE = "+254722000002"


class NextOfKinTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_authenticate(self.admin)
        self.org = Organization.objects.create(name="Acme", slug="acme")

    def add_kin(self, person, **extra):
        return self.client.post(
            "/api/trusted-contacts/",
            {"person": str(person.id), "name": "Kin", "phone": KIN_PHONE, **extra},
            format="json",
        )

    def test_org_wearer_contact_is_linked_to_org(self):
        person = Person.objects.create(organization=self.org, first_name="Ada")
        resp = self.add_kin(person)
        self.assertEqual(resp.status_code, 201, resp.content)
        contact = TrustedContact.objects.get()
        self.assertEqual(contact.person, person)
        self.assertEqual(contact.organization, self.org)

    def test_independent_person_contact_reaches_checkin_escalation(self):
        user = User.objects.create_user(phone="+254712345678")
        person = Person.objects.create(owner_user=user, linked_user=user, first_name="Sam")
        self.assertEqual(self.add_kin(person).status_code, 201)
        # safety_engine finds check-in contacts by owner_user.
        self.assertTrue(TrustedContact.objects.filter(owner_user=user, phone=KIN_PHONE).exists())

    def test_org_wearer_with_login_reaches_checkin_escalation(self):
        user = User.objects.create_user(phone="+254712345678")
        person = Person.objects.create(organization=self.org, linked_user=user, first_name="Sam")
        self.assertEqual(self.add_kin(person).status_code, 201)
        self.assertTrue(TrustedContact.objects.filter(owner_user=user, phone=KIN_PHONE).exists())

    def test_contact_needs_phone_or_email(self):
        person = Person.objects.create(organization=self.org, first_name="Ada")
        resp = self.client.post(
            "/api/trusted-contacts/",
            {"person": str(person.id), "name": "Kin"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_org_viewer_cannot_change_but_manager_can(self):
        person = Person.objects.create(organization=self.org, first_name="Ada")
        self.add_kin(person)
        contact = TrustedContact.objects.get()
        url = f"/api/trusted-contacts/{contact.id}/"

        viewer = User.objects.create_user(phone="+254712345678")
        OrganizationMembership.objects.create(
            organization=self.org, user=viewer, role=MembershipRole.VIEWER
        )
        self.client.force_authenticate(viewer)
        self.assertEqual(self.client.get(url).status_code, 200)
        self.assertEqual(self.client.patch(url, {"name": "New"}, format="json").status_code, 403)
        self.assertEqual(self.client.delete(url).status_code, 403)

        manager = User.objects.create_user(phone="+254712345679")
        OrganizationMembership.objects.create(
            organization=self.org, user=manager, role=MembershipRole.STAFF
        )
        self.client.force_authenticate(manager)
        self.assertEqual(self.client.patch(url, {"name": "New"}, format="json").status_code, 200)

    def test_mobile_sync_keeps_admin_added_contacts_without_duplicates(self):
        user = User.objects.create_user(email="sam@example.com")
        profile, _ = get_or_create_profile("sam@example.com", email="sam@example.com")
        person = Person.objects.create(owner_user=user, linked_user=user, first_name="Sam")
        self.assertEqual(self.add_kin(person).status_code, 201)

        sync_trusted_contacts_from_json(
            profile,
            json.dumps(
                [
                    {"name": "Kin", "phone": KIN_PHONE},
                    {"name": "Friend", "phone": "+254733000003"},
                ]
            ),
        )
        self.assertEqual(TrustedContact.objects.filter(owner_user=user).count(), 2)
        self.assertEqual(TrustedContact.objects.filter(phone=KIN_PHONE).count(), 1)

        sync_trusted_contacts_from_json(profile, "[]")
        self.assertEqual(TrustedContact.objects.filter(owner_user=user).count(), 1)
        self.assertTrue(TrustedContact.objects.filter(phone=KIN_PHONE, person=person).exists())

    def test_non_admin_cannot_create_people(self):
        owner = User.objects.create_user(phone="+254712345678")
        self.client.force_authenticate(owner)
        resp = self.client.post("/api/people/", {"first_name": "Me"}, format="json")
        self.assertEqual(resp.status_code, 403)

    def test_org_manager_cannot_add_or_edit_people_but_can_add_kin(self):
        person = Person.objects.create(organization=self.org, first_name="Ada")
        manager = User.objects.create_user(phone="+254712345678")
        OrganizationMembership.objects.create(
            organization=self.org, user=manager, role=MembershipRole.OWNER
        )
        self.client.force_authenticate(manager)
        resp = self.client.post(
            "/api/people/", {"first_name": "Bo", "organization": str(self.org.id)}, format="json"
        )
        self.assertEqual(resp.status_code, 403)
        url = f"/api/people/{person.id}/"
        self.assertEqual(self.client.patch(url, {"first_name": "X"}, format="json").status_code, 403)
        self.assertEqual(self.client.delete(url).status_code, 403)
        self.assertEqual(self.add_kin(person).status_code, 201)

    def test_admin_can_set_person_owner(self):
        owner = User.objects.create_user(phone="+254712345678")
        resp = self.client.post(
            "/api/people/", {"first_name": "Kid", "owner_user": str(owner.id)}, format="json"
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertEqual(Person.objects.get(first_name="Kid").owner_user, owner)


@override_settings(BRACELET_API_SECRET="test-secret", OPENCELLID_API_KEY="")
class SosRoutingTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.org = Organization.objects.create(name="Acme", slug="acme")
        self.person = Person.objects.create(organization=self.org, first_name="Ada")
        Bracelet.objects.create(
            device_id="SB-TEST-001",
            status=BraceletStatus.IN_USE,
            organization=self.org,
            current_person=self.person,
        )

    @patch(
        "apps.alerts.services.reverse_geocode_place",
        return_value={"label": "Nairobi, Kenya", "area": "Nairobi"},
    )
    def test_admin_added_kin_and_phone_only_staff_are_alerted(self, _geo):
        self.client.force_authenticate(self.admin)
        self.client.post(
            "/api/trusted-contacts/",
            {"person": str(self.person.id), "name": "Kin", "phone": KIN_PHONE},
            format="json",
        )
        staff = User.objects.create_user(phone="+254712345678")
        OrganizationMembership.objects.create(
            organization=self.org, user=staff, role=MembershipRole.RESPONDER
        )
        self.client.force_authenticate(None)
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
            HTTP_X_BRACELET_SECRET="test-secret",
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertTrue(
            Notification.objects.filter(
                channel=Notification.Channel.SMS, recipient=KIN_PHONE
            ).exists()
        )
        self.assertTrue(
            Notification.objects.filter(channel=Notification.Channel.IN_APP, user=staff).exists()
        )
        self.assertTrue(
            Notification.objects.filter(channel=Notification.Channel.SMS, user=staff).exists()
        )
