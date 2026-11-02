"""Thin wrapper so the scheduler can fall back to PSTN voice calls."""
from apps.safety.services.voice_provider import VoiceProvider


def place_voice_fallback(phone_number: str, uid: str) -> dict:
    return VoiceProvider().place_checkin_call(phone_number, uid)
