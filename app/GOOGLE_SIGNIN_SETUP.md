# Google Sign-In setup (Android)

Google Sign-In is failing because OAuth is not fully configured for the Firebase project used by this app.

## Error `[28444] Developer console is not set up correctly`

This means Google Play Services cannot match your app’s signing certificate to an **Android OAuth client**.

Your `google-services.json` has a **Web client** (`client_type: 3`) but is **missing an Android client** (`client_type: 1` with your SHA-1). That Android client is created when you add SHA-1 in Firebase.

### Fix (required)

1. Firebase Console → **safecheck-c4fa6** → **Project settings** → your Android app
2. Under **SHA certificate fingerprints**, click **Add fingerprint** and paste:

   **Debug SHA-1** (for `flutter run` on your PC):

   ```
   2E:5B:1C:24:A6:78:9F:5A:D5:08:4A:33:29:6E:41:B0:88:3D:31:58
   ```

3. Wait 1–2 minutes, then **re-download** `google-services.json`
4. Replace `app/android/app/google-services.json` and `app/google-services.json`
5. After re-download, `oauth_client` should include **two** entries:
   - `client_type: 1` (Android, with `certificate_hash`)
   - `client_type: 3` (Web)
6. **Uninstall** the app from your phone, then:

   ```powershell
   cd app
   flutter clean
   flutter run
   ```

## What we found

| Issue | Current state |
|-------|----------------|
| Firebase project | `safecheck-c4fa6` (`google-services.json`) |
| `oauth_client` in `google-services.json` | **Empty `[]`** — no Web/Android OAuth clients |
| `serverClientId` in app | Points to project `safecheck-493610` (different project) |
| Package name | `com.safecheck.app` |

The app and Firebase must use OAuth clients from the **same** Google Cloud / Firebase project.

## Fix in Firebase Console

1. Open [Firebase Console](https://console.firebase.google.com/) → project **safecheck-c4fa6**.
2. **Authentication** → **Sign-in method** → enable **Google**.
3. **Project settings** → **Your apps** → Android app `com.safecheck.app`:
   - Add **SHA-1** fingerprint (debug keystore):

   ```
   2E:5B:1C:24:A6:78:9F:5A:D5:08:4A:33:29:6E:41:B0:88:3D:31:58
   ```

   - Add **SHA-256** (recommended):

   ```
   E7:26:FF:11:0E:5D:9F:B9:76:D5:DD:E9:4C:94:A2:CC:66:51:E6:C1:C6:A5:15:4E:C6:B2:A7:E6:58:18:C1:C9
   ```

   For release builds, also add your upload keystore SHA-1.

4. In [Google Cloud Console](https://console.cloud.google.com/) (same project **safecheck-c4fa6**):
   - **APIs & Services** → **Credentials**
   - Ensure there is a **Web application** OAuth 2.0 client (type Web, `client_type: 3` in `google-services.json`).

5. Re-download `google-services.json` from Firebase and replace:
   - `app/android/app/google-services.json`
   - `app/google-services.json`

   After a correct download, `oauth_client` should **not** be empty.

6. Copy the **Web client ID** from Credentials (ends with `.apps.googleusercontent.com`) and run the app with:

   ```powershell
   flutter run --dart-define=SAFECHECK_GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
   ```

   Or update the default in `app/lib/config/app_config.dart`.

7. Uninstall the app and reinstall (native Google config is cached):

   ```powershell
   flutter clean
   flutter run
   ```

## Verify API is reachable

Google may succeed but login still fails if the backend is unreachable. Default API URL is `https://safebangle.com/api`. For local dev:

```powershell
flutter run --dart-define=SAFECHECK_API_BASE_URL=http://YOUR_LAN_IP:8000/api
```

Ensure Django is running and `DJANGO_DEBUG=True` (or `SAFECHECK_ALLOW_MOCK_AUTH=true`) if testing without full production auth.

## Get your debug SHA-1 (Windows)

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```
