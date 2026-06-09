import json
import os
import uuid
from datetime import timedelta
from typing import Any, Dict, Optional


class PushProvider:
    """Sends high-priority FCM data messages to wake the app for check-in calls."""

    def __init__(self) -> None:
        self._initialized = False

    def _ensure_firebase(self) -> bool:
        if self._initialized:
            return True
        cred_path = os.getenv('FIREBASE_CREDENTIALS_PATH', '').strip()
        cred_json = os.getenv('FIREBASE_CREDENTIALS_JSON', '').strip()
        if not cred_path and not cred_json:
            return False
        try:
            import firebase_admin
            from firebase_admin import credentials

            if firebase_admin._apps:
                self._initialized = True
                return True

            if cred_json:
                cred = credentials.Certificate(json.loads(cred_json))
            else:
                cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            self._initialized = True
            return True
        except Exception:
            return False

    def send_checkin_call_push(
        self,
        fcm_token: str,
        *,
        uid: str,
        call_kit_id: str,
        scheduled_for_iso: str,
        frequency: str,
        checkin_time: str = '18:00',
        snoozed: bool = False,
    ) -> Dict[str, Any]:
        if not fcm_token:
            return {'success': False, 'error': 'Missing FCM token'}

        data = {
            'type': 'checkin_call',
            'uid': uid,
            'callKitId': call_kit_id,
            'scheduledFor': scheduled_for_iso,
            'frequency': frequency,
            'checkinTime': checkin_time,
            'snoozed': 'true' if snoozed else 'false',
            'alarmId': '1' if snoozed else '0',
        }

        if not self._ensure_firebase():
            return {
                'success': True,
                'provider_message_id': f'mock-push-{uuid.uuid4().hex[:10]}',
                'mocked': True,
            }

        try:
            from firebase_admin import messaging

            android_config = messaging.AndroidConfig(
                priority='high',
                ttl=timedelta(seconds=300),
            )
            message = messaging.Message(
                data={k: str(v) for k, v in data.items()},
                token=fcm_token,
                android=android_config,
            )
            message_id = messaging.send(message)
            return {'success': True, 'provider_message_id': message_id}
        except Exception as exc:
            return {'success': False, 'error': str(exc)}


def new_call_kit_id(seed: Optional[str] = None) -> str:
    if seed:
        hex_seed = uuid.uuid5(uuid.NAMESPACE_DNS, seed).hex
        return (
            f'{hex_seed[0:8]}-{hex_seed[8:12]}-{hex_seed[12:16]}-'
            f'{hex_seed[16:20]}-{hex_seed[20:32]}'
        )
    return str(uuid.uuid4())
