# Server-driven check-in calls (VPS)

SafeCheck triggers in-app check-in calls via a VPS scheduler that sends **FCM**
high-priority pushes. Local Android alarms remain a backup.

## 1. Requirements

- Always-on VPS with public HTTPS
- Postgres/MySQL in `backend/.env`
- Firebase project with Cloud Messaging
- Flutter app with Firebase config

## 2. Environment (`backend/.env`)

```env
SMS_PROVIDER=africastalking
AT_USERNAME=your_username
AT_API_KEY=your_api_key
AT_SENDER_ID=your_approved_sender_id
CALLBACK_BASE_URL=https://safebangle.com
FIREBASE_CREDENTIALS_PATH=/etc/safecheck/firebase-service-account.json
```

```bash
cd backend
pip install -r requirements.txt
python manage.py migrate
```

## 3. Cron (every 5 minutes)

```cron
*/5 * * * * cd /path/to/safeBangle/backend && /path/to/venv/bin/python manage.py run_checkin_scheduler >> /var/log/safecheck-scheduler.log 2>&1
```

Birthday wishes, every hour (each person gets one SMS a year, at about 8am their time):

```cron
0 * * * * cd /path/to/safeBangle/backend && /path/to/venv/bin/python manage.py send_birthday_wishes >> /var/log/safecheck-birthdays.log 2>&1
```

Dry run:

```bash
python manage.py run_checkin_scheduler --dry-run
```

## 4. How it works

- Profile stores `checkin_time`, `timezone`, `checkin_frequency`, `next_scheduled_checkin_at`, `fcm_token`
- Scheduler pushes `type=checkin_call`, then advances the schedule
- Missed within grace period → SMS to `TrustedContact` / next of kin
