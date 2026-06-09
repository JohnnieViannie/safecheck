from __future__ import annotations

from datetime import datetime, time, timedelta, timezone as dt_timezone
from typing import Optional
from zoneinfo import ZoneInfo

from django.utils import timezone

from api.models import UserProfile

DEFAULT_CHECKIN_TIME = time(18, 0)


def _resolve_tz_name(user: UserProfile) -> str:
    raw = (user.timezone or 'UTC').strip()
    try:
        ZoneInfo(raw)
        return raw
    except Exception:
        return 'UTC'


def _checkin_time_for_user(user: UserProfile) -> time:
    if user.checkin_time:
        return user.checkin_time
    return DEFAULT_CHECKIN_TIME


def _period_days(user: UserProfile) -> int:
    frequency = (user.checkin_frequency or 'Daily').strip().lower()
    return 7 if frequency == 'weekly' else 1


def compute_next_checkin_at(
    user: UserProfile,
    now_utc: Optional[datetime] = None,
    *,
    after: Optional[datetime] = None,
) -> datetime:
    """
    Return the next check-in instant in UTC.

    If `after` is provided, returns the first occurrence strictly after that moment.
    Otherwise uses `now_utc` and returns the next future occurrence (or now if due).
    """
    now_utc = now_utc or timezone.now()
    if timezone.is_naive(now_utc):
        now_utc = timezone.make_aware(now_utc, dt_timezone.utc)

    tz_name = _resolve_tz_name(user)
    tz = ZoneInfo(tz_name)
    checkin_time = _checkin_time_for_user(user)
    period_days = _period_days(user)

    reference_utc = after or now_utc
    if timezone.is_naive(reference_utc):
        reference_utc = timezone.make_aware(reference_utc, dt_timezone.utc)

    local_ref = reference_utc.astimezone(tz)
    candidate_local = datetime.combine(local_ref.date(), checkin_time, tzinfo=tz)

    if candidate_local <= local_ref:
        candidate_local = candidate_local + timedelta(days=period_days)

    return candidate_local.astimezone(dt_timezone.utc)


def ensure_next_scheduled_checkin(
    user: UserProfile,
    now_utc: Optional[datetime] = None,
    *,
    force_recompute: bool = False,
) -> datetime:
    """Initialize or optionally recompute user.next_scheduled_checkin_at."""
    now_utc = now_utc or timezone.now()
    if user.next_scheduled_checkin_at and not force_recompute:
        return user.next_scheduled_checkin_at
    next_at = compute_next_checkin_at(user, now_utc=now_utc)
    user.next_scheduled_checkin_at = next_at
    return next_at


def recompute_next_scheduled_checkin(
    user: UserProfile,
    now_utc: Optional[datetime] = None,
) -> datetime:
    """Recompute the next check-in after schedule settings change."""
    return ensure_next_scheduled_checkin(user, now_utc, force_recompute=True)


def is_snoozed(user: UserProfile, now_utc: Optional[datetime] = None) -> bool:
    now_utc = now_utc or timezone.now()
    snoozed_until = getattr(user, 'snoozed_until', None)
    return snoozed_until is not None and snoozed_until > now_utc


def is_due(user: UserProfile, now_utc: Optional[datetime] = None) -> bool:
    now_utc = now_utc or timezone.now()
    if is_snoozed(user, now_utc):
        return False
    if not user.next_scheduled_checkin_at:
        ensure_next_scheduled_checkin(user, now_utc)
    return user.next_scheduled_checkin_at is not None and user.next_scheduled_checkin_at <= now_utc


def advance_after_dispatch(user: UserProfile, dispatched_at: Optional[datetime] = None) -> datetime:
    """Move schedule to the next occurrence after a check-in push was sent."""
    dispatched_at = dispatched_at or timezone.now()
    next_at = compute_next_checkin_at(user, now_utc=dispatched_at, after=dispatched_at)
    user.next_scheduled_checkin_at = next_at
    return next_at
