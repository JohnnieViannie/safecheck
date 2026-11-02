import os


class ProviderConfig:
    @staticmethod
    def provider_name() -> str:
        """Legacy voice/SMS combined provider (voice still uses this)."""
        return os.getenv('VOICE_SMS_PROVIDER', 'africastalking').lower().strip()

    @staticmethod
    def sms_provider_name() -> str:
        """Active SMS backend: africastalking | kacyber."""
        explicit = os.getenv('SMS_PROVIDER', '').strip().lower()
        if explicit:
            return explicit
        return ProviderConfig.provider_name()

    @staticmethod
    def voice_base_url() -> str:
        return os.getenv('AT_VOICE_BASE_URL', 'https://voice.africastalking.com')

    @staticmethod
    def sms_base_url() -> str:
        return os.getenv('AT_SMS_BASE_URL', 'https://api.africastalking.com/version1/messaging')

    @staticmethod
    def sms_bulk_url() -> str:
        return os.getenv(
            'AT_SMS_BULK_URL',
            'https://api.africastalking.com/version1/messaging/bulk',
        )

    @staticmethod
    def username() -> str:
        return os.getenv('AT_USERNAME', '')

    @staticmethod
    def api_key() -> str:
        return os.getenv('AT_API_KEY', '')

    @staticmethod
    def from_number() -> str:
        # Leave unset unless Africa's Talking has approved your alphanumeric sender ID.
        return os.getenv('AT_SENDER_ID', '').strip()

    @staticmethod
    def callback_base_url() -> str:
        return os.getenv('CALLBACK_BASE_URL', 'http://127.0.0.1:8080')

    # --- KaCyber SMS ---
    # Environments (from KaCyber docs):
    #   sandbox -> https://sandbox.kacyber.africa/api/v1  (keys: kcy_sbx_...)
    #   live    -> https://kacyberpay.com/api/v1          (keys: kcy_live_...)

    _KACYBER_API_ROOTS = {
        'sandbox': 'https://sandbox.kacyber.africa/api/v1',
        'live': 'https://kacyberpay.com/api/v1',
    }

    @staticmethod
    def kacyber_env() -> str:
        explicit = os.getenv('KACYBER_ENV', '').strip().lower()
        if explicit in ('sandbox', 'live', 'production', 'prod'):
            return 'live' if explicit in ('live', 'production', 'prod') else 'sandbox'

        key = ProviderConfig.kacyber_api_key().lower()
        if key.startswith('kcy_live_'):
            return 'live'
        if key.startswith('kcy_sbx_'):
            return 'sandbox'

        # Fall back from an explicit SMS URL if present.
        url = os.getenv('KACYBER_SMS_BASE_URL', '').strip().lower()
        if 'kacyberpay.com' in url:
            return 'live'
        return 'sandbox'

    @staticmethod
    def kacyber_api_root() -> str:
        return ProviderConfig._KACYBER_API_ROOTS[ProviderConfig.kacyber_env()]

    @staticmethod
    def kacyber_sms_url() -> str:
        override = os.getenv('KACYBER_SMS_BASE_URL', '').strip()
        if override:
            return override.rstrip('/')
        return f"{ProviderConfig.kacyber_api_root().rstrip('/')}/comms/sms"

    @staticmethod
    def kacyber_app_id() -> str:
        return os.getenv('KACYBER_APP_ID', '').strip()

    @staticmethod
    def kacyber_api_key() -> str:
        return os.getenv('KACYBER_API_KEY', '').strip()

    @staticmethod
    def kacyber_sender_id() -> str:
        return os.getenv('KACYBER_SENDER_ID', 'KaCyber').strip()

    @staticmethod
    def kacyber_is_configured() -> bool:
        return bool(
            ProviderConfig.kacyber_app_id()
            and ProviderConfig.kacyber_api_key()
            and ProviderConfig.kacyber_sender_id()
        )
