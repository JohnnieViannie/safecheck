from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.devices.models import Bracelet, BraceletStatus
from apps.organizations.models import MembershipRole, Organization, OrganizationMembership
from apps.people.models import Person, TrustedContact

User = get_user_model()
PHONE = "+254712345678"
SEND_SMS = "apps.safety.services.sms_provider.SmsProvider.send_sms"


def payload(**extra):
    return {
        "phone": PHONE,
        "first_name": "Amina",
        "city": "Kampala",
        "date_of_birth": "1995-03-14",
        "device_id": "SB-0001",
        **extra,
    }


@patch(SEND_SMS, return_value={"success": True})
class UserListTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_authenticate(self.admin)
        self.org = Organization.objects.create(name="Acme", slug="acme")

    def list_users(self, **params):
        response = self.client.get("/api/auth/users/", {"ordering": "-created_at", **params})
        self.assertEqual(response.status_code, 200, response.content)
        return response.data["results"]

    def test_new_user_is_first_in_the_list_right_away(self, sms):
        created = self.client.post("/api/auth/users/", payload(), format="json")
        self.assertEqual(created.status_code, 201, created.content)
        self.assertEqual(self.list_users()[0]["id"], created.data["id"])

    def test_organization_member_shows_under_that_organization(self, sms):
        self.client.post(
            "/api/auth/users/", payload(organization=str(self.org.id)), format="json"
        )
        for params in ({"organization": str(self.org.id)}, {"source": "org"}):
            rows = self.list_users(**params)
            self.assertEqual([row["phone"] for row in rows], [PHONE], params)
            self.assertEqual(rows[0]["organization_name"], "Acme")
        self.assertNotIn(PHONE, [row["phone"] for row in self.list_users(source="independent")])

    def test_find_user_by_bracelet_id(self, sms):
        self.client.post("/api/auth/users/", payload(), format="json")
        self.assertEqual([row["phone"] for row in self.list_users(search="SB-0001")], [PHONE])

    def test_editing_user_updates_their_member_record(self, sms):
        created = self.client.post(
            "/api/auth/users/", payload(organization=str(self.org.id)), format="json"
        )
        response = self.client.patch(
            f"/api/auth/users/{created.data['id']}/",
            {"first_name": "Grace", "phone": "+254712345679"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        person = Person.objects.get()
        self.assertEqual(person.first_name, "Grace")
        self.assertEqual(person.phone, "+254712345679")


@patch(SEND_SMS, return_value={"success": True})
class ManageMembersTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password="x")
        self.client.force_authenticate(self.admin)
        self.org = Organization.objects.create(name="Acme", slug="acme")

    def add_member(self):
        response = self.client.post(
            "/api/auth/users/", payload(organization=str(self.org.id)), format="json"
        )
        self.assertEqual(response.status_code, 201, response.content)
        return Person.objects.get()

    def remove(self, person):
        return self.client.post(f"/api/people/{person.id}/remove-from-organization/")

    def test_removing_member_with_account_keeps_them_independent_with_bracelet(self, sms):
        person = self.add_member()
        kin = TrustedContact.objects.create(
            person=person, organization=self.org, name="Kin", phone="+254722000002"
        )
        response = self.remove(person)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.data["outcome"], "independent")
        person.refresh_from_db()
        self.assertIsNone(person.organization)
        self.assertEqual(person.owner_user, person.linked_user)
        bracelet = Bracelet.objects.get()
        self.assertEqual(bracelet.current_person, person)
        self.assertIsNone(bracelet.organization)
        kin.refresh_from_db()
        self.assertIsNone(kin.organization)
        self.assertEqual(kin.owner_user, person.linked_user)

    def test_removing_member_without_account_deletes_record_and_frees_bracelet(self, sms):
        person = Person.objects.create(organization=self.org, first_name="Old")
        bracelet = Bracelet.objects.create(
            device_id="SB-OLD",
            organization=self.org,
            current_person=person,
            status=BraceletStatus.IN_USE,
        )
        response = self.remove(person)
        self.assertEqual(response.data["outcome"], "deleted")
        self.assertFalse(Person.objects.exists())
        bracelet.refresh_from_db()
        self.assertEqual(bracelet.status, BraceletStatus.UNASSIGNED)

    def test_only_admin_can_remove_a_member(self, sms):
        person = self.add_member()
        owner = User.objects.create_user(phone="+254700000001")
        OrganizationMembership.objects.create(
            organization=self.org, user=owner, role=MembershipRole.OWNER
        )
        self.client.force_authenticate(owner)
        self.assertEqual(self.remove(person).status_code, 403)

    def test_staff_role_change_and_remove(self, sms):
        staff = User.objects.create_user(phone="+254700000002")
        membership = OrganizationMembership.objects.create(
            organization=self.org, user=staff, role=MembershipRole.STAFF
        )
        url = f"/api/organizations/{self.org.id}/members/{membership.id}/"
        self.assertEqual(self.client.patch(url, {"role": "BOSS"}, format="json").status_code, 400)
        response = self.client.patch(url, {"role": "RESPONDER"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.data["role"], "RESPONDER")
        self.assertEqual(self.client.delete(url).status_code, 204)
        self.assertFalse(self.org.memberships.exists())
        self.assertTrue(User.objects.filter(pk=staff.pk).exists())

    def test_last_owner_cannot_be_removed_or_demoted(self, sms):
        owner = User.objects.create_user(phone="+254700000003")
        membership = OrganizationMembership.objects.create(
            organization=self.org, user=owner, role=MembershipRole.OWNER
        )
        url = f"/api/organizations/{self.org.id}/members/{membership.id}/"
        self.assertEqual(self.client.delete(url).status_code, 400)
        self.assertEqual(self.client.patch(url, {"role": "STAFF"}, format="json").status_code, 400)

    def test_viewer_cannot_change_staff(self, sms):
        viewer = User.objects.create_user(phone="+254700000004")
        membership = OrganizationMembership.objects.create(
            organization=self.org, user=viewer, role=MembershipRole.VIEWER
        )
        self.client.force_authenticate(viewer)
        url = f"/api/organizations/{self.org.id}/members/{membership.id}/"
        self.assertEqual(self.client.delete(url).status_code, 403)

    def test_removing_a_device_frees_it(self, sms):
        person = self.add_member()
        bracelet = Bracelet.objects.get()
        response = self.client.post(f"/api/bracelets/{bracelet.id}/unassign/")
        self.assertEqual(response.status_code, 200, response.content)
        bracelet.refresh_from_db()
        self.assertIsNone(bracelet.current_person)
        self.assertEqual(bracelet.status, BraceletStatus.UNASSIGNED)
        self.assertIsNotNone(person.pk)
