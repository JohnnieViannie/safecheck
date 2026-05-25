# Server-driven check-in calls (VPS)

SafeCheck can trigger in-app check-in calls even when the app has not been opened for a long time. The **VPS** runs a scheduler every few minutes; it sends **FCM high-priority pushes** that wake the app and show the CallKit incoming-call UI.

Local Android alarms remain a **backup** only.

## 1. Requirements

- Always-on VPS with public HTTPS URL (for webhooks if needed)
- MySQL/Postgres configured in `server/.env`
- **Firebase project** with Cloud Messaging enabled
- Flutter app built with Firebase config (see below)

## 2. Server environment variables

Add to `server/.env` on the VPS:

```env
# Africa's Talking (SMS escalation)
AT_USERNAME=your_username
AT_API_KEY=your_api_key
AT_SENDER_ID=your_approved_sender_id

# Public URL of this API (no trailing slash)
CALLBACK_BASE_URL=https://api.yourdomain.com

# Firebase Admin (service account JSON file path on VPS)
FIREBASE_CREDENTIALS_PATH=/etc/safecheck/firebase-service-account.json
# Or inline JSON (escape carefully):
# FIREBASE_CREDENTIALS_JSON={"type":"service_account",...}
```

Create the service account in Firebase Console → Project settings → Service accounts → Generate new private key. Grant permission to send FCM messages.

Install Python deps on VPS:

```bash
pip install -r requirements.txt
python manage.py migrate
```

## 3. Cron (every 5 minutes)

```bash
crontab -e
```

Add:

```cron
*/5 * * * * cd /path/to/safeBangle/server && /path/to/venv/bin/python manage.py run_checkin_scheduler >> /var/log/safecheck-scheduler.log 2>&1
```

Dry run (no pushes sent):

```bash
python manage.py run_checkin_scheduler --dry-run
```

## 4. Flutter app Firebase setup

1. Create/configure Firebase project and add Android + iOS apps (`com.safecheck.app`).
2. Download `google-services.json` → `app/android/app/`
3. Download `GoogleService-Info.plist` → `app/ios/Runner/`
4. Apply the Google Services Gradle plugin in Android (see Firebase Flutter setup docs).
5. Build/run with dart-defines (or use `flutterfire configure` and replace `lib/firebase_options.dart`):

```bash
flutter run \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_IOS_BUNDLE_ID=com.safecheck.app
```

On login, the app registers its FCM token via `POST /api/devices/register-push/`.

## 5. How scheduling works

- User profile stores `checkin_time`, `timezone`, `checkin_frequency`, `next_scheduled_checkin_at`, `fcm_token`.
- Scheduler finds users where `next_scheduled_checkin_at <= now` and sends push `type=checkin_call`.
- After push, server advances `next_scheduled_checkin_at` (daily or weekly).
- If user does not confirm within `grace_period_hours`, server escalates SMS to next of kin.

## 6. Smoke test

1. Set check-in time to 2–3 minutes ahead in the app (Settings).
2. Confirm app logged in and FCM token registered (check DB `fcm_token` not null).
3. Force-close the app.
4. Wait for cron cycle — CallKit UI should appear without opening the app.
5. Check VPS log: `Scheduler done: pushed=1 ...`

## 7. Limits

- Phone **powered off**: no calls until power on (same as alarms).
- **App-only** (no PSTN): depends on FCM + OEM battery settings. Users should disable battery optimization for SafeCheck ([dontkillmyapp.com](https://dontkillmyapp.com)).
- iOS may need additional VoIP push setup for CallKit when force-quit (future enhancement).
