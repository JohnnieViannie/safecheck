import uuid
from typing import Any, Dict, List

import requests

from .provider_config import ProviderConfig

# Africa's Talking bulk SMS recipient status codes.
_AT_STATUS_LABELS = {
    100: 'Processed',
    101: 'Sent',
    102: 'Queued',
    401: 'RiskHold',
    402: 'InvalidSenderId',
    403: 'InvalidPhoneNumber',
    404: 'UnsupportedNumberType',
    405: 'InsufficientBalance',
    406: 'UserInBlacklist',
    407: 'CouldNotRoute',
    409: 'DoNotDisturbRejection',
    500: 'InternalServerError',
    501: 'GatewayError',
    502: 'RejectedByGateway',
}


def _parse_bulk_response(data: Dict[str, Any]) -> Dict[str, str]:
    sms_data = data.get('SMSMessageData', {}) if isinstance(data, dict) else {}
    summary = (sms_data.get('Message') or '').strip()
    recipients: List[Dict[str, Any]] = sms_data.get('Recipients') or []

    if not recipients:
        return {
            'success': False,
            'error': summary or 'SMS API returned no recipients',
        }

    recipient = recipients[0]
    status_code = recipient.get('statusCode')
    status_label = _AT_STATUS_LABELS.get(status_code, f'Unknown({status_code})')
    message_id = (recipient.get('messageId') or '').strip()
    number = (recipient.get('number') or '').strip()
    cost = (recipient.get('cost') or '').strip()

    # 100 Processed, 101 Sent, 102 Queued are success paths from AT docs.
    if status_code in (100, 101, 102):
        return {
            'success': True,
            'provider_message_id': message_id or f'at-sms-{uuid.uuid4().hex[:10]}',
            'status_code': str(status_code),
            'status': status_label,
            'cost': cost,
            'number': number,
            'summary': summary,
        }

    detail = f'{status_label}'
    if number:
        detail += f' for {number}'
    if summary:
        detail += f' — {summary}'
    if status_code == 402:
        detail += (
            '. Register an approved sender ID in Africa\'s Talking: '
            'Dashboard → SMS → Alphanumerics → Request, then set AT_SENDER_ID in .env'
        )
    return {
        'success': False,
        'error': detail,
        'status_code': str(status_code) if status_code is not None else '',
        'number': number,
        'summary': summary,
    }


class SmsProvider:
    def send_sms(self, phone_number: str, message: str) -> Dict[str, str]:
        if ProviderConfig.provider_name() != 'africastalking':
            return {'success': False, 'error': 'Unsupported provider'}

        if not ProviderConfig.api_key() or not ProviderConfig.username():
            return {'success': True, 'provider_message_id': f"mock-sms-{uuid.uuid4().hex[:10]}", 'mocked': True}

        sender_id = ProviderConfig.from_number().strip()
        headers = {
            'apiKey': ProviderConfig.api_key(),
            'Accept': 'application/json',
        }

        try:
            if sender_id:
                # Bulk JSON API — requires an approved senderId.
                headers['Content-Type'] = 'application/json'
                response = requests.post(
                    ProviderConfig.sms_bulk_url(),
                    json={
                        'username': ProviderConfig.username(),
                        'phoneNumbers': [phone_number],
                        'message': message,
                        'senderId': sender_id,
                    },
                    headers=headers,
                    timeout=15,
                )
            else:
                # No approved sender yet: legacy endpoint without `from` uses AT default route.
                headers['Content-Type'] = 'application/x-www-form-urlencoded'
                response = requests.post(
                    ProviderConfig.sms_base_url(),
                    data={
                        'username': ProviderConfig.username(),
                        'to': phone_number,
                        'message': message,
                    },
                    headers=headers,
                    timeout=15,
                )

            if 200 <= response.status_code < 300:
                data = response.json()
                return _parse_bulk_response(data)
            return {'success': False, 'error': f'SMS API error {response.status_code}: {response.text}'}
        except Exception as exc:
            return {'success': False, 'error': str(exc)}
