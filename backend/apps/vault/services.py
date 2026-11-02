import os
import secrets
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from apps.vault.models import VaultDocument, VaultReleaseToken


def public_base_url() -> str:
    return getattr(settings, "SAFECHECK_PUBLIC_BASE_URL", None) or os.getenv(
        "SAFECHECK_PUBLIC_BASE_URL", "https://safebangle.com"
    ).rstrip("/")


def create_release_token(user) -> VaultReleaseToken:
    token = secrets.token_urlsafe(32)
    expires_at = timezone.now() + timedelta(days=7)
    return VaultReleaseToken.objects.create(
        user=user,
        token=token,
        expires_at=expires_at,
    )


def release_url(token: str) -> str:
    return f'{public_base_url()}/api/vault/release/{token}/'


def active_documents(user) -> list[VaultDocument]:
    return list(
        VaultDocument.objects.filter(user=user, status='active')
        .exclude(file='')
        .order_by('uploaded_at')
    )


def append_vault_links_to_message(user, message: str) -> str:
    docs = active_documents(user)
    if not docs:
        return message
    release = create_release_token(user)
    link = release_url(release.token)
    titles = ', '.join(doc.title for doc in docs[:5])
    return f'{message} Documents ({titles}): {link}'
