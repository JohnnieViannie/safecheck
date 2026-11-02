from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import User
from apps.alerts.models import Alert, AlertCode
from apps.alerts.services import AlertEngine
from apps.devices.models import Bracelet, BraceletStatus
from apps.devices.services import BraceletAssignmentService
from apps.incidents.models import IncidentStatus
from apps.incidents.services import IncidentService
from apps.organizations.models import MembershipRole, OrganizationMembership
from apps.organizations.services import OrganizationService
from apps.people.models import Person, TrustedContact


class Command(BaseCommand):
    help = "Seed demo platform admin, organization, people, bracelets, alerts, incidents"

    def handle(self, *args, **options):
        admin, created = User.objects.get_or_create(
            email="admin@safebangle.local",
            defaults={
                "first_name": "Platform",
                "last_name": "Admin",
                "is_platform_admin": True,
                "is_staff": True,
                "is_superuser": True,
                "email_verified": True,
            },
        )
        if created or not admin.has_usable_password():
            admin.set_password("Admin123!")
            admin.save()
        self.stdout.write(f"Platform admin: {admin.email} / Admin123!")

        org_admin, created = User.objects.get_or_create(
            email="orgadmin@demo.local",
            defaults={
                "first_name": "Org",
                "last_name": "Admin",
                "phone": "+254700000001",
                "account_type": "organization",
                "email_verified": True,
            },
        )
        if created or not org_admin.has_usable_password():
            org_admin.set_password("Demo123!")
            org_admin.save()

        responder, created = User.objects.get_or_create(
            email="responder@demo.local",
            defaults={
                "first_name": "Sam",
                "last_name": "Responder",
                "phone": "+254700000002",
                "email_verified": True,
            },
        )
        if created or not responder.has_usable_password():
            responder.set_password("Demo123!")
            responder.save()

        individual, created = User.objects.get_or_create(
            email="individual@demo.local",
            defaults={
                "first_name": "Alex",
                "last_name": "Individual",
                "phone": "+254700000003",
                "account_type": "individual",
                "email_verified": True,
            },
        )
        if created or not individual.has_usable_password():
            individual.set_password("Demo123!")
            individual.save()

        from apps.organizations.models import Organization

        org = Organization.objects.filter(slug="demo-ngo").first()
        if not org:
            org = OrganizationService.create_organization(
                name="Demo NGO",
                owner=org_admin,
                description="Demonstration organization",
                email="hello@demo.local",
            )
            # fix slug
            org.slug = "demo-ngo"
            org.save(update_fields=["slug"])
        else:
            OrganizationMembership.objects.update_or_create(
                organization=org,
                user=org_admin,
                defaults={"role": MembershipRole.OWNER, "is_active": True},
            )

        OrganizationMembership.objects.update_or_create(
            organization=org,
            user=responder,
            defaults={"role": MembershipRole.RESPONDER, "is_active": True},
        )

        for code, label, sev in [
            ("SOS", "Emergency SOS", "critical"),
            ("TEST", "Test alert", "info"),
            ("HELP", "Help request", "warning"),
        ]:
            AlertCode.objects.get_or_create(
                code=code, defaults={"label": label, "severity": sev}
            )

        people_data = [
            ("Sarah", "Njeri", "sarah@beneficiary.local"),
            ("John", "Otieno", "john@beneficiary.local"),
            ("Mary", "Wanjiku", "mary@beneficiary.local"),
        ]
        people = []
        for first, last, email in people_data:
            p, _ = Person.objects.get_or_create(
                organization=org,
                email=email,
                defaults={"first_name": first, "last_name": last, "phone": "+254711000000"},
            )
            people.append(p)

        for i, person in enumerate(people, start=1):
            device_id = f"SB-00{i:04d}"
            b, _ = Bracelet.objects.get_or_create(
                device_id=device_id,
                defaults={
                    "serial_number": f"SN-{i:05d}",
                    "status": BraceletStatus.INVENTORY,
                    "organization": org,
                },
            )
            if not b.current_person:
                BraceletAssignmentService.assign(b, person, assigned_by=org_admin)

        TrustedContact.objects.get_or_create(
            organization=org,
            email="contact@demo.local",
            defaults={
                "name": "Org Emergency Desk",
                "phone": "+254700000099",
                "relationship": "Security",
                "priority": 1,
            },
        )

        # Individual person + bracelet
        ind_person, _ = Person.objects.get_or_create(
            owner_user=individual,
            first_name="Alex",
            defaults={"last_name": "Individual", "email": individual.email},
        )
        ind_b, _ = Bracelet.objects.get_or_create(
            device_id="SB-IND-0001",
            defaults={
                "serial_number": "SN-IND-1",
                "status": BraceletStatus.ACTIVATED,
                "owner_user": individual,
            },
        )
        if not ind_b.current_person:
            BraceletAssignmentService.assign(ind_b, ind_person, assigned_by=individual)

        TrustedContact.objects.get_or_create(
            owner_user=individual,
            email="friend@demo.local",
            defaults={
                "name": "Trusted Friend",
                "phone": "+254700000088",
                "relationship": "Friend",
                "person": ind_person,
            },
        )

        # Sample alert via engine
        result = AlertEngine.process_inbound(
            text="SB|SB-000001|SOS|-1.292100|36.821900",
            sender="+254700111222",
            provider_message_id="seed-msg-1",
            date=timezone.now().isoformat(),
            raw_payload={"seed": True},
        )
        self.stdout.write(f"Sample alert: {result}")

        # Second distinct alert
        AlertEngine.process_inbound(
            text="SB|SB-000002|HELP|-1.300000|36.800000",
            sender="+254700111223",
            provider_message_id="seed-msg-2",
            date=timezone.now().isoformat(),
            raw_payload={"seed": True},
        )

        self.stdout.write(self.style.SUCCESS("Demo data ready."))
        self.stdout.write("  admin@safebangle.local / Admin123!")
        self.stdout.write("  orgadmin@demo.local / Demo123!")
        self.stdout.write("  responder@demo.local / Demo123!")
        self.stdout.write("  individual@demo.local / Demo123!")
