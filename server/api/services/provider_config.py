import os


class ProviderConfig:
    @staticmethod
    def provider_name() -> str:
        return os.getenv('VOICE_SMS_PROVIDER', 'africastalking').lower()

    @staticmethod
    def voice_base_url() -> str:
        return os.getenv('AT_VOICE_BASE_URL', 'https://voice.africastalking.com')

    @staticmethod
    def sms_base_url() -> str:
        return os.getenv('AT_SMS_BASE_URL', 'https://api.africastalking.com/version1/messaging')

    @staticmethod
    def username() -> str:
        return os.getenv('AT_USERNAME', '')

    @staticmethod
    def api_key() -> str:
        return os.getenv('AT_API_KEY', '')

    @staticmethod
    def from_number() -> str:
        return os.getenv('AT_SENDER_ID', 'SafeCheck')

    @staticmethod
    def callback_base_url() -> str:
        return os.getenv('CALLBACK_BASE_URL', 'http://127.0.0.1:8080')
