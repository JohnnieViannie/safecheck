# Update production backend (safebangle.com)

The Flutter app and Blaces web share **one** Django project: [`backend/`](../backend/).

## Quick check

```bash
curl https://server.safebangle.com/api/health/
# {"status":"ok","service":"safebangle"}

curl "https://server.safebangle.com/api/journeys/active/?uid=test@example.com"
# {"active":false}
```

App default API root: `https://server.safebangle.com/api`

## Deploy

```bash
cd /path/to/safeBangle
git pull

cd backend
source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput

# Point systemd WorkingDirectory at .../safeBangle/backend
sudo systemctl restart safecheck
```

### Scheduler

```bash
cd /path/to/safeBangle/backend
source venv/bin/activate
python manage.py run_checkin_scheduler
```

### Optional: import old SafeCheck DB once

```bash
LEGACY_DATABASE_URL=postgresql://... python manage.py migrate_safecheck_users
```

Next of kin is shared: `TrustedContact` feeds both Blaces web and the mobile profile.
