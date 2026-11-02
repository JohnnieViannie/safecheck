from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.accounts.phone import find_phone_issues


class Command(BaseCommand):
    help = "List stored phone numbers that would stop migration 0005. Changes nothing."

    def handle(self, *args, **options):
        issues = find_phone_issues(
            get_user_model().objects.values_list("id", "phone", "country_code")
        )
        for issue in issues:
            self.stdout.write(issue)
        if issues:
            self.stderr.write(self.style.ERROR(f"{len(issues)} issue(s). Fix these, then migrate."))
        else:
            self.stdout.write(self.style.SUCCESS("All phone numbers can be migrated."))
