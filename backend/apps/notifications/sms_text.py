"""Short text messages. One SMS is 160 plain characters, so every character here costs money."""
from __future__ import annotations

import re
import unicodedata
from zoneinfo import ZoneInfo

import phonenumbers
from django.conf import settings
from django.utils import timezone
from phonenumbers import timezone as phone_timezone

SMS_LIMIT = 160
NAME_LIMIT = 24
# Characters outside this set cost extra or shrink the whole message from 160 to 70 characters.
_NOT_SMS_SAFE = re.compile(r"[^A-Za-z0-9 .,:;'\"!?()/+\-=&%#@_*$\n]")


def gsm_safe(text) -> str:
    plain = unicodedata.normalize("NFKD", str(text or "")).encode("ascii", "ignore").decode()
    return re.sub(r" {2,}", " ", _NOT_SMS_SAFE.sub("", plain)).strip()


def shorten(text: str, limit: int) -> str:
    """Cut at a word boundary, without a dangling comma."""
    if len(text) <= limit:
        return text
    cut = text[:limit]
    if " " in cut and not text[limit].isspace():
        cut = cut.rsplit(" ", 1)[0]
    return cut.rstrip(" ,;:-")


def sms_name(name, limit: int = NAME_LIMIT, fallback: str = "Your contact") -> str:
    return shorten(gsm_safe(name), limit) or fallback


def map_link(lat, lng) -> str:
    return f"https://maps.google.com/?q={float(lat):.5f},{float(lng):.5f}"


def format_radius(metres) -> str:
    try:
        value = int(metres or 0)
    except (TypeError, ValueError):
        return ""
    if value <= 0:
        return ""
    if value < 1000:
        return f"{value}m"
    km = round(value / 1000, 1)
    return f"{int(km)}km" if km == int(km) else f"{km}km"


def zone_for_phone(phone) -> ZoneInfo:
    """Time zone for a phone number, or the default when the number doesn't settle on one."""
    default = ZoneInfo(settings.ALERT_DEFAULT_TIMEZONE)
    try:
        zones = phone_timezone.time_zones_for_number(phonenumbers.parse(str(phone or ""), None))
    except phonenumbers.NumberParseException:
        return default
    if len(zones) != 1 or zones[0] == phone_timezone.UNKNOWN_TIMEZONE:
        return default
    try:
        return ZoneInfo(zones[0])
    except Exception:
        return default


def local_time(moment, phone=None) -> str:
    """14:32 EAT, with the day added when it isn't today where the wearer is."""
    zone = zone_for_phone(phone)
    local = (moment or timezone.now()).astimezone(zone)
    text = local.strftime("%H:%M")
    abbreviation = local.strftime("%Z")
    if abbreviation.isalpha():
        text = f"{text} {abbreviation}"
    if local.date() != timezone.now().astimezone(zone).date():
        text = f"{local.day} {local:%b} {text}"
    return text


def _fit_area(area, room: int) -> str:
    """Fit a place name in the room left, preferring the wider place over a cut-off road name."""
    area = gsm_safe(area)
    if len(area) <= room:
        return area
    wider = area.rsplit(",", 1)[-1].strip()
    if len(wider) <= room:
        return wider
    return shorten(wider, room) if room >= 8 else ""


def sos_sms(name, area, when, radius_m, lat, lng) -> str:
    who = sms_name(name)
    if lat is None or lng is None:
        return f"SOS! {who} needs help. Location unavailable. Sent {when}."
    radius = format_radius(radius_m)
    tail = f" at {when}.{f' Within {radius}.' if radius else ''} {map_link(lat, lng)}"
    start = f"SOS! {who} needs help"
    place = _fit_area(area, SMS_LIMIT - len(start) - len(tail) - len(" near "))
    return f"{start}{f' near {place}' if place else ''}{tail}"


def checkin_sms(name, area, when, lat, lng) -> str:
    who = sms_name(name)
    start = f"SafeBangle: {who} missed a check-in."
    if lat is None or lng is None:
        return f"{start} Location unavailable."
    tail = f" at {when}. {map_link(lat, lng)}"
    lead = f"{start} Last seen"
    place = _fit_area(area, SMS_LIMIT - len(lead) - len(tail) - len(" near "))
    return f"{lead}{f' near {place}' if place else ''}{tail}"


BIRTHDAY_MESSAGES = (
    "Happy birthday, {name}! Wishing you a safe and joyful year ahead. "
    "With love from all of us at SafeBangle.",
    "Happy birthday, {name}! We're glad to be looking out for you. "
    "May this year bring you health and happiness. From your SafeBangle family.",
    "It's your special day, {name}! Wishing you peace, joy and safe journeys all year. "
    "Happy birthday from SafeBangle.",
    "Happy birthday, {name}! You matter to us and to the people who love you. "
    "Have a wonderful day. From all of us at SafeBangle.",
)


def birthday_sms(first_name, seed: int) -> str:
    name = sms_name(first_name, limit=20, fallback="friend")
    return BIRTHDAY_MESSAGES[seed % len(BIRTHDAY_MESSAGES)].format(name=name)
