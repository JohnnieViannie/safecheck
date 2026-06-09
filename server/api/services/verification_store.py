import secrets
from typing import Optional

from django.core.cache import cache

_CODE_TTL_SECONDS = 600


def generate_code() -> str:
    return f'{secrets.randbelow(900000) + 100000:06d}'


def create_verification_id(prefix: str) -> str:
    return f'{prefix}-{secrets.token_hex(6)}'


def store_code(verification_id: str, code: str, subject: str) -> None:
    cache.set(
        f'verify:{verification_id}',
        {'code': code, 'subject': subject},
        timeout=_CODE_TTL_SECONDS,
    )


def verify_code(
    verification_id: Optional[str],
    code: Optional[str],
    subject: Optional[str] = None,
) -> bool:
    if not verification_id or not code:
        return False

    payload = cache.get(f'verify:{verification_id}')
    if not payload:
        return False
    if subject is not None:
        stored_subject = (payload.get('subject') or '').strip().lower()
        if stored_subject != subject.strip().lower():
            return False
    expected = payload.get('code')
    if not expected or str(code).strip() != str(expected):
        return False
    cache.delete(f'verify:{verification_id}')
    return True
