"""Branded SafeBangle transactional emails."""
from __future__ import annotations

from django.conf import settings
from django.core.mail import EmailMultiAlternatives


def _brand_html(*, title: str, intro: str, code: str, minutes: int, footer_note: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
</head>
<body style="margin:0;padding:0;background:#f3f5f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#3d2a2a;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f5f8;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0;">
          <tr>
            <td style="background:linear-gradient(160deg,#0b5fa5 0%,#084a82 60%,#3d2a2a 100%);padding:28px 32px;text-align:center;">
              <div style="font-family:Georgia,'Times New Roman',serif;font-size:28px;letter-spacing:-0.02em;">
                <span style="color:#ffb4b7;">Safe</span><span style="color:#ffffff;">Bangle</span>
              </div>
              <p style="margin:10px 0 0;color:#dbeafe;font-size:13px;">Bracelet safety platform</p>
            </td>
          </tr>
          <tr>
            <td style="padding:32px;">
              <h1 style="margin:0 0 12px;font-size:22px;line-height:1.3;color:#3d2a2a;">{title}</h1>
              <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#64748b;">{intro}</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td align="center" style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:20px;">
                    <p style="margin:0 0 8px;font-size:12px;letter-spacing:0.08em;text-transform:uppercase;color:#64748b;font-weight:600;">Your code</p>
                    <p style="margin:0;font-size:36px;letter-spacing:0.28em;font-weight:700;color:#0b5fa5;font-family:ui-monospace,Consolas,monospace;">{code}</p>
                  </td>
                </tr>
              </table>
              <p style="margin:24px 0 0;font-size:14px;line-height:1.6;color:#64748b;">
                This code expires in <strong style="color:#3d2a2a;">{minutes} minutes</strong>.
                If you did not request this, you can ignore this email.
              </p>
              <p style="margin:16px 0 0;font-size:13px;line-height:1.5;color:#94a3b8;">{footer_note}</p>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 32px 24px;border-top:1px solid #e2e8f0;text-align:center;">
              <p style="margin:0;font-size:12px;color:#94a3b8;">© SafeBangle · Secure access · Incident response</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def send_branded_code_email(*, to_email: str, code: str, purpose: str) -> None:
    """
    purpose: 'email verification' | 'password reset'
    """
    minutes = getattr(settings, "EMAIL_CODE_EXPIRY_MINUTES", 15)
    if purpose == "password reset":
        subject = "Your SafeBangle password reset code"
        title = "Reset your password"
        intro = "Use this code to set a new password for your SafeBangle account."
        footer = "For your security, never share this code with anyone."
        plain = (
            f"SafeBangle password reset\n\n"
            f"Your code is: {code}\n"
            f"It expires in {minutes} minutes.\n\n"
            f"If you did not request this, ignore this email."
        )
    else:
        subject = "Your SafeBangle verification code"
        title = "Verify your email"
        intro = "Welcome to SafeBangle. Enter this code to verify your email and activate your account."
        footer = "Once verified, you can sign in to your console."
        plain = (
            f"SafeBangle email verification\n\n"
            f"Your code is: {code}\n"
            f"It expires in {minutes} minutes.\n\n"
            f"If you did not create an account, ignore this email."
        )

    html = _brand_html(
        title=title,
        intro=intro,
        code=code,
        minutes=minutes,
        footer_note=footer,
    )

    from_email = settings.DEFAULT_FROM_EMAIL
    msg = EmailMultiAlternatives(
        subject=subject,
        body=plain,
        from_email=from_email,
        to=[to_email],
    )
    msg.attach_alternative(html, "text/html")
    msg.send(fail_silently=False)
