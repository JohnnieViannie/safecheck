import json
import uuid
from typing import Dict

import requests

from .provider_config import ProviderConfig


class VoiceProvider:
    def place_checkin_call(self, phone_number: str, user_uid: str) -> Dict[str, str]:
        if ProviderConfig.provider_name() != 'africastalking':
            return {'success': False, 'error': 'Unsupported provider'}

        callback = f"{ProviderConfig.callback_base_url()}/api/webhooks/call-status/"
        payload = {
            'username': ProviderConfig.username(),
            'to': phone_number,
            'from': ProviderConfig.from_number(),
            'clientRequestId': f"{user_uid}-{uuid.uuid4().hex[:8]}",
            'callbackUrl': callback,
        }
        headers = {'apiKey': ProviderConfig.api_key(), 'Content-Type': 'application/json'}

        if not ProviderConfig.api_key() or not ProviderConfig.username():
            # Keep development flow working without credentials.
            return {'success': True, 'provider_call_id': f"mock-{uuid.uuid4().hex[:10]}", 'mocked': True}

        try:
            response = requests.post(
                f"{ProviderConfig.voice_base_url()}/call",
                data=json.dumps(payload),
                headers=headers,
                timeout=10,
            )
            if response.status_code >= 200 and response.status_code < 300:
                data = response.json()
                entries = data.get('entries', [])
                provider_call_id = entries[0].get('sessionId') if entries else None
                return {'success': True, 'provider_call_id': provider_call_id or f"at-{uuid.uuid4().hex[:10]}"}
            return {'success': False, 'error': f'Voice API error {response.status_code}: {response.text}'}
        except Exception as exc:
            return {'success': False, 'error': str(exc)}
