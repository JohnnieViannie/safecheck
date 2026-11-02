import uuid

from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.checkins.models import CallAttempt
from apps.journeys.models import JourneySession
from apps.push.push_provider import PushProvider, new_call_kit_id
from apps.safety.models import SafetyProfile
from apps.safety.services.push_fallback import place_voice_fallback
from apps.safety.services.schedule_engine import (
    advance_after_dispatch,
    ensure_next_scheduled_checkin,
    is_due,
    is_snoozed,
)
from apps.safety.services.safety_engine import escalate_to_next_of_kin
from apps.safety.services.timeline import log_timeline_event


class Command(BaseCommand):
    help = "Triggers due check-in push notifications (SafeCheck scheduler)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Log actions without sending pushes or updating schedules.",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        now = timezone.now()
        push = PushProvider()

        users = SafetyProfile.objects.filter(onboarding_completed=True).select_related(
            "user"
        )
        triggered = 0
        skipped = 0
        escalated = 0
        journeys_escalated = 0

        overdue_journeys = JourneySession.objects.filter(
            status="active",
            expected_arrival_at__lte=now,
        ).select_related("user")
        for journey in overdue_journeys:
            profile = getattr(journey.user, "safety_profile", None)
            if not profile:
                continue
            if dry_run:
                self.stdout.write(
                    f"[dry-run] Would escalate overdue journey for {profile.legacy_uid}"
                )
                journeys_escalated += 1
                continue
            journey.status = "missed"
            journey.save(update_fields=["status"])
            escalate_to_next_of_kin(profile)
            log_timeline_event(
                user=profile,
                event_type="journey_missed",
                source="scheduler",
                status="escalated",
                payload={
                    "journey_id": str(journey.id),
                    "reason": "expected_arrival_missed",
                },
            )
            journeys_escalated += 1

        for user in users:
            if not user.fcm_token:
                skipped += 1
                continue

            ensure_next_scheduled_checkin(user, now)
            if not user.next_scheduled_checkin_at:
                skipped += 1
                continue

            if self._should_escalate_missed(user, now):
                if not dry_run:
                    user.last_call_status = "no_answer"
                    user.save(update_fields=["last_call_status"])
                    escalate_to_next_of_kin(user)
                    log_timeline_event(
                        user=user,
                        event_type="checkin_escalated",
                        source="scheduler",
                        status="escalated",
                        payload={"reason": "no_answer", "source": "server_scheduler"},
                    )
                    user.last_push_sent_at = None
                    user.pending_call_kit_id = None
                    advance_after_dispatch(user, now)
                    user.save(
                        update_fields=[
                            "next_scheduled_checkin_at",
                            "last_push_sent_at",
                            "pending_call_kit_id",
                        ]
                    )
                escalated += 1
                continue

            if is_snoozed(user, now):
                skipped += 1
                continue

            if not is_due(user, now):
                skipped += 1
                continue

            call_kit_id = new_call_kit_id(
                f"{user.legacy_uid}-{user.next_scheduled_checkin_at.isoformat()}"
            )
            scheduled_for = user.next_scheduled_checkin_at
            frequency = user.checkin_frequency or "Daily"
            checkin_time = (
                user.checkin_time.strftime("%H:%M") if user.checkin_time else "18:00"
            )
            snoozed = is_snoozed(user, now)

            if dry_run:
                self.stdout.write(
                    f"[dry-run] Would push check-in to {user.legacy_uid} at {scheduled_for.isoformat()}"
                )
                triggered += 1
                continue

            result = push.send_checkin_call_push(
                user.fcm_token,
                uid=user.legacy_uid,
                call_kit_id=call_kit_id,
                scheduled_for_iso=scheduled_for.isoformat(),
                frequency=frequency,
                checkin_time=checkin_time,
                snoozed=snoozed,
            )

            last_attempt = (
                CallAttempt.objects.filter(user=user.user)
                .order_by("-attempt_number")
                .first()
            )
            attempt_number = (last_attempt.attempt_number + 1) if last_attempt else 1
            CallAttempt.objects.create(
                user=user.user,
                attempt_number=attempt_number,
                provider_call_id=result.get("provider_message_id")
                or f"push-{uuid.uuid4().hex[:8]}",
                status="in_progress" if result.get("success") else "failed",
                scheduled_for=scheduled_for,
            )

            if result.get("success"):
                user.last_call_status = "push_sent"
                user.last_push_sent_at = now
                user.pending_call_kit_id = call_kit_id
                advance_after_dispatch(user, now)
                user.save(
                    update_fields=[
                        "last_call_status",
                        "last_push_sent_at",
                        "pending_call_kit_id",
                        "next_scheduled_checkin_at",
                    ]
                )
                log_timeline_event(
                    user=user,
                    event_type="checkin_push_sent",
                    source="scheduler",
                    status="sent",
                    payload={
                        "call_kit_id": call_kit_id,
                        "scheduled_for": scheduled_for.isoformat(),
                        "provider_message_id": result.get("provider_message_id"),
                    },
                )
                triggered += 1
            else:
                user.last_call_status = "push_failed"
                user.save(update_fields=["last_call_status"])
                log_timeline_event(
                    user=user,
                    event_type="checkin_push_failed",
                    source="scheduler",
                    status="failed",
                    payload={"error": result.get("error", "unknown")},
                )
                phone = user.user.phone
                if phone:
                    voice_result = place_voice_fallback(phone, user.legacy_uid)
                    if voice_result.get("success"):
                        CallAttempt.objects.create(
                            user=user.user,
                            attempt_number=attempt_number,
                            provider_call_id=voice_result.get("provider_call_id"),
                            status="in_progress",
                            scheduled_for=scheduled_for,
                        )
                        user.last_call_status = "in_progress"
                        advance_after_dispatch(user, now)
                        user.save(
                            update_fields=[
                                "last_call_status",
                                "next_scheduled_checkin_at",
                            ]
                        )
                        triggered += 1
                        continue
                skipped += 1

        self.stdout.write(
            self.style.SUCCESS(
                "Scheduler done: "
                f"pushed={triggered}, skipped={skipped}, escalated={escalated}, "
                f"journeys_escalated={journeys_escalated}, dry_run={dry_run}"
            )
        )

    def _should_escalate_missed(self, user: SafetyProfile, now) -> bool:
        if not user.last_push_sent_at or not user.pending_call_kit_id:
            return False
        grace_deadline = user.last_push_sent_at + user.grace_period_timedelta()
        if now < grace_deadline:
            return False
        if user.confirmed_safe_after_last_push():
            return False
        return user.last_call_status in ("push_sent", "in_progress")
