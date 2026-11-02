"""Send and check the 6-digit codes used for account verification and password reset."""
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.db.models import F
from django.utils import timezone

from .emails import send_branded_code_email
from .models import EmailVerificationToken, PhoneVerificationToken

logger = logging.getLogger(__name__)

MAX_CODE_ATTEMPTS = 5
MAX_CODE_SENDS_PER_HOUR = 5
CODE_RESEND_COOLDOWN_SECONDS = 30


def send_code_email(*, email: str, code: str, purpose: str):
    try:
        send_branded_code_email(to_email=email, code=code, purpose=purpose)
    except Exception as exc:
        logger.exception("Failed to send %s email to %s", purpose, email)
        if settings.DEBUG:
            # Hosting SMTP may be down — print code in the server terminal so local
            # development can continue. Never returned in the API response.
            print(
                f"\n*** DEBUG {purpose} code for {email}: {code} ***\n",
                flush=True,
            )
            return
        raise RuntimeError(
            "We could not send the email right now. Check your inbox later or try again."
        ) from exc


def send_code_sms(*, phone: str, code: str, purpose: str, user=None):
    from apps.safety.services.sms_provider import SmsProvider

    minutes = getattr(settings, "EMAIL_CODE_EXPIRY_MINUTES", 15)
    result = SmsProvider().send_sms(
        phone,
        f"Your SafeBangle {purpose} code is {code}. It expires in {minutes} minutes.",
        purpose="otp",
        user=user,
    )
    if result.get("success") and not result.get("mocked"):
        return
    logger.error("Failed to send %s SMS to %s: %s", purpose, phone, result.get("error", "mocked"))
    if settings.DEBUG:
        print(f"\n*** DEBUG {purpose} code for {phone}: {code} ***\n", flush=True)
        return
    raise RuntimeError("We could not send the SMS right now. Please try again shortly.")


def can_send_code(model, user) -> bool:
    now = timezone.now()
    recent = model.objects.filter(user=user, created_at__gte=now - timedelta(hours=1))
    if recent.count() >= MAX_CODE_SENDS_PER_HOUR:
        return False
    cooldown_start = now - timedelta(seconds=CODE_RESEND_COOLDOWN_SECONDS)
    return not recent.filter(created_at__gte=cooldown_start).exists()


def consume_code(model, user, code) -> bool:
    """Check a code against the newest unused token, limiting wrong guesses."""
    token = model.objects.filter(user=user, used_at__isnull=True).order_by("-created_at").first()
    if not token or not token.is_valid or token.attempts >= MAX_CODE_ATTEMPTS:
        return False
    if not secrets.compare_digest(str(token.token), str(code)):
        model.objects.filter(pk=token.pk).update(attempts=F("attempts") + 1)
        return False
    token.used_at = timezone.now()
    token.save(update_fields=["used_at"])
    return True


def send_verification_code(user, channel: str):
    """Create a verification token and deliver it. Raises RuntimeError if delivery fails."""
    if channel == "sms":
        token = PhoneVerificationToken.create_for_user(user)
        send_code_sms(phone=user.phone, code=token.token, purpose="verification", user=user)
    else:
        token = EmailVerificationToken.create_for_user(user)
        send_code_email(email=user.email, code=token.token, purpose="email verification")
