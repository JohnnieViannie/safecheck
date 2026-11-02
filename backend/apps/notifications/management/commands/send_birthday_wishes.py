from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.notifications.birthdays import is_birthday, local_now
from apps.notifications.models import BirthdayGreeting
from apps.notifications.sms_text import birthday_sms
from apps.safety.services.sms_provider import SmsProvider

SEND_FROM_HOUR = 8
MAX_ATTEMPTS = 3


class Command(BaseCommand):
    help = "Send birthday wishes by SMS. Run hourly; each person gets one wish a year."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true", help="List wishes without sending.")

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        now = timezone.now()
        sent = failed = 0
        people = (
            get_user_model()
            .objects.filter(
                is_active=True,
                is_muted=False,
                date_of_birth__isnull=False,
                phone__isnull=False,
            )
            .exclude(phone="")
        )
        for user in people:
            local = local_now(user, now)
            if local.hour < SEND_FROM_HOUR or not is_birthday(user.date_of_birth, local.date()):
                continue
            if dry_run:
                greeting = BirthdayGreeting.objects.filter(user=user, year=local.year).first()
                if not greeting or greeting.status != BirthdayGreeting.Status.SENT:
                    self.stdout.write(f"[dry-run] Would wish {user.username} a happy birthday")
                continue

            greeting, _ = BirthdayGreeting.objects.get_or_create(user=user, year=local.year)
            if greeting.status == BirthdayGreeting.Status.SENT or greeting.attempts >= MAX_ATTEMPTS:
                continue
            message = birthday_sms(user.first_name, user.id.int + local.year)
            result = SmsProvider().send_sms(user.phone, message, purpose="birthday", user=user)
            greeting.attempts += 1
            if result.get("success") and not result.get("mocked"):
                greeting.status = BirthdayGreeting.Status.SENT
                greeting.sent_at = timezone.now()
                greeting.error = ""
                sent += 1
            else:
                greeting.status = BirthdayGreeting.Status.FAILED
                greeting.error = (result.get("error") or "SMS is not configured.")[:500]
                failed += 1
            greeting.save()
        self.stdout.write(f"Birthday wishes sent: {sent}, failed: {failed}")
