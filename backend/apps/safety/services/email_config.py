import os


def _env_bool(key: str, default: str = 'false') -> bool:
    return os.getenv(key, default).strip().lower() in ('1', 'true', 'yes', 'on')


class EmailConfig:
    """SMTP settings for email verification (read from server/.env)."""

    @staticmethod
    def host() -> str:
        return os.getenv('EMAIL_HOST', '').strip()

    @staticmethod
    def port() -> int:
        return int(os.getenv('EMAIL_PORT', '587') or '587')

    @staticmethod
    def use_tls() -> bool:
        return _env_bool('EMAIL_USE_TLS', 'true')

    @staticmethod
    def use_ssl() -> bool:
        return _env_bool('EMAIL_USE_SSL', 'false')

    @staticmethod
    def username() -> str:
        return os.getenv('EMAIL_HOST_USER', '').strip()

    @staticmethod
    def password() -> str:
        return os.getenv('EMAIL_HOST_PASSWORD', '').strip()

    @staticmethod
    def from_address() -> str:
        configured = os.getenv('EMAIL_FROM', '').strip()
        if configured:
            return configured
        return EmailConfig.username()

    @staticmethod
    def from_name() -> str:
        return os.getenv('EMAIL_FROM_NAME', 'SafeBangle').strip() or 'SafeBangle'

    @staticmethod
    def verification_subject() -> str:
        return os.getenv(
            'EMAIL_VERIFICATION_SUBJECT',
            'Your SafeBangle verification code',
        ).strip()

    @staticmethod
    def password_reset_subject() -> str:
        return os.getenv(
            'EMAIL_PASSWORD_RESET_SUBJECT',
            'Reset your SafeBangle password',
        ).strip()

    @staticmethod
    def verification_expiry_minutes() -> int:
        raw = os.getenv('EMAIL_VERIFICATION_EXPIRY_MINUTES', '10').strip()
        try:
            return max(1, int(raw))
        except ValueError:
            return 10

    @staticmethod
    def formatted_from() -> str:
        address = EmailConfig.from_address()
        name = EmailConfig.from_name()
        if name and address:
            return f'{name} <{address}>'
        return address

    @staticmethod
    def is_configured() -> bool:
        return bool(
            EmailConfig.host()
            and EmailConfig.username()
            and EmailConfig.password()
            and EmailConfig.from_address()
        )
