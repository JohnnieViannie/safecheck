from datetime import date

from apps.notifications.sms_text import zone_for_phone


def celebrated_on(birth: date, year: int) -> date:
    """29 February birthdays fall on 28 February in other years."""
    try:
        return birth.replace(year=year)
    except ValueError:
        return date(year, 2, 28)


def is_birthday(birth: date, today: date) -> bool:
    return celebrated_on(birth, today.year) == today


def days_until_birthday(birth: date, today: date) -> int:
    upcoming = celebrated_on(birth, today.year)
    if upcoming < today:
        upcoming = celebrated_on(birth, today.year + 1)
    return (upcoming - today).days


def local_now(user, now):
    return now.astimezone(zone_for_phone(user.phone))
