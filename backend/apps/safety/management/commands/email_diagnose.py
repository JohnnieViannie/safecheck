import email
import imaplib
import re
import smtplib
import socket
import ssl
import time
from datetime import timedelta
from email.message import EmailMessage
from email.policy import default as default_policy
from email.utils import formatdate, make_msgid, parseaddr

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

REASON_RE = re.compile(
    r"^(Final-Recipient|Action|Status|Remote-MTA|Diagnostic-Code)\s*:"
    r"|\b(5\d\d|4\d\d)[ -]\d\.\d\.\d"
    r"|rejected|blocked|denied|suspended|exceeded|unauthenticated|retry time",
    re.IGNORECASE,
)
BOUNCE_RE = re.compile(
    r"mailer-daemon|postmaster|mail delivery|undeliver|delivery status|returned mail|failure notice",
    re.IGNORECASE,
)


class Command(BaseCommand):
    help = (
        "Print every SMTP server reply and any bounce reasons from the sender's mailbox "
        "(no secrets). Nothing is sent unless --send is given."
    )

    def add_arguments(self, parser):
        parser.add_argument("--send", metavar="EMAIL", help="Send one test email to this address")
        parser.add_argument(
            "--bounces",
            action="store_true",
            help="Log in to the sender's mailbox read-only and print bounce reasons",
        )
        parser.add_argument("--days", type=int, default=7, help="How far back to look for bounces")
        parser.add_argument("--imap-port", type=int, default=993)

    def handle(self, *args, **options):
        self.stdout.write("=== Settings ===")
        self.stdout.write(f"EMAIL_BACKEND: {settings.EMAIL_BACKEND}")
        self.stdout.write(f"EMAIL_HOST: {settings.EMAIL_HOST}:{settings.EMAIL_PORT}")
        self.stdout.write(f"EMAIL_HOST_USER: {settings.EMAIL_HOST_USER}")
        self.stdout.write(f"DEFAULT_FROM_EMAIL: {settings.DEFAULT_FROM_EMAIL}")
        self.stdout.write(f"EMAIL_TIMEOUT: {settings.EMAIL_TIMEOUT}")

        self._smtp(options.get("send"))
        if options["bounces"]:
            self._bounces(options["days"], options["imap_port"])
        else:
            self.stdout.write("\nAdd --bounces to print failure reasons from the mailbox.")

    def _smtp(self, to_email):
        self.stdout.write("\n=== SMTP conversation ===")
        start = time.time()

        def reply(step, result):
            self.stdout.write(f"[{time.time() - start:5.1f}s] {step}: {result}")

        try:
            client = smtplib.SMTP(
                settings.EMAIL_HOST, settings.EMAIL_PORT, timeout=settings.EMAIL_TIMEOUT
            )
            reply("connected", "server greeted us")
            client.ehlo()
            if settings.EMAIL_USE_TLS:
                reply("STARTTLS", client.starttls(context=ssl.create_default_context()))
                client.ehlo()
            reply("LOGIN", client.login(settings.EMAIL_HOST_USER, settings.EMAIL_HOST_PASSWORD))
            if to_email:
                sender = parseaddr(settings.DEFAULT_FROM_EMAIL)[1]
                message = EmailMessage()
                message["Subject"] = f"SafeBangle diagnostic test {time.strftime('%H:%M:%S')}"
                message["From"] = settings.DEFAULT_FROM_EMAIL
                message["To"] = to_email
                message["Date"] = formatdate(localtime=True)
                message["Message-ID"] = make_msgid(domain=sender.split("@")[-1])
                message.set_content("SafeBangle diagnostic test email. No action needed.")
                reply("MAIL FROM", client.mail(sender))
                reply("RCPT TO", client.rcpt(to_email))
                reply("DATA", client.data(message.as_bytes()))
                self.stdout.write(
                    "A 250 reply only means the mail server accepted the email, not that it "
                    "was delivered."
                )
            client.quit()
        except (smtplib.SMTPException, socket.error, ssl.SSLError) as exc:
            self.stderr.write(self.style.ERROR(f"FAILED: {type(exc).__name__}: {exc}"))

    def _bounces(self, days, imap_port):
        self.stdout.write(f"\n=== Bounces in {settings.EMAIL_HOST_USER} (last {days} days) ===")
        since = (timezone.now() - timedelta(days=days)).strftime("%d-%b-%Y")
        try:
            box = imaplib.IMAP4_SSL(settings.EMAIL_HOST, imap_port, timeout=settings.EMAIL_TIMEOUT)
            box.login(settings.EMAIL_HOST_USER, settings.EMAIL_HOST_PASSWORD)
        except (imaplib.IMAP4.error, socket.error, ssl.SSLError) as exc:
            self.stderr.write(self.style.ERROR(f"Mailbox login FAILED: {type(exc).__name__}: {exc}"))
            return

        found = 0
        try:
            status, _ = box.select("INBOX", readonly=True)
            if status != "OK":
                self.stderr.write(self.style.ERROR("Could not open INBOX"))
                return
            _, data = box.search(None, "SINCE", since)
            for num in data[0].split():
                _, headers = box.fetch(num, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
                if not BOUNCE_RE.search(headers[0][1].decode("utf-8", "replace")):
                    continue
                _, raw = box.fetch(num, "(BODY.PEEK[])")
                found += 1
                self._print_bounce(email.message_from_bytes(raw[0][1], policy=default_policy))
        finally:
            box.logout()

        if not found:
            self.stdout.write("No bounce messages found.")
            self.stdout.write(
                "The real reason is then only in the mail host's delivery logs. "
                "Ask them to trace the id from the DATA reply above."
            )

    def _print_bounce(self, message):
        self.stdout.write("")
        self.stdout.write(f"Date: {message['Date']}")
        self.stdout.write(f"From: {message['From']}")
        self.stdout.write(f"Subject: {message['Subject']}")
        seen = set()
        for part in message.walk():
            if part.get_content_type() not in ("text/plain", "message/delivery-status"):
                continue
            if part.get_content_type() == "message/delivery-status":
                text = "\n".join(str(block) for block in part.iter_parts()) if part.is_multipart() else ""
            else:
                text = part.get_content()
            for line in text.splitlines():
                line = line.strip()
                if line and line not in seen and REASON_RE.search(line):
                    seen.add(line)
                    self.stdout.write(self.style.WARNING(f"  {line[:300]}"))
