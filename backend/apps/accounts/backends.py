from django.contrib.auth import get_user_model
from django.contrib.auth.backends import ModelBackend

from .phone import is_email_identifier, is_username_identifier, normalize_phone


def find_user(identifier, country_code=None):
    """Return the account for a username, phone number or email, or None."""
    User = get_user_model()
    text = str(identifier or "").strip()
    if not text:
        return None
    if is_email_identifier(text):
        return User.objects.filter(email__iexact=text).first()
    if is_username_identifier(text):
        return User.objects.filter(username__iexact=text).first()
    phone = normalize_phone(text, country_code)
    if not phone:
        return None
    return User.objects.filter(phone=phone).first()


class PhoneOrEmailBackend(ModelBackend):
    """Password login with a username, phone number or email address."""

    def authenticate(self, request, username=None, password=None, country_code=None, **kwargs):
        User = get_user_model()
        if username is None:
            username = kwargs.get(User.USERNAME_FIELD)
        if username is None or password is None:
            return None
        user = find_user(username, country_code)
        if user is None:
            # Same hashing cost as a real attempt, so response time doesn't reveal accounts.
            User().set_password(password)
            return None
        if user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None
