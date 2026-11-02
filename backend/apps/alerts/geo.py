"""Location helpers: Nominatim reverse geocode + OpenCellID cell lookup."""

from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class GeoError(Exception):
    def __init__(self, message: str, code: str = "geo_error"):
        super().__init__(message)
        self.code = code


def area_from_address(address: dict | None) -> str:
    """Short place name from Nominatim address parts, e.g. "Kampala Road, Kampala"."""
    address = address or {}
    local_keys = ("road", "neighbourhood", "suburb", "quarter", "hamlet")
    wider_keys = ("city", "town", "village", "municipality", "county", "state_district", "state")
    local = next((address[k] for k in local_keys if address.get(k)), "")
    wider = next((address[k] for k in wider_keys if address.get(k)), "")
    parts = [part for part in (local, wider) if part]
    if len(parts) == 2 and parts[0] == parts[1]:
        parts = parts[:1]
    return ", ".join(parts)


def reverse_geocode_place(lat: Decimal | float, lng: Decimal | float) -> dict[str, str]:
    """Return {"label": full address, "area": short place}. Empty values on any failure."""
    empty = {"label": "", "area": ""}
    url = getattr(
        settings,
        "NOMINATIM_REVERSE_URL",
        "https://nominatim.openstreetmap.org/reverse",
    )
    user_agent = getattr(
        settings,
        "NOMINATIM_USER_AGENT",
        "SafeBangle/1.0 (alerts@safebangle.com)",
    )
    timeout = getattr(settings, "GEO_HTTP_TIMEOUT", 8)
    try:
        resp = requests.get(
            url,
            params={
                "lat": str(lat),
                "lon": str(lng),
                "format": "json",
                "zoom": 18,
                "addressdetails": 1,
                "accept-language": "en",
            },
            headers={"User-Agent": user_agent, "Accept": "application/json"},
            timeout=timeout,
        )
        if not resp.ok:
            logger.warning("Nominatim reverse failed: %s %s", resp.status_code, resp.text[:200])
            return empty
        data = resp.json() if resp.content else {}
        return {
            "label": (data.get("display_name") or "").strip()[:500],
            "area": area_from_address(data.get("address"))[:200],
        }
    except Exception:
        logger.exception("Nominatim reverse geocode error")
        return empty


def opencellid_lookup(
    *,
    mcc: int,
    mnc: int,
    lac: int,
    cellid: int,
    radio: str | None = None,
) -> dict[str, Any]:
    """
    Resolve cell tower identifiers to approximate lat/lon via OpenCellID.

    Returns dict with latitude, longitude, accuracy_m (nullable).
    Raises GeoError when the cell is unknown or the API is unavailable.
    """
    api_key = getattr(settings, "OPENCELLID_API_KEY", "") or ""
    if not api_key:
        if settings.DEBUG:
            # Deterministic mock for local/dev without a key
            logger.info(
                "MOCK OpenCellID lookup mcc=%s mnc=%s lac=%s cellid=%s",
                mcc,
                mnc,
                lac,
                cellid,
            )
            return {
                "latitude": Decimal("-1.292100"),
                "longitude": Decimal("36.821900"),
                "accuracy_m": 500,
                "mock": True,
            }
        raise GeoError("OpenCellID is not configured.", "opencellid_unconfigured")

    base = getattr(settings, "OPENCELLID_BASE_URL", "https://opencellid.org").rstrip("/")
    url = f"{base}/cell/get"
    timeout = getattr(settings, "GEO_HTTP_TIMEOUT", 8)
    params: dict[str, Any] = {
        "key": api_key,
        "mcc": int(mcc),
        "mnc": int(mnc),
        "lac": int(lac),
        "cellid": int(cellid),
        "format": "json",
    }
    if radio:
        params["radio"] = radio.upper()

    # A slow connection shouldn't cost an emergency its location, so try once more.
    resp = None
    for attempt in range(2):
        try:
            resp = requests.get(url, params=params, timeout=timeout)
            break
        except Exception as exc:
            # The request URL carries the API key, so its error text must never reach the logs.
            logger.error("OpenCellID request failed (try %s): %s", attempt + 1, type(exc).__name__)
    if resp is None:
        raise GeoError("OpenCellID request failed.", "opencellid_unreachable")

    if resp.status_code == 404 or (resp.ok and not resp.content):
        raise GeoError("Cell tower not found in OpenCellID.", "cell_not_found")

    try:
        data = resp.json() if resp.content else {}
    except ValueError as exc:
        raise GeoError("Invalid OpenCellID response.", "opencellid_bad_response") from exc

    # Error payloads vary; treat missing lat/lon as not found
    if not resp.ok:
        err = data.get("error") or data.get("message") or resp.text[:200]
        if "not found" in str(err).lower() or resp.status_code in (404, 422):
            raise GeoError("Cell tower not found in OpenCellID.", "cell_not_found")
        raise GeoError(f"OpenCellID error: {err}", "opencellid_error")

    lat = data.get("lat")
    lon = data.get("lon")
    if lat is None or lon is None:
        raise GeoError("Cell tower not found in OpenCellID.", "cell_not_found")

    try:
        latitude = Decimal(str(lat))
        longitude = Decimal(str(lon))
    except Exception as exc:
        raise GeoError("Invalid coordinates from OpenCellID.", "opencellid_bad_coords") from exc

    accuracy = data.get("range")
    try:
        accuracy_m = int(accuracy) if accuracy is not None else None
    except (TypeError, ValueError):
        accuracy_m = None

    return {
        "latitude": latitude,
        "longitude": longitude,
        "accuracy_m": accuracy_m,
        "raw": data,
    }
