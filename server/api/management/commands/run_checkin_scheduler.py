import uuid

from django.core.management.base import BaseCommand
from django.utils import timezone

from api.models import CallAttempt, UserProfile
from api.services.push_provider import PushProvider, new_call_kit_id
from api.services.schedule_engine import (
    advance_after_dispatch,
    ensure_next_scheduled_checkin,
    is_due,
    is_snoozed,
)
from api.services.safety_engine import escalate_to_next_of_kin
from api.services.timeline import log_timeline_event


class Command(BaseCommand):
    help = 'Triggers due check-in push notifications for users (server-driven calls).'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Log actions without sending pushes or updating schedules.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        now = timezone.now()
        push = PushProvider()

        users = UserProfile.objects.filter(onboarding_completed=True)
        triggered = 0
        skipped = 0
        escalated = 0

        for user in users:
            if not user.fcm_token:
                skipped += 1
                continue

            ensure_next_scheduled_checkin(user, now)
            if not user.next_scheduled_checkin_at:
                skipped += 1
                continue

            # Escalate if previous push was not answered within grace window.
            if self._should_escalate_missed(user, now):
                if not dry_run:
                    user.last_call_status = 'no_answer'
                    user.save(update_fields=['last_call_status'])
                    escalate_to_next_of_kin(user)
                    log_timeline_event(
                        user=user,
                        event_type='checkin_escalated',
                        source='scheduler',
                        status='escalated',
                        payload={'reason': 'no_answer', 'source': 'server_scheduler'},
                    )
                    user.last_push_sent_at = None
                    user.pending_call_kit_id = None
                    advance_after_dispatch(user, now)
                    user.save(
                        update_fields=[
                            'next_scheduled_checkin_at',
                            'last_push_sent_at',
                            'pending_call_kit_id',
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

            call_kit_id = new_call_kit_id(f'{user.uid}-{user.next_scheduled_checkin_at.isoformat()}')
            scheduled_for = user.next_scheduled_checkin_at
            frequency = user.checkin_frequency or 'Daily'
            snoozed = False

            if dry_run:
                self.stdout.write(
                    f'[dry-run] Would push check-in to {user.uid} at {scheduled_for.isoformat()}'
                )
                triggered += 1
                continue

            result = push.send_checkin_call_push(
                user.fcm_token,
                uid=user.uid,
                call_kit_id=call_kit_id,
                scheduled_for_iso=scheduled_for.isoformat(),
                frequency=frequency,
                snoozed=snoozed,
            )

            last_attempt = user.call_attempts.order_by('-attempt_number').first()
            attempt_number = (last_attempt.attempt_number + 1) if last_attempt else 1
            CallAttempt.objects.create(
                user=user,
                attempt_number=attempt_number,
                provider_call_id=result.get('provider_message_id') or f'push-{uuid.uuid4().hex[:8]}',
                status='in_progress' if result.get('success') else 'failed',
                scheduled_for=scheduled_for,
            )

            if result.get('success'):
                user.last_call_status = 'push_sent'
                user.last_push_sent_at = now
                user.pending_call_kit_id = call_kit_id
                advance_after_dispatch(user, now)
                user.save(
                    update_fields=[
                        'last_call_status',
                        'last_push_sent_at',
                        'pending_call_kit_id',
                        'next_scheduled_checkin_at',
                    ]
                )
                log_timeline_event(
                    user=user,
                    event_type='checkin_push_sent',
                    source='scheduler',
                    status='sent',
                    payload={
                        'call_kit_id': call_kit_id,
                        'scheduled_for': scheduled_for.isoformat(),
                        'provider_message_id': result.get('provider_message_id'),
                    },
                )
                triggered += 1
            else:
                user.last_call_status = 'push_failed'
                user.save(update_fields=['last_call_status'])
                log_timeline_event(
                    user=user,
                    event_type='checkin_push_failed',
                    source='scheduler',
                    status='failed',
                    payload={'error': result.get('error', 'unknown')},
                )
                skipped += 1

        self.stdout.write(
            self.style.SUCCESS(
                f'Scheduler done: pushed={triggered}, skipped={skipped}, escalated={escalated}, dry_run={dry_run}'
            )
        )

    def _should_escalate_missed(self, user: UserProfile, now) -> bool:
        if not user.last_push_sent_at or not user.pending_call_kit_id:
            return False
        grace_hours = user.grace_period_hours if user.grace_period_hours is not None else 2
        grace_deadline = user.last_push_sent_at + timezone.timedelta(hours=grace_hours)
        if now < grace_deadline:
            return False
        # User confirmed safe after last push — do not escalate.
        if user.confirmed_safe_after_last_push():
            return False
        return user.last_call_status in ('push_sent', 'in_progress')
