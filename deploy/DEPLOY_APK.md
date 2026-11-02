# Release APK — build & host at safebangle.com/safecheck.apk

## App API (production)

The release APK is built with:

```
https://server.safebangle.com/api
```

This matches `app/lib/services/endpoints.dart` default and your Django routes at `/api/`.

---

## 1. Build APK (Windows)

From repo root:

```powershell
cd app\scripts
.\build_release.ps1 -Target apk -ApiBaseUrl "https://server.safebangle.com/api"
```

Output:

- `deploy/public/safecheck.apk` — upload this file
- `app/build/app/outputs/flutter-apk/app-release.apk` — same build

**Play Store signing (optional):** copy `app/android/key.properties.example` → `key.properties` and add your upload keystore before building.

---

## 2. VPS — one-time nginx setup

SSH into the server:

```bash
mkdir -p /var/www/safecheck/public
chmod 755 /var/www/safecheck/public
```

Add the contents of `deploy/nginx-safecheck-apk.conf` to your **safebangle.com** nginx site config (inside the `server { }` block that already serves the site).

Then:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Ensure `/api/` proxies to gunicorn (`safecheck` service) and `/safecheck.apk` serves the static file.

---

## 3. Upload APK

From your PC (replace with your VPS IP or hostname):

```powershell
scp "c:\Users\User\Downloads\Lane\safeBangle\deploy\public\safecheck.apk" root@YOUR_VPS:/var/www/safecheck/public/safecheck.apk
```

On VPS:

```bash
chmod 644 /var/www/safecheck/public/safecheck.apk
```

---

## 4. Test

```bash
curl -I https://safebangle.com/safecheck.apk
curl -I https://server.safebangle.com/api/health/
```

Browser: **https://safebangle.com/safecheck.apk** — should download the APK.

Install on Android (enable “Install unknown apps” for the browser/files app).

---

## Rebuild after code changes

```powershell
cd app\scripts
.\build_release.ps1 -Target apk
scp ..\..\deploy\public\safecheck.apk root@YOUR_VPS:/var/www/safecheck/public/safecheck.apk
```
