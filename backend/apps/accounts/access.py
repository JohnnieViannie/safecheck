"""Getting people into accounts staff created for them."""
from django.conf import settings

from apps.notifications.sms_text import gsm_safe


def send_access_sms(user, intro: str) -> tuple[bool, str]:
    """Text someone their username and how to get in. Returns (sent, error)."""
    from apps.safety.services.sms_provider import SmsProvider

    if not user.phone:
        return False, "This account has no phone number."
    if user.has_usable_password():
        link = f"Log in: {settings.FRONTEND_URL}/login"
    else:
        link = f"Set password: {settings.FRONTEND_URL}/forgot-password"
    message = f"{gsm_safe(intro)} Username: {user.username}. {link}"
    result = SmsProvider().send_sms(user.phone, message, purpose="invite", user=user)
    if result.get("success") and not result.get("mocked"):
        return True, ""
    return False, result.get("error") or "SMS is not configured."
