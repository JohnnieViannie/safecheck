# SafeCheck (Flutter Mobile MVP)

SafeCheck is a mobile-first Flutter app (Android + iOS) with:

- Phone OTP authentication (Firebase Auth)
- First-time onboarding (saved in Firestore)
- Home check-in flow with local countdown simulation
- Missed check-in fallback screen
- Local notification reminders

## Tech stack

- Flutter (stable)
- Dart (null safety)
- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `shared_preferences`
- `flutter_local_notifications`

## 1) Install dependencies
   
```bash
flutter pub get
```

## 2) Firebase setup (required)

### Create Firebase project

1. Go to [Firebase Console](https://console.firebase.google.com/).
2. Create a new project named `SafeCheck`.
3. Add Android and iOS apps in project settings.

### Enable authentication

1. Firebase Console -> Authentication -> Sign-in method.
2. Enable **Phone** sign-in provider.

### Enable Firestore

1. Firebase Console -> Firestore Database.
2. Create database (start in test mode for development).

### Configure app with FlutterFire

1. Install FlutterFire CLI:
   ```bash
   dart pub global activate flutterfire_cli
   ```
2. From project root, run:
   ```bash
   flutterfire configure
   ```
   This **overwrites** `lib/firebase_options.dart` with real `apiKey`, `appId`, `projectId`, etc. The app reads these in `main.dart` via `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` so Android does not need a separate `values.xml` for startup.
3. Ensure Android `applicationId` and iOS bundle ID match what you registered in Firebase.

Until `firebase_options.dart` is configured (no `REPLACE_*` placeholders), the app shows an on-screen message instead of a black screen.

### Phone auth notes

- Android: add SHA-1/SHA-256 fingerprints in Firebase project settings.
- iOS: configure APNs and push notification capabilities for production OTP reliability.

## 3) Run app

```bash
flutter run
```

## App flow

1. Welcome -> Phone input -> OTP verification
2. After login:
   - New user -> onboarding
   - Existing user with `onboardingCompleted = true` -> home
   - Existing user without onboarding complete -> onboarding
3. Home:
   - Countdown timer to next check-in
   - Tap "I'm Safe" to reset
4. If timer expires:
   - Navigate to missed check-in screen
