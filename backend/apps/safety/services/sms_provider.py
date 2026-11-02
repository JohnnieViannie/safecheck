import re
import logging
import uuid
from typing import Any, Dict, List

import requests

from .provider_config import ProviderConfig

logger = logging.getLogger(__name__)

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


def _to_kacyber_msisdn(phone_number: str) -> str:
    """KaCyber expects digits only, e.g. 256790221891 (no +)."""
    return ''.join(ch for ch in (phone_number or '') if ch.isdigit())


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


def _parse_kacyber_response(data: Dict[str, Any], http_status: int) -> Dict[str, str]:
    if not isinstance(data, dict):
        return {
            'success': False,
            'error': f'KaCyber SMS unexpected response (HTTP {http_status})',
        }

    success_raw = data.get('success')
    success = str(success_raw).strip().lower() in ('true', '1', 'yes')
    reference = (data.get('kacyberReference') or '').strip()
    status = (data.get('status') or '').strip()
    total_sent = data.get('totalSent')
    total_failed = data.get('totalFailed') or 0
    failed = data.get('failedRecipients') or []

    if success and (total_sent is None or int(total_sent) > 0):
        result: Dict[str, str] = {
            'success': True,
            'provider_message_id': reference or f'kc-sms-{uuid.uuid4().hex[:10]}',
            'status': status or 'sent',
            'cost': str(data.get('totalAmount') or ''),
        }
        if total_failed:
            result['partial_failure'] = str(total_failed)
            if failed:
                first = failed[0] if isinstance(failed, list) else {}
                reason = (first.get('reason') or '').strip() if isinstance(first, dict) else ''
                if reason:
                    result['warning'] = reason
        return result

    error_bits = []
    code = data.get('code') or data.get('errorCode')
    message = data.get('message') or data.get('error') or data.get('detail')
    if code:
        error_bits.append(str(code))
    if message:
        error_bits.append(str(message))
    if (
        str(code).upper() == 'KC01'
        or 'credential' in str(message).lower()
        or 'api key' in str(message).lower()
    ):
        error_bits.append(
            'Confirm KACYBER_APP_ID + KACYBER_API_KEY match the same KaCyber app, '
            'and KACYBER_ENV matches the key (sandbox=kcy_sbx_ / live=kcy_live_).'
        )
    if failed and isinstance(failed, list):
        first = failed[0] if failed else {}
        if isinstance(first, dict):
            msisdn = first.get('msisdn') or ''
            reason = first.get('reason') or ''
            if msisdn or reason:
                error_bits.append(f'{msisdn}: {reason}'.strip(': '))
    if not error_bits:
        error_bits.append(f'KaCyber SMS failed (HTTP {http_status}, status={status or "unknown"})')
    return {'success': False, 'error': ' — '.join(error_bits)}


class SmsProvider:
    def send_sms(
        self,
        phone_number: str,
        message: str,
        *,
        purpose: str = 'general',
        user=None,
    ) -> Dict[str, str]:
        provider = ProviderConfig.sms_provider_name()
        if provider == 'kacyber':
            result = self._send_kacyber(phone_number, message)
        elif provider == 'africastalking':
            result = self._send_africastalking(phone_number, message)
        else:
            result = {'success': False, 'error': f'Unsupported SMS provider: {provider}'}

        self._persist_outbound(
            phone_number=phone_number,
            message=message,
            provider=provider,
            purpose=purpose,
            user=user,
            result=result,
        )
        return result

    def _persist_outbound(
        self,
        *,
        phone_number: str,
        message: str,
        provider: str,
        purpose: str,
        user,
        result: Dict[str, str],
    ) -> None:
        try:
            from apps.safety.models import SmsMessage

            success = bool(result.get('success'))
            SmsMessage.objects.create(
                direction='outbound',
                provider=provider or '',
                purpose=purpose or 'general',
                phone_number=(phone_number or '')[:32],
                # Admins can read this log, so one-time codes are not stored.
                message=re.sub(r'\b\d{6}\b', '[code]', message or '') if purpose == 'otp' else message or '',
                status='sent' if success else 'failed',
                provider_message_id=(result.get('provider_message_id') or '')[:128],
                cost=(result.get('cost') or '')[:64],
                error=(result.get('error') or '')[:2000],
                user=user,
                raw_response=dict(result),
            )
        except Exception:
            # Never fail the SMS send path because logging failed.
            logger.exception('Failed to persist outbound SMS log')

    @staticmethod
    def record_inbound(
        *,
        phone_number: str,
        message: str,
        provider: str = '',
        provider_message_id: str = '',
        raw_payload=None,
        user=None,
    ):
        from apps.safety.models import SmsMessage

        return SmsMessage.objects.create(
            direction='inbound',
            provider=provider or ProviderConfig.sms_provider_name(),
            purpose='inbound',
            phone_number=(phone_number or '')[:32],
            message=message or '',
            status='received',
            provider_message_id=(provider_message_id or '')[:128],
            user=user,
            raw_response=raw_payload if isinstance(raw_payload, dict) else {'raw': raw_payload},
        )

    def _send_africastalking(self, phone_number: str, message: str) -> Dict[str, str]:
        if not ProviderConfig.api_key() or not ProviderConfig.username():
            return {
                'success': True,
                'provider_message_id': f'mock-sms-{uuid.uuid4().hex[:10]}',
                'mocked': True,
            }

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
            return {
                'success': False,
                'error': f'SMS API error {response.status_code}: {response.text}',
            }
        except Exception as exc:
            return {'success': False, 'error': str(exc)}

    def _send_kacyber(self, phone_number: str, message: str) -> Dict[str, str]:
        if not ProviderConfig.kacyber_is_configured():
            return {
                'success': False,
                'error': (
                    'KaCyber SMS is not configured. Set KACYBER_APP_ID, '
                    'KACYBER_API_KEY, and KACYBER_SENDER_ID in backend/.env, '
                    'then set SMS_PROVIDER=kacyber.'
                ),
            }

        msisdn = _to_kacyber_msisdn(phone_number)
        if not msisdn:
            return {'success': False, 'error': 'Invalid phone number for KaCyber SMS'}

        headers = {
            'X-app-id': ProviderConfig.kacyber_app_id(),
            'X-API-Key': ProviderConfig.kacyber_api_key(),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        }
        payload = {
            'senderId': ProviderConfig.kacyber_sender_id(),
            'message': message,
            'recipients': [msisdn],
        }

        try:
            response = requests.post(
                ProviderConfig.kacyber_sms_url(),
                json=payload,
                headers=headers,
                timeout=(10, 60),
            )
            try:
                data = response.json()
            except ValueError:
                data = {}

            if 200 <= response.status_code < 300:
                return _parse_kacyber_response(data, response.status_code)

            parsed = _parse_kacyber_response(data, response.status_code)
            if parsed.get('error'):
                return parsed
            return {
                'success': False,
                'error': f'KaCyber SMS error {response.status_code}: {response.text}',
            }
        except Exception as exc:
            return {'success': False, 'error': str(exc)}
