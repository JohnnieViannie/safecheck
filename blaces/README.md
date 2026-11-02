# SafeBangle Platform (web UI)

The Django API lives at the **repo-root** [`backend/`](../backend/) folder (shared with the mobile app).

```text
safeBangle/
├── backend/     # Django + DRF (mobile + Blaces)
└── blaces/
    └── ui/      # React + TypeScript + Tailwind
```

## Quick start

### Backend

```bash
cd ../backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
python manage.py migrate
python manage.py seed_demo_data
python manage.py runserver 127.0.0.1:8001
```

### Frontend

```bash
cd ui
npm install
npm run dev
```

Open http://localhost:3000

Set `VITE_API_BASE_URL=http://127.0.0.1:8001/api` in `ui/.env`.

## Demo logins

| Email | Password | Portal |
|-------|----------|--------|
| admin@safebangle.local | Admin123! | Platform admin |
| orgadmin@demo.local | Demo123! | Org |
| individual@demo.local | Demo123! | Individual |
