import logging
import smtplib
import ssl
from email.message import EmailMessage
from typing import Dict, List

from django.template.loader import render_to_string

from api.services.email_config import EmailConfig

logger = logging.getLogger(__name__)

_SMTP_TIMEOUT_SECONDS = 30


class EmailProvider:
    def _send_via_smtp(self, message: EmailMessage) -> None:
        host = EmailConfig.host()
        port = EmailConfig.port()
        username = EmailConfig.username()
        password = EmailConfig.password()

        if EmailConfig.use_ssl():
            with smtplib.SMTP_SSL(host, port, timeout=_SMTP_TIMEOUT_SECONDS) as smtp:
                smtp.login(username, password)
                smtp.send_message(message)
            return

        with smtplib.SMTP(host, port, timeout=_SMTP_TIMEOUT_SECONDS) as smtp:
            smtp.ehlo()
            if EmailConfig.use_tls():
                smtp.starttls(context=ssl.create_default_context())
                smtp.ehlo()
            smtp.login(username, password)
            smtp.send_message(message)

    def send_verification_code(
        self,
        to_email: str,
        code: str,
        *,
        purpose: str = 'verify',
    ) -> Dict[str, str]:
        if not EmailConfig.is_configured():
            logger.error(
                'Email not configured (EMAIL_HOST, EMAIL_HOST_USER, EMAIL_HOST_PASSWORD, EMAIL_FROM). '
                'Cannot send verification code to %s',
                to_email,
            )
            return {
                'success': False,
                'error': 'Email delivery is not configured on the server.',
            }

        expiry_minutes = EmailConfig.verification_expiry_minutes()
        if purpose == 'reset':
            subject = EmailConfig.password_reset_subject()
            headline = 'Reset your password'
            subtitle = 'Enter this code in SafeBangle to choose a new password.'
            body_lead = 'Use the 6-digit code below to reset the password for'
            plain_intro = f'Reset your {EmailConfig.from_name()} password with code {code}.'
        else:
            subject = EmailConfig.verification_subject()
            headline = 'Verify your email'
            subtitle = 'Enter this code in SafeBangle to continue.'
            body_lead = 'Use the 6-digit code below to verify'
            plain_intro = f'Your {EmailConfig.from_name()} verification code is {code}.'

        code_digits: List[str] = list(str(code).strip().zfill(6)[:6])

        plain_text = (
            f'{plain_intro}\n\n'
            f'Enter this 6-digit code in the app for {to_email}.\n'
            f'The code expires in {expiry_minutes} minutes.\n\n'
            'If you did not request this, you can ignore this email.'
        )

        html_body = render_to_string(
            'emails/verification_code.html',
            {
                'subject': subject,
                'headline': headline,
                'subtitle': subtitle,
                'body_lead': body_lead,
                'recipient_email': to_email,
                'code': code,
                'code_digits': code_digits,
                'expiry_minutes': expiry_minutes,
                'brand_name': EmailConfig.from_name(),
            },
        )

        message = EmailMessage()
        message['Subject'] = subject
        message['From'] = EmailConfig.formatted_from()
        message['To'] = to_email
        message.set_content(plain_text)
        message.add_alternative(html_body, subtype='html')

        try:
            self._send_via_smtp(message)
            return {'success': True}
        except Exception as exc:
            logger.exception('Failed to send verification email to %s', to_email)
            return {'success': False, 'error': str(exc)}
