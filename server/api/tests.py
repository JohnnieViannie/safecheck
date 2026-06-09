from unittest.mock import patch

from django.test import TestCase
from rest_framework.test import APIClient

from api.models import AlertEvent, CallAttempt, Checkin, LocationSnapshot, UserProfile
from datetime import time
from datetime import datetime as dt_datetime
from datetime import timezone as dt_timezone

from django.utils import timezone

from api.services.schedule_engine import compute_next_checkin_at, is_due
from api.services.safety_engine import is_safe_phrase


class SafetyWorkflowTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = UserProfile.objects.create(
            uid='user-1',
            phone_number='+2348000000000',
            full_name='Viannie',
            onboarding_completed=True,
            emergency_contact_name='John',
            emergency_contact_phone='+2348111111111',
            emergency_contact_relationship='Brother',
            emergency_contact_email='john@example.com',
            max_retry_attempts=2,
        )

    def test_safe_phrase_detection(self):
        self.assertTrue(is_safe_phrase("I'm fine"))
        self.assertTrue(is_safe_phrase('i am fine now'))
        self.assertFalse(is_safe_phrase('help me'))

    @patch('api.services.voice_provider.VoiceProvider.place_checkin_call')
    def test_trigger_call_creates_attempt(self, mock_place_call):
        mock_place_call.return_value = {'success': True, 'provider_call_id': 'abc-1'}
        response = self.client.post('/api/checkins/trigger-call/', {'uid': self.user.uid}, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(CallAttempt.objects.filter(user=self.user).count(), 1)

    def test_call_webhook_marks_safe(self):
        CallAttempt.objects.create(
            user=self.user,
            provider_call_id='call-safe',
            status='in_progress',
            attempt_number=1,
        )
        response = self.client.post(
            '/api/webhooks/call-status/',
            {'providerCallId': 'call-safe', 'speechText': "I am fine"},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.last_call_status, 'safe_confirmed')
        self.assertEqual(Checkin.objects.filter(user=self.user).count(), 1)

    @patch('api.services.sms_provider.SmsProvider.send_sms')
    @patch('api.services.voice_provider.VoiceProvider.place_checkin_call')
    def test_retry_then_escalate(self, mock_place_call, mock_send_sms):
        mock_place_call.return_value = {'success': True, 'provider_call_id': 'retry-1'}
        mock_send_sms.return_value = {'success': True, 'provider_message_id': 'sms-1'}

        first = CallAttempt.objects.create(
            user=self.user,
            provider_call_id='call-fail-1',
            status='in_progress',
            attempt_number=1,
        )
        first.completed_at = None
        first.save()

        response_1 = self.client.post(
            '/api/webhooks/call-status/',
            {'providerCallId': 'call-fail-1', 'status': 'no_answer'},
            format='json',
        )
        self.assertEqual(response_1.status_code, 200)
        self.assertEqual(response_1.data['result'], 'retrying')

        retry = CallAttempt.objects.filter(user=self.user).order_by('-attempt_number').first()
        retry.provider_call_id = 'call-fail-2'
        retry.save(update_fields=['provider_call_id'])

        response_2 = self.client.post(
            '/api/webhooks/call-status/',
            {'providerCallId': 'call-fail-2', 'status': 'no_answer'},
            format='json',
        )
        self.assertEqual(response_2.status_code, 200)
        self.assertEqual(response_2.data['result'], 'escalated')
        self.assertEqual(AlertEvent.objects.filter(user=self.user, status='sent').count(), 1)

    @patch('api.services.sms_provider.SmsProvider.send_sms')
    def test_sms_body_contains_greeting_and_location_link(self, mock_send_sms):
        mock_send_sms.return_value = {'success': True, 'provider_message_id': 'sms-1'}

        LocationSnapshot.objects.create(
            user=self.user,
            latitude=1.23,
            longitude=4.56,
        )

        response = self.client.post(
            '/api/checkins/escalate/',
            {'uid': self.user.uid, 'reason': 'no_answer'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        alert = AlertEvent.objects.filter(user=self.user, channel='sms').order_by('-created_at').first()
        self.assertIsNotNone(alert)

        self.assertIn('Hello John', alert.message)
        self.assertIn('SafeCheck tried to check on Viannie', alert.message)
        expected_link = 'https://maps.google.com/?q=1.23,4.56'
        self.assertIn(expected_link, alert.message)

    def test_upsert_profile_accepts_e164_emergency_phone(self):
        response = self.client.post(
            '/api/user/profile/',
            {
                'uid': 'e164-user',
                'full_name': 'Test User',
                'emergency_contact_country_code': 'UG',
                'emergency_contact_phone': '+256779697569',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        user = UserProfile.objects.get(uid='e164-user')
        self.assertEqual(user.emergency_contact_phone, '+256779697569')

    @patch('api.services.sms_provider.SmsProvider.send_sms')
    def test_escalation_normalizes_kin_number_to_e164(self, mock_send_sms):
        mock_send_sms.return_value = {'success': True, 'provider_message_id': 'sms-2'}
        self.user.emergency_contact_country_code = 'MW'
        self.user.emergency_contact_phone = '0779697569'
        self.user.save(update_fields=['emergency_contact_country_code', 'emergency_contact_phone'])

        response = self.client.post(
            '/api/checkins/escalate/',
            {'uid': self.user.uid, 'reason': 'no_answer'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        mock_send_sms.assert_called_once()
        recipient_arg = mock_send_sms.call_args.args[0]
        self.assertEqual(recipient_arg, '+265779697569')


class ScheduleEngineTests(TestCase):
    def setUp(self):
        self.user = UserProfile.objects.create(
            uid='sched-user',
            onboarding_completed=True,
            checkin_time=time(9, 30),
            timezone='UTC',
            checkin_frequency='Daily',
        )

    def test_compute_next_checkin_daily_utc(self):
        now = timezone.make_aware(dt_datetime(2026, 4, 29, 8, 0, 0))
        next_at = compute_next_checkin_at(self.user, now_utc=now)
        self.assertEqual(next_at.hour, 9)
        self.assertEqual(next_at.minute, 30)
        self.assertTrue(next_at > now)

    def test_is_due_when_scheduled_in_past(self):
        self.user.next_scheduled_checkin_at = timezone.now() - timezone.timedelta(minutes=5)
        self.user.save(update_fields=['next_scheduled_checkin_at'])
        self.assertTrue(is_due(self.user))

    def test_register_push_token_sets_fcm_and_schedule(self):
        client = APIClient()
        response = client.post(
            '/api/devices/register-push/',
            {
                'uid': self.user.uid,
                'fcm_token': 'test-fcm-token-abc',
                'platform': 'android',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertEqual(self.user.fcm_token, 'test-fcm-token-abc')
        self.assertIsNotNone(self.user.next_scheduled_checkin_at)

    @patch('api.services.push_provider.PushProvider.send_checkin_call_push')
    def test_scheduler_triggers_due_push(self, mock_push):
        mock_push.return_value = {'success': True, 'provider_message_id': 'push-1'}
        self.user.fcm_token = 'token-xyz'
        self.user.next_scheduled_checkin_at = timezone.now() - timezone.timedelta(minutes=1)
        self.user.save()

        from django.core.management import call_command

        call_command('run_checkin_scheduler')

        mock_push.assert_called_once()
        self.user.refresh_from_db()
        self.assertTrue(self.user.next_scheduled_checkin_at > timezone.now())

    @patch('api.services.safety_engine.escalate_to_next_of_kin')
    def test_scheduler_escalates_unanswered_push_after_grace(self, mock_escalate):
        self.user.fcm_token = 'token-xyz'
        self.user.grace_period_hours = 1
        self.user.last_push_sent_at = timezone.now() - timezone.timedelta(hours=2)
        self.user.pending_call_kit_id = 'ck-escalate-1'
        self.user.last_call_status = 'push_sent'
        self.user.next_scheduled_checkin_at = timezone.now() - timezone.timedelta(minutes=1)
        self.user.save()

        from django.core.management import call_command

        call_command('run_checkin_scheduler')

        mock_escalate.assert_called_once()
        self.user.refresh_from_db()
        self.assertIsNone(self.user.pending_call_kit_id)


class EmailVerificationTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    @patch('api.views.generate_code', return_value='123456')
    @patch('api.views.EmailProvider')
    def test_send_and_verify_email_code(self, mock_provider_cls, _mock_code):
        mock_provider_cls.return_value.send_verification_code.return_value = {'success': True}

        send_response = self.client.post(
            '/api/auth/send-email-code/',
            {'email': 'user@example.com', 'password': 'secret123'},
            format='json',
        )
        self.assertEqual(send_response.status_code, 200)
        verification_id = send_response.data['verificationId']
        self.assertTrue(verification_id.startswith('email-'))

        verify_response = self.client.post(
            '/api/auth/verify-email-code/',
            {
                'verificationId': verification_id,
                'email': 'user@example.com',
                'password': 'secret123',
                'code': '123456',
            },
            format='json',
        )
        self.assertEqual(verify_response.status_code, 200)
        self.assertIn('token', verify_response.data)
        self.assertEqual(verify_response.data['user']['email'], 'user@example.com')
        self.assertTrue(UserProfile.objects.filter(uid='user@example.com').exists())

    @patch('api.views.generate_code', return_value='123456')
    @patch('api.views.EmailProvider')
    def test_verify_rejects_wrong_code(self, mock_provider_cls, _mock_code):
        mock_provider_cls.return_value.send_verification_code.return_value = {'success': True}
        send_response = self.client.post(
            '/api/auth/send-email-code/',
            {'email': 'wrong@example.com', 'password': 'secret123'},
            format='json',
        )
        verification_id = send_response.data['verificationId']

        verify_response = self.client.post(
            '/api/auth/verify-email-code/',
            {
                'verificationId': verification_id,
                'email': 'wrong@example.com',
                'password': 'secret123',
                'code': '000000',
            },
            format='json',
        )
        self.assertEqual(verify_response.status_code, 400)

    @patch('api.views.generate_code', return_value='123456')
    @patch('api.views.EmailProvider')
    def test_verify_rejects_mismatched_email(self, mock_provider_cls, _mock_code):
        mock_provider_cls.return_value.send_verification_code.return_value = {'success': True}
        send_response = self.client.post(
            '/api/auth/send-email-code/',
            {'email': 'owner@example.com', 'password': 'secret123'},
            format='json',
        )
        verification_id = send_response.data['verificationId']

        verify_response = self.client.post(
            '/api/auth/verify-email-code/',
            {
                'verificationId': verification_id,
                'email': 'attacker@example.com',
                'password': 'secret123',
                'code': '123456',
            },
            format='json',
        )
        self.assertEqual(verify_response.status_code, 400)

    @patch('api.views.EmailProvider')
    def test_send_email_uses_html_provider(self, mock_provider_cls):
        mock_provider_cls.return_value.send_verification_code.return_value = {'success': True}

        with self.settings(DEBUG=False, SAFECHECK_ALLOW_MOCK_AUTH=False):
            response = self.client.post(
                '/api/auth/send-email-code/',
                {'email': 'prod@example.com', 'password': 'secret123'},
                format='json',
            )

        self.assertEqual(response.status_code, 200)
        mock_provider_cls.return_value.send_verification_code.assert_called_once()
        args, _kwargs = mock_provider_cls.return_value.send_verification_code.call_args
        self.assertEqual(args[0], 'prod@example.com')
        self.assertRegex(args[1], r'^\d{6}$')


class PasswordResetTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        from django.contrib.auth.hashers import make_password

        UserProfile.objects.create(
            uid='reset@example.com',
            email='reset@example.com',
            password=make_password('oldpass123'),
            onboarding_completed=True,
        )

    @patch('api.views.generate_code', return_value='123456')
    @patch('api.views.EmailProvider')
    def test_forgot_password_and_reset(self, mock_provider_cls, _mock_code):
        mock_provider_cls.return_value.send_verification_code.return_value = {'success': True}

        send_response = self.client.post(
            '/api/auth/forgot-password/',
            {'email': 'reset@example.com'},
            format='json',
        )
        self.assertEqual(send_response.status_code, 200)
        verification_id = send_response.data['verificationId']
        self.assertTrue(verification_id.startswith('reset-'))

        reset_response = self.client.post(
            '/api/auth/reset-password/',
            {
                'verificationId': verification_id,
                'email': 'reset@example.com',
                'code': '123456',
                'newPassword': 'newpass456',
            },
            format='json',
        )
        self.assertEqual(reset_response.status_code, 200)
        self.assertIn('token', reset_response.data)

        user = UserProfile.objects.get(uid='reset@example.com')
        from django.contrib.auth.hashers import check_password

        self.assertTrue(check_password('newpass456', user.password))
        self.assertFalse(check_password('oldpass123', user.password))

    def test_forgot_password_unknown_email(self):
        response = self.client.post(
            '/api/auth/forgot-password/',
            {'email': 'missing@example.com'},
            format='json',
        )
        self.assertEqual(response.status_code, 404)
