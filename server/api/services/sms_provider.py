import uuid
from typing import Dict

import requests

from .provider_config import ProviderConfig


class SmsProvider:
    def send_sms(self, phone_number: str, message: str) -> Dict[str, str]:
        if ProviderConfig.provider_name() != 'africastalking':
            return {'success': False, 'error': 'Unsupported provider'}

        if not ProviderConfig.api_key() or not ProviderConfig.username():
            return {'success': True, 'provider_message_id': f"mock-sms-{uuid.uuid4().hex[:10]}", 'mocked': True}

        headers = {
            'apiKey': ProviderConfig.api_key(),
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
        }
        payload = {
            'username': ProviderConfig.username(),
            'to': phone_number,
            'message': message,
            'from': ProviderConfig.from_number(),
        }
        try:
            response = requests.post(ProviderConfig.sms_base_url(), data=payload, headers=headers, timeout=10)
            if 200 <= response.status_code < 300:
                data = response.json()
                sms_data = data.get('SMSMessageData', {}) if isinstance(data, dict) else {}
                provider_message = sms_data.get('Message') or ''
                recipients = sms_data.get('Recipients', [])
                if recipients:
                    message_id = recipients[0].get('messageId')
                    return {'success': True, 'provider_message_id': message_id or f"at-sms-{uuid.uuid4().hex[:10]}"}
                return {
                    'success': False,
                    'error': f"SMS API accepted request but did not queue recipients: {provider_message or 'Unknown provider response'}",
                }
            return {'success': False, 'error': f'SMS API error {response.status_code}: {response.text}'}
        except Exception as exc:
            return {'success': False, 'error': str(exc)}
