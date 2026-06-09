"""Direct Africa's Talking bulk SMS test. Run from server/: python scripts/test_at_sms.py"""
import json
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

# Load .env
dotenv = BASE_DIR / '.env'
if dotenv.exists():
    for raw_line in dotenv.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))

import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'server.settings')
django.setup()

from api.services.sms_provider import SmsProvider

to = sys.argv[1] if len(sys.argv) > 1 else '+256779697569'
message = (
    sys.argv[2]
    if len(sys.argv) > 2
    else 'SafeBangle bulk SMS test - please confirm receipt.'
)

print('=== Config ===')
print('username:', os.getenv('AT_USERNAME', ''))
print('senderId:', os.getenv('AT_SENDER_ID', '') or '(not set — required for bulk API)')
print('bulk url:', os.getenv('AT_SMS_BULK_URL', 'https://api.africastalking.com/version1/messaging/bulk'))
print('to:', to)
print()

result = SmsProvider().send_sms(to, message)
print('=== Result ===')
print(json.dumps(result, indent=2))
