# SafeBangle Production Checklist

## 1. Backend (Django)

1. Copy `server/.env.example` to `server/.env` and set:
   - `DJANGO_DEBUG=False`
   - `SAFECHECK_ALLOW_MOCK_AUTH=false`
   - Strong `DJANGO_SECRET_KEY`
   - `DJANGO_DEBUG=False` (enforces safebangle.com hosts only; no `*` or localhost)
   - Optional `DJANGO_ALLOWED_HOSTS` — defaults to `safebangle.com`, `www.safebangle.com`, `api.safebangle.com`
   - Optional `DJANGO_CSRF_TRUSTED_ORIGINS` — defaults to `https://safebangle.com`, `https://www.safebangle.com`, `https://api.safebangle.com`
   - Production database (`DATABASE_URL` recommended)
   - SMTP vars (`EMAIL_HOST`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `EMAIL_FROM`)
   - Africa's Talking credentials for SMS/voice
   - `CALLBACK_BASE_URL` to your public HTTPS API
   - `FIREBASE_CREDENTIALS_PATH` for server push fallback

2. Deploy the API behind HTTPS (e.g. `https://api.safebangle.com/api`).

3. Run the check-in scheduler every minute (see `server/SCHEDULER_DEPLOY.md`):
   ```powershell
   cd server
   .\run_scheduler.ps1
   ```

4. Rotate any credentials that were ever committed to git.

## 2. Flutter app — release build

### Android

1. Create an upload keystore:
   ```powershell
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Copy `app/android/key.properties.example` to `app/android/key.properties` and point `storeFile` at your `.jks`.

3. Build release APK/AAB:
   ```powershell
   cd app
   flutter pub get
   flutter build appbundle `
     --dart-define=SAFECHECK_API_BASE_URL=https://api.safebangle.com/api `
     --dart-define=SAFECHECK_ENV=prod
   ```

   Output: `app/build/app/outputs/bundle/release/app-release.aab`

### iOS

1. Run `flutterfire configure` and add `GoogleService-Info.plist` to `ios/Runner/`.
2. Set your Apple Developer `DEVELOPMENT_TEAM` in Xcode.
3. Enable Push Notifications and Sign in with Apple capabilities.
4. Build:
   ```bash
   flutter build ipa \
     --dart-define=SAFECHECK_API_BASE_URL=https://api.safebangle.com/api \
     --dart-define=SAFECHECK_ENV=prod
   ```

## 3. Build-time defines

| Define | Purpose | Production example |
|--------|---------|-------------------|
| `SAFECHECK_API_BASE_URL` | Backend API root | `https://api.safebangle.com/api` |
| `SAFECHECK_ENV` | `prod` or `dev` | `prod` |
| `SAFECHECK_GOOGLE_SERVER_CLIENT_ID` | Google Sign-In web client | From Google Cloud Console |
| `SAFECHECK_TERMS_URL` | Terms link on welcome screen | `https://safebangle.com/terms` |
| `SAFECHECK_PRIVACY_URL` | Privacy link | `https://safebangle.com/privacy` |
| `FIREBASE_API_KEY` | Override Firebase config | From Firebase console |
| `FIREBASE_APP_ID` | Platform app ID | From Firebase console |

Defaults live in `app/lib/services/endpoints.dart` and `app/lib/config/app_config.dart`.

## 4. Pre-launch verification

- [ ] Email sign-in sends a real code (not `123456`) with `DJANGO_DEBUG=False`
- [ ] Google Sign-In works on a physical Android device (release build)
- [ ] FCM push check-in fires when app is killed
- [ ] Local alarm rings when phone sleeps (grant exact alarm + battery exemption)
- [ ] Missed check-in escalates SMS to next of kin
- [ ] Terms and Privacy links open in browser
- [ ] Scheduler cron is running on the server

## 5. Store submission notes

- **Android**: Upload `app-release.aab` to Play Console. Declare background location, alarms, and full-screen intent usage.
- **iOS**: Complete App Privacy questionnaire. Add `NSLocationAlwaysAndWhenInUseUsageDescription` usage justification.
- **Apple Sign-In**: Required if Google Sign-In is offered — integrate `sign_in_with_apple` before iOS launch.
