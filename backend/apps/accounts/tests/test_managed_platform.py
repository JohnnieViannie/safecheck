import io
import shutil
import tempfile
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from PIL import Image
from rest_framework.test import APIClient

from apps.alerts.models import Alert
from apps.devices.models import Bracelet, BraceletStatus
from apps.organizations.models import MembershipRole, Organization, OrganizationMembership
from apps.people.models import Person, TrustedContact

User = get_user_model()
PHONE = "+254712345678"
PASSWORD = "Str0ng-Passw0rd!"
SEND_SMS = "apps.safety.services.sms_provider.SmsProvider.send_sms"


def add_user_payload(**extra):
    return {
        "phone": PHONE,
        "first_name": "Amina",
        "city": "Kampala",
        "date_of_birth": "1995-03-14",
        "device_id": "SB-0001",
        **extra,
    }


@patch(SEND_SMS, return_value={"success": True})
class ClosedRegistrationTests(TestCase):
    def test_register_is_refused(self, sms):
        cache.clear()
        resp = APIClient().post(
            "/api/auth/register/", {"phone": PHONE, "password": PASSWORD}, format="json"
        )
        self.assertEqual(resp.status_code, 403)
        self.assertFalse(User.objects.exists())
        sms.assert_not_called()


class UsernameTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_generated_from_name_and_unique(self):
        first = User.objects.create_user(phone=PHONE, first_name="Am\u00edna Rose")
        second = User.objects.create_user(phone="+254712345679", first_name="Am\u00edna Rose")
        self.assertRegex(first.username, r"^aminarose\d{4}$")
        self.assertNotEqual(first.username, second.username)

    def test_name_without_letters_falls_back(self):
        self.assertRegex(User.objects.create_user(phone=PHONE).username, r"^user\d{4}$")

    def test_username_logs_in_in_any_case_alongside_phone_and_email(self):
        user = User.objects.create_user(
            phone=PHONE, email="a@example.com", password=PASSWORD, phone_verified=True
        )
        for identifier in (user.username.upper(), PHONE, "a@example.com"):
            resp = APIClient().post(
                "/api/auth/login/", {"identifier": identifier, "password": PASSWORD}, format="json"
            )
            self.assertEqual(resp.status_code, 200, identifier)

    @patch(SEND_SMS, return_value={"success": True})
    def test_set_password_by_username_uses_the_phone(self, sms):
        user = User.objects.create_user(phone=PHONE, first_name="Amina")
        client = APIClient()
        resp = client.post(
            "/api/auth/forgot-password/", {"identifier": user.username}, format="json"
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(sms.call_args.args[0], PHONE)
        code = sms.call_args.args[1].split("code is ")[1][:6]
        resp = client.post(
            "/api/auth/reset-password/",
            {"identifier": user.username, "code": code, "password": PASSWORD},
            format="json",
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        user.refresh_from_db()
        self.assertTrue(user.phone_verified)
        self.assertTrue(user.has_usable_password())


@patch(SEND_SMS, return_value={"success": True})
class AddUserTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password=PASSWORD)
        self.client.force_authenticate(self.admin)
        self.org = Organization.objects.create(name="Acme", slug="acme")

    def add(self, **extra):
        return self.client.post("/api/auth/users/", add_user_payload(**extra), format="json")

    def test_registers_person_and_bracelet_together(self, sms):
        resp = self.add(address="Plot 4")
        self.assertEqual(resp.status_code, 201, resp.content)
        user = User.objects.get(phone=PHONE)
        self.assertEqual(user.registered_by, self.admin)
        self.assertEqual(user.city, "Kampala")
        self.assertFalse(user.has_usable_password())
        person = Person.objects.get(linked_user=user)
        self.assertEqual(person.owner_user, user)
        bracelet = Bracelet.objects.get(device_id="SB-0001")
        self.assertEqual(bracelet.current_person, person)
        self.assertEqual(bracelet.status, BraceletStatus.IN_USE)
        self.assertEqual(resp.data["username"], user.username)
        self.assertEqual(resp.data["device_id"], "SB-0001")
        self.assertTrue(resp.data["sms_sent"])
        self.assertIn(user.username, sms.call_args.args[1])
        self.assertIn("/forgot-password", sms.call_args.args[1])

    def test_device_and_city_are_required(self, sms):
        for field in ("device_id", "city", "date_of_birth"):
            payload = add_user_payload()
            del payload[field]
            resp = self.client.post("/api/auth/users/", payload, format="json")
            self.assertEqual(resp.status_code, 400)
            self.assertIn(field, resp.data["details"])
        self.assertFalse(User.objects.filter(phone=PHONE).exists())
        sms.assert_not_called()

    def test_device_in_use_rejected_and_nothing_saved(self, sms):
        self.assertEqual(self.add().status_code, 201)
        resp = self.add(phone="+254712345679")
        self.assertEqual(resp.status_code, 400)
        self.assertIn("device_id", resp.data["details"])
        self.assertFalse(User.objects.filter(phone="+254712345679").exists())

    def test_spare_device_is_reused_and_deactivated_refused(self, sms):
        Bracelet.objects.create(device_id="SB-SPARE", status=BraceletStatus.UNASSIGNED)
        self.assertEqual(self.add(device_id="sb-spare").status_code, 201)
        Bracelet.objects.create(device_id="SB-DEAD", status=BraceletStatus.DEACTIVATED)
        self.assertEqual(
            self.add(phone="+254712345679", device_id="SB-DEAD").status_code, 400
        )

    def test_organization_member(self, sms):
        resp = self.add(organization=str(self.org.id))
        self.assertEqual(resp.status_code, 201, resp.content)
        person = Person.objects.get(phone=PHONE)
        self.assertEqual(person.organization, self.org)
        self.assertIsNone(person.owner_user)
        self.assertEqual(Bracelet.objects.get().organization, self.org)

    def test_failed_sms_keeps_user_and_reports(self, sms):
        sms.return_value = {"success": False, "error": "down"}
        resp = self.add()
        self.assertEqual(resp.status_code, 201)
        self.assertFalse(resp.data["sms_sent"])
        self.assertEqual(resp.data["sms_error"], "down")

    def test_non_staff_forbidden(self, sms):
        self.client.force_authenticate(User.objects.create_user(phone="+254712345679"))
        self.assertEqual(self.add().status_code, 403)

    def test_independent_filter(self, sms):
        self.add()
        resp = self.client.get("/api/auth/users/", {"source": "independent"})
        self.assertIn(PHONE, [row["phone"] for row in resp.data["results"]])


@patch(SEND_SMS, return_value={"success": True})
class ManageUserTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password=PASSWORD)
        self.client.force_authenticate(self.admin)

    def make_user(self):
        resp = self.client.post("/api/auth/users/", add_user_payload(), format="json")
        self.assertEqual(resp.status_code, 201, resp.content)
        return User.objects.get(phone=PHONE)

    def replace(self, user, **data):
        return self.client.post(f"/api/auth/users/{user.id}/replace-device/", data, format="json")

    def test_detail_shows_device_history_and_person(self, sms):
        user = self.make_user()
        resp = self.client.get(f"/api/auth/users/{user.id}/")
        self.assertEqual(resp.data["current_device"]["device_id"], "SB-0001")
        self.assertEqual(len(resp.data["device_history"]), 1)
        self.assertTrue(resp.data["person_id"])
        self.assertEqual(resp.data["registered_by_name"], "admin@example.com")

    def test_replace_broken_device_deactivates_old_and_records_history(self, sms):
        user = self.make_user()
        resp = self.replace(user, device_id="SB-0002", old_device_state="broken", reason="Cracked")
        self.assertEqual(resp.status_code, 200, resp.content)
        old = Bracelet.objects.get(device_id="SB-0001")
        self.assertEqual(old.status, BraceletStatus.DEACTIVATED)
        self.assertIsNone(old.current_person)
        self.assertIsNone(old.owner_user)
        self.assertEqual(resp.data["current_device"]["device_id"], "SB-0002")
        self.assertEqual(len(resp.data["device_history"]), 2)

    def test_replace_spare_keeps_old_device_usable(self, sms):
        user = self.make_user()
        self.assertEqual(self.replace(user, device_id="SB-0002").status_code, 200)
        self.assertEqual(Bracelet.objects.get(device_id="SB-0001").status, BraceletStatus.UNASSIGNED)

    def test_replace_rejects_same_and_taken_devices(self, sms):
        user = self.make_user()
        self.assertEqual(self.replace(user, device_id="sb-0001").status_code, 400)
        other = Person.objects.create(first_name="Other")
        Bracelet.objects.create(device_id="SB-TAKEN", current_person=other)
        self.assertEqual(self.replace(user, device_id="SB-TAKEN").status_code, 400)
        self.assertEqual(Bracelet.objects.get(device_id="SB-0001").current_person.linked_user, user)

    def test_add_device_for_account_without_one(self, sms):
        user = User.objects.create_user(phone=PHONE, first_name="Old")
        self.assertFalse(
            self.client.get(f"/api/auth/users/{user.id}/").data["has_device"]
        )
        resp = self.replace(user, device_id="SB-0009")
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertEqual(resp.data["current_device"]["device_id"], "SB-0009")

    def test_delete_frees_bracelet_keeps_alert_and_removes_people(self, sms):
        user = self.make_user()
        person = Person.objects.get(linked_user=user)
        TrustedContact.objects.create(person=person, owner_user=user, name="Kin", phone="+254722000002")
        bracelet = Bracelet.objects.get()
        alert = Alert.objects.create(
            bracelet=bracelet,
            person=person,
            owner_user=user,
            alert_code="SOS",
            received_at=timezone.now(),
        )
        self.assertEqual(self.client.delete(f"/api/auth/users/{user.id}/").status_code, 204)
        self.assertFalse(User.objects.filter(phone=PHONE).exists())
        self.assertFalse(Person.objects.exists())
        self.assertFalse(TrustedContact.objects.exists())
        bracelet.refresh_from_db()
        self.assertEqual(bracelet.status, BraceletStatus.UNASSIGNED)
        self.assertIsNone(bracelet.owner_user)
        alert.refresh_from_db()
        self.assertIsNone(alert.person)
        resp = self.client.post(
            "/api/auth/users/", add_user_payload(phone="+254712345679"), format="json"
        )
        self.assertEqual(resp.status_code, 201, resp.content)

    def test_org_managers_cannot_register_or_manage_bracelets(self, sms):
        org = Organization.objects.create(name="Acme", slug="acme")
        bracelet = Bracelet.objects.create(device_id="SB-ORG", organization=org)
        owner = User.objects.create_user(phone="+254712345679")
        OrganizationMembership.objects.create(
            organization=org, user=owner, role=MembershipRole.OWNER
        )
        self.client.force_authenticate(owner)
        self.assertEqual(self.client.get("/api/bracelets/").status_code, 200)
        resp = self.client.post(
            "/api/bracelets/", {"device_id": "SB-X", "organization": str(org.id)}, format="json"
        )
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(
            self.client.post(f"/api/bracelets/{bracelet.id}/deactivate/").status_code, 403
        )
        self.assertEqual(
            self.client.patch(
                f"/api/bracelets/{bracelet.id}/", {"notes": "x"}, format="json"
            ).status_code,
            403,
        )


def image_bytes(fmt="JPEG", size=(32, 32), exif=None):
    buffer = io.BytesIO()
    kwargs = {"exif": exif} if exif else {}
    Image.new("RGB", size, "red").save(buffer, format=fmt, **kwargs)
    return buffer.getvalue()


class PhotoTests(TestCase):
    def setUp(self):
        self.media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.media, ignore_errors=True)
        override = override_settings(MEDIA_ROOT=self.media)
        override.enable()
        self.addCleanup(override.disable)
        self.client = APIClient()
        self.user = User.objects.create_user(phone=PHONE, first_name="Amina")
        self.client.force_authenticate(self.user)

    def upload(self, content, name="me.jpg", kind="image/jpeg"):
        return self.client.post(
            "/api/auth/me/photo/",
            {"photo": SimpleUploadedFile(name, content, content_type=kind)},
            format="multipart",
        )

    def test_upload_replace_and_remove(self):
        resp = self.upload(image_bytes())
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertTrue(resp.data["photo_url"].startswith("http"))
        self.assertNotIn("me.jpg", resp.data["photo_url"])
        self.user.refresh_from_db()
        first = self.user.photo.name
        self.assertEqual(self.upload(image_bytes("PNG"), "x.png", "image/png").status_code, 200)
        self.user.refresh_from_db()
        self.assertNotEqual(self.user.photo.name, first)
        resp = self.client.delete("/api/auth/me/photo/")
        self.assertEqual(resp.status_code, 200)
        self.assertIsNone(resp.data["photo_url"])

    def test_location_data_is_stripped(self):
        exif = Image.Exif()
        exif[0x010F] = "SecretCamera"
        self.assertEqual(self.upload(image_bytes(exif=exif)).status_code, 200)
        self.user.refresh_from_db()
        with Image.open(self.user.photo.path) as saved:
            self.assertEqual(dict(saved.getexif()), {})

    def test_large_pictures_are_shrunk(self):
        self.assertEqual(self.upload(image_bytes(size=(2000, 1000))).status_code, 200)
        self.user.refresh_from_db()
        with Image.open(self.user.photo.path) as saved:
            self.assertEqual(max(saved.size), 1024)

    def test_rejects_non_images_and_oversized(self):
        self.assertEqual(self.upload(b"<script>alert(1)</script>").status_code, 400)
        gif = io.BytesIO()
        Image.new("RGB", (4, 4)).save(gif, format="GIF")
        self.assertEqual(self.upload(gif.getvalue(), "a.gif", "image/gif").status_code, 400)
        self.assertEqual(self.upload(b"x" * (5 * 1024 * 1024 + 1)).status_code, 400)
        self.assertEqual(self.client.post("/api/auth/me/photo/", {}, format="multipart").status_code, 400)

    def test_self_edit_address(self):
        resp = self.client.patch(
            "/api/auth/me/", {"city": "Nairobi", "address": "Plot 9"}, format="json"
        )
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertEqual(resp.data["city"], "Nairobi")
        self.assertEqual(resp.data["address"], "Plot 9")

    def test_only_admin_can_change_someone_elses_photo(self):
        other = User.objects.create_user(phone="+254712345679")
        url = f"/api/auth/users/{other.id}/photo/"
        payload = {"photo": SimpleUploadedFile("a.jpg", image_bytes(), content_type="image/jpeg")}
        self.assertEqual(self.client.post(url, payload, format="multipart").status_code, 403)
        self.client.force_authenticate(User.objects.create_superuser(email="a@b.co", password="x"))
        payload = {"photo": SimpleUploadedFile("a.jpg", image_bytes(), content_type="image/jpeg")}
        self.assertEqual(self.client.post(url, payload, format="multipart").status_code, 200)


@patch(SEND_SMS, return_value={"success": True})
class RegistrarTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email="admin@example.com", password=PASSWORD)
        self.client.force_authenticate(self.admin)

    def invite(self, phone="+254700000001"):
        return self.client.post(
            "/api/auth/staff/invite/", {"first_name": "Reg", "phone": phone}, format="json"
        )

    def make_registrar(self):
        self.assertEqual(self.invite().status_code, 201)
        return User.objects.get(phone="+254700000001")

    def test_invite_creates_pending_registrar_and_texts_login(self, sms):
        resp = self.invite()
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertTrue(resp.data["pending"])
        user = User.objects.get(phone="+254700000001")
        self.assertTrue(user.is_registrar)
        self.assertFalse(user.is_platform_admin)
        self.assertIn(user.username, sms.call_args.args[1])
        self.assertEqual(len(self.client.get("/api/auth/staff/").data), 1)
        self.assertEqual(self.client.post(f"/api/auth/staff/{user.id}/resend/").status_code, 200)

    def test_invite_refuses_existing_staff_and_admins(self, sms):
        self.invite()
        self.assertEqual(self.invite().status_code, 400)
        self.admin.phone = "+254700000002"
        self.admin.save()
        self.assertEqual(self.invite("+254700000002").status_code, 400)

    def test_existing_account_gets_role_and_remove_role_works(self, sms):
        existing = User.objects.create_user(phone="+254700000003")
        self.assertEqual(self.invite("+254700000003").status_code, 201)
        existing.refresh_from_db()
        self.assertTrue(existing.is_registrar)
        resp = self.client.post(f"/api/auth/staff/{existing.id}/remove-role/")
        self.assertEqual(resp.status_code, 200)
        existing.refresh_from_db()
        self.assertEqual(existing.platform_role, "")
        self.assertEqual(self.client.post(f"/api/auth/staff/{existing.id}/resend/").status_code, 404)

    def test_registrar_manages_only_their_own_people(self, sms):
        registrar = self.make_registrar()
        other = User.objects.create_user(phone="+254700000009")
        org = Organization.objects.create(name="Acme", slug="acme")
        self.client.force_authenticate(registrar)

        # Can pick an organization and register into it.
        self.assertEqual(self.client.get("/api/organizations/").status_code, 200)
        resp = self.client.post(
            "/api/auth/users/", add_user_payload(organization=str(org.id)), format="json"
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        mine = User.objects.get(phone=PHONE)
        self.assertEqual(mine.registered_by, registrar)
        person = Person.objects.get(linked_user=mine)

        # Sees and edits only their own.
        phones = [row["phone"] for row in self.client.get("/api/auth/users/").data["results"]]
        self.assertEqual(phones, [PHONE])
        self.assertEqual(self.client.get(f"/api/auth/users/{other.id}/").status_code, 404)
        url = f"/api/auth/users/{mine.id}/"
        self.assertEqual(self.client.patch(url, {"city": "Gulu"}, format="json").status_code, 200)
        resp = self.client.post(f"{url}replace-device/", {"device_id": "SB-0002"}, format="json")
        self.assertEqual(resp.status_code, 200, resp.content)
        resp = self.client.post(
            "/api/trusted-contacts/",
            {"person": str(person.id), "name": "Kin", "phone": "+254722000002"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.content)

        # Admin-only actions stay closed.
        self.assertEqual(self.client.delete(url).status_code, 403)
        self.assertEqual(self.client.post(f"{url}block/").status_code, 403)
        self.assertEqual(self.client.patch(url, {"is_active": False}, format="json").status_code, 403)
        self.assertEqual(self.client.get("/api/auth/staff/").status_code, 403)
        resp = self.client.post(
            "/api/auth/staff/invite/", {"first_name": "X", "phone": "+254700000005"}, format="json"
        )
        self.assertEqual(resp.status_code, 403)
        resp = self.client.post(
            "/api/organizations/onboard/",
            {"name": "X", "owner_first_name": "Y", "owner_phone": "+254700000006"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(self.client.patch(f"/api/organizations/{org.id}/", {"name": "Z"}, format="json").status_code, 404)
        self.assertEqual(self.client.get(f"/api/organizations/{org.id}/members/").status_code, 404)
        self.assertEqual(self.client.get("/api/sms-messages/").status_code, 403)

    def test_regular_user_has_no_staff_access(self, sms):
        self.client.force_authenticate(User.objects.create_user(phone="+254700000008"))
        self.assertEqual(self.client.get("/api/auth/users/").status_code, 403)
        self.assertEqual(self.client.get("/api/auth/staff/").status_code, 403)
