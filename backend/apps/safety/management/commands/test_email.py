from django.core.management.base import BaseCommand

from apps.safety.services.email_config import EmailConfig
from apps.safety.services.email_provider import EmailProvider
from apps.safety.services.verification_store import generate_code


class Command(BaseCommand):
    help = "Send a test verification email and print SMTP configuration (no secrets)."

    def add_arguments(self, parser):
        parser.add_argument("email", help="Recipient email address")

    def handle(self, *args, **options):
        to_email = options["email"].strip().lower()
        configured = EmailConfig.is_configured()

        self.stdout.write(f"Recipient: {to_email}")
        self.stdout.write(f"SMTP configured: {configured}")
        if configured:
            self.stdout.write(f"  EMAIL_HOST: {EmailConfig.host()}")
            self.stdout.write(f"  EMAIL_PORT: {EmailConfig.port()}")
            self.stdout.write(f"  EMAIL_USE_TLS: {EmailConfig.use_tls()}")
            self.stdout.write(f"  EMAIL_USE_SSL: {EmailConfig.use_ssl()}")
            self.stdout.write(f"  EMAIL_HOST_USER: {EmailConfig.username()}")
            self.stdout.write(f"  EMAIL_FROM: {EmailConfig.from_address()}")
            self.stdout.write(f"  From header: {EmailConfig.formatted_from()}")
        else:
            self.stderr.write(
                "Email is not configured. Set EMAIL_HOST, EMAIL_HOST_USER, "
                "EMAIL_HOST_PASSWORD, and EMAIL_FROM in backend/.env"
            )
            return

        code = generate_code()
        self.stdout.write(f"Sending test code {code} ...")

        result = EmailProvider().send_verification_code(to_email, code, purpose="verify")
        if result.get("success"):
            self.stdout.write(self.style.SUCCESS("SMTP accepted the message."))
            self.stdout.write(
                "If the inbox is empty, check Spam/Promotions and verify "
                "EMAIL_FROM matches your SMTP provider (see backend/.env.example)."
            )
        else:
            self.stderr.write(self.style.ERROR(result.get("error", "Send failed")))
