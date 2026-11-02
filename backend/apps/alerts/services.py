import hashlib
import logging
import re
from datetime import datetime
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from apps.alerts.geo import reverse_geocode_place
from apps.alerts.models import Alert, AlertCode, InboundSmsEvent
from apps.audit.services import AuditService
from apps.devices.models import Bracelet, BraceletStatus
from apps.incidents.services import IncidentService
from apps.notifications.services import AlertRoutingService

logger = logging.getLogger(__name__)


class SmsParseError(Exception):
    def __init__(self, message, code="parse_error"):
        super().__init__(message)
        self.code = code


class DeviceAlertError(Exception):
    def __init__(self, message, code="device_alert_error", http_status=400):
        super().__init__(message)
        self.code = code
        self.http_status = http_status


class SmsParser:
    @classmethod
    def parse(cls, text: str) -> dict:
        pattern = settings.BRACELET_SMS_REGEX
        match = re.match(pattern, (text or "").strip(), re.IGNORECASE)
        if not match:
            raise SmsParseError("Malformed SMS: does not match expected format.", "malformed")
        groups = match.groupdict()
        device_id = (groups.get("device_id") or "").strip()
        alert_code = (groups.get("alert_code") or "").strip().upper()
        if not device_id:
            raise SmsParseError("Missing device ID.", "missing_device")
        if not alert_code:
            raise SmsParseError("Missing alert code.", "missing_code")
        try:
            lat = Decimal(groups["lat"])
            lng = Decimal(groups["lng"])
        except (InvalidOperation, KeyError, TypeError) as exc:
            raise SmsParseError("Invalid coordinates.", "invalid_coords") from exc
        if not (-90 <= float(lat) <= 90 and -180 <= float(lng) <= 180):
            raise SmsParseError("Coordinates out of range.", "invalid_coords")
        return {
            "device_id": device_id,
            "alert_code": alert_code,
            "latitude": lat,
            "longitude": lng,
        }


def parse_device_timestamp(value):
    if value is None or value == "":
        return timezone.now()
    if isinstance(value, (int, float)) or (isinstance(value, str) and str(value).isdigit()):
        ts = int(value)
        if ts > 10_000_000_000:  # ms
            ts = ts / 1000
        return datetime.fromtimestamp(ts, tz=timezone.get_current_timezone())
    received_at = parse_datetime(str(value))
    if received_at is None:
        return timezone.now()
    if timezone.is_naive(received_at):
        received_at = timezone.make_aware(received_at)
    return received_at


class AlertEngine:
    @classmethod
    @transaction.atomic
    def create_from_device(
        cls,
        *,
        device_id: str,
        alert_code: str = "SOS",
        latitude: Decimal | None = None,
        longitude: Decimal | None = None,
        received_at=None,
        raw_payload: dict | None = None,
        location_source: str = Alert.LocationSource.GPS,
        location_label: str = "",
        location_accuracy_m: int | None = None,
        inbound_event: InboundSmsEvent | None = None,
        phone: str = "",
        geocode: bool = True,
    ) -> dict:
        raw_payload = dict(raw_payload or {})
        if phone:
            raw_payload.setdefault("phone", phone)

        device_id = (device_id or "").strip()
        alert_code = (alert_code or "SOS").strip().upper() or "SOS"
        if not device_id:
            raise DeviceAlertError("Missing device_id.", "missing_device", 400)

        try:
            bracelet = Bracelet.objects.select_related(
                "organization", "current_person", "owner_user"
            ).get(device_id__iexact=device_id)
        except Bracelet.DoesNotExist as exc:
            raise DeviceAlertError(
                f"Unknown bracelet: {device_id}", "unknown_bracelet", 404
            ) from exc

        if bracelet.status == BraceletStatus.DEACTIVATED:
            raise DeviceAlertError(
                "Bracelet is deactivated.", "deactivated", 409
            )

        if latitude is not None and longitude is not None:
            try:
                lat = Decimal(str(latitude))
                lng = Decimal(str(longitude))
            except (InvalidOperation, TypeError) as exc:
                raise DeviceAlertError(
                    "Invalid coordinates.", "invalid_coords", 400
                ) from exc
            if not (-90 <= float(lat) <= 90 and -180 <= float(lng) <= 180):
                raise DeviceAlertError(
                    "Coordinates out of range.", "invalid_coords", 400
                )
        else:
            lat = lng = None

        code_obj = AlertCode.objects.filter(code__iexact=alert_code, is_active=True).first()
        if not code_obj and alert_code not in {"SOS", "TEST", "HELP"}:
            logger.info("Unknown alert code %s — accepting", alert_code)

        if received_at is None:
            received_at = timezone.now()
        elif timezone.is_naive(received_at):
            received_at = timezone.make_aware(received_at)

        location_area = ""
        if geocode and lat is not None and lng is not None and not location_label:
            place = reverse_geocode_place(lat, lng)
            location_label = place["label"]
            location_area = place["area"]

        person = bracelet.current_person
        if phone and person and person.phone:
            raw_payload["phone_match"] = (
                phone.replace(" ", "") == person.phone.replace(" ", "")
            )

        alert = Alert.objects.create(
            bracelet=bracelet,
            person=person,
            organization=bracelet.organization or (person.organization if person else None),
            owner_user=bracelet.owner_user
            or (person.owner_user if person else None),
            alert_code=alert_code,
            latitude=lat,
            longitude=lng,
            location_label=location_label or "",
            location_area=location_area,
            location_source=location_source or Alert.LocationSource.GPS,
            location_accuracy_m=location_accuracy_m,
            received_at=received_at,
            raw_payload=raw_payload,
            processing_status=Alert.ProcessingStatus.PROCESSED,
            inbound_event=inbound_event,
        )

        incident = None
        unassigned = False
        if person or bracelet.organization_id or bracelet.owner_user_id:
            incident = IncidentService.create_from_alert(alert)
        else:
            unassigned = True
            logger.warning("Unassigned bracelet alert %s", bracelet.device_id)

        AlertRoutingService.route_alert(alert)

        AuditService.log(
            actor=None,
            action="alert.received",
            object_type="Alert",
            object_id=str(alert.id),
            organization=alert.organization,
            metadata={
                "device_id": bracelet.device_id,
                "alert_code": alert.alert_code,
                "incident_id": str(incident.id) if incident else None,
                "location_source": alert.location_source,
            },
        )

        return {
            "alert_id": str(alert.id),
            "incident_id": str(incident.id) if incident else None,
            "status": "processed",
            "unassigned": unassigned,
            "location_label": alert.location_label,
            "location_area": alert.location_area,
            "location_accuracy_m": alert.location_accuracy_m,
            "latitude": str(alert.latitude) if alert.latitude is not None else None,
            "longitude": str(alert.longitude) if alert.longitude is not None else None,
            "location_source": alert.location_source,
        }

    @classmethod
    @transaction.atomic
    def process_inbound(
        cls,
        *,
        text: str,
        sender: str = "",
        recipient: str = "",
        provider_message_id: str = "",
        date: str = "",
        raw_payload: dict | None = None,
    ) -> dict:
        raw_payload = raw_payload or {}
        key = InboundSmsEvent.make_idempotency_key(
            provider_message_id, sender, text, date
        )
        existing = InboundSmsEvent.objects.filter(idempotency_key=key).first()
        if existing:
            return {
                "duplicate": True,
                "event_id": str(existing.id),
                "status": existing.status,
                "alert_id": str(existing.alert.id)
                if hasattr(existing, "alert") and existing.alert
                else None,
            }

        event = InboundSmsEvent.objects.create(
            idempotency_key=key,
            provider_message_id=provider_message_id or "",
            sender=sender or "",
            recipient=recipient or "",
            text=text or "",
            raw_payload=raw_payload,
            status=InboundSmsEvent.ProcessStatus.RECEIVED,
        )

        try:
            parsed = SmsParser.parse(text)
        except SmsParseError as exc:
            event.status = InboundSmsEvent.ProcessStatus.FAILED
            event.error_message = str(exc)
            event.processed_at = timezone.now()
            event.save()
            logger.warning("SMS parse failed: %s", exc)
            return {
                "duplicate": False,
                "event_id": str(event.id),
                "error": str(exc),
                "code": exc.code,
            }

        received_at = parse_datetime(date) if date else None
        if received_at is None:
            received_at = timezone.now()
        elif timezone.is_naive(received_at):
            received_at = timezone.make_aware(received_at)

        try:
            result = cls.create_from_device(
                device_id=parsed["device_id"],
                alert_code=parsed["alert_code"],
                latitude=parsed["latitude"],
                longitude=parsed["longitude"],
                received_at=received_at,
                raw_payload={
                    "text": text,
                    "parsed": {k: str(v) for k, v in parsed.items()},
                    **raw_payload,
                },
                location_source=Alert.LocationSource.SMS,
                inbound_event=event,
                phone=sender or "",
                geocode=True,
            )
        except DeviceAlertError as exc:
            if exc.code == "deactivated":
                event.status = InboundSmsEvent.ProcessStatus.IGNORED
            else:
                event.status = InboundSmsEvent.ProcessStatus.FAILED
            event.error_message = str(exc)
            event.processed_at = timezone.now()
            event.save()
            return {
                "duplicate": False,
                "event_id": str(event.id),
                "error": str(exc),
                "code": exc.code,
            }

        if result.get("unassigned"):
            event.error_message = "Bracelet unassigned; alert recorded without incident."

        event.status = InboundSmsEvent.ProcessStatus.PROCESSED
        event.processed_at = timezone.now()
        event.save()

        return {
            "duplicate": False,
            "event_id": str(event.id),
            **result,
        }

    @classmethod
    def process_device_sos(
        cls,
        *,
        device_id: str,
        alert_code: str,
        latitude: Decimal | None,
        longitude: Decimal | None,
        timestamp,
        phone: str,
        raw_payload: dict,
        location_source: str,
        location_accuracy_m: int | None = None,
        idempotency_key: str = "",
    ) -> dict:
        """HTTP bracelet SOS with optional idempotency via InboundSmsEvent journal."""
        if not idempotency_key:
            material = "|".join(
                [
                    device_id or "",
                    str(timestamp or ""),
                    alert_code or "SOS",
                    str(latitude or ""),
                    str(longitude or ""),
                    phone or "",
                    location_source or "",
                ]
            )
            idempotency_key = (
                "sos:" + hashlib.sha256(material.encode("utf-8")).hexdigest()
            )
        elif not idempotency_key.startswith("sos:"):
            idempotency_key = f"sos:{idempotency_key}"

        existing = InboundSmsEvent.objects.filter(idempotency_key=idempotency_key).first()
        if existing:
            alert_id = None
            if hasattr(existing, "alert") and existing.alert:
                alert_id = str(existing.alert.id)
            return {
                "duplicate": True,
                "event_id": str(existing.id),
                "status": existing.status,
                "alert_id": alert_id,
            }

        event = InboundSmsEvent.objects.create(
            idempotency_key=idempotency_key,
            provider_message_id="",
            sender=phone or "",
            recipient="bracelet-http",
            text=f"HTTP_SOS|{device_id}|{alert_code}|{latitude}|{longitude}",
            raw_payload=raw_payload,
            status=InboundSmsEvent.ProcessStatus.RECEIVED,
        )

        received_at = parse_device_timestamp(timestamp)

        try:
            result = cls.create_from_device(
                device_id=device_id,
                alert_code=alert_code,
                latitude=latitude,
                longitude=longitude,
                received_at=received_at,
                raw_payload=raw_payload,
                location_source=location_source,
                location_accuracy_m=location_accuracy_m,
                inbound_event=event,
                phone=phone,
                geocode=True,
            )
        except DeviceAlertError as exc:
            if exc.code == "deactivated":
                event.status = InboundSmsEvent.ProcessStatus.IGNORED
            else:
                event.status = InboundSmsEvent.ProcessStatus.FAILED
            event.error_message = str(exc)
            event.processed_at = timezone.now()
            event.save()
            raise

        event.status = InboundSmsEvent.ProcessStatus.PROCESSED
        event.processed_at = timezone.now()
        if result.get("unassigned"):
            event.error_message = "Bracelet unassigned; alert recorded without incident."
        event.save()

        return {"duplicate": False, "event_id": str(event.id), **result}
