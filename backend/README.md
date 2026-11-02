# SafeBangle Backend (unified)

Single Django API for the **SafeCheck mobile app** and **Blaces web**.

```bash
cd backend   # from repo root
python -m venv venv
venv\Scripts\activate   # or: source venv/bin/activate
pip install -r requirements.txt
copy .env.example .env
python manage.py migrate
python manage.py seed_demo_data
python manage.py runserver 127.0.0.1:8001
```

API: http://127.0.0.1:8001/api/health/

- Mobile: `/api/auth/send-email-code/`, check-ins, journeys, vault, FCM
- Blaces: `/api/auth/login/`, orgs, bracelets, incidents
- Shared NOK: `people.TrustedContact`

Scheduler: `python manage.py run_checkin_scheduler`  
Legacy import: `python manage.py migrate_safecheck_users` (needs `LEGACY_DATABASE_URL`)

Full webhook / bracelet SOS examples: see git history or ask in-repo docs under `deploy/`.
