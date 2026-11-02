# Backend merge verification

Canonical API folder: **`backend/`** only.

## Moved / present

| Area | Location |
|------|----------|
| Blaces apps (accounts, orgs, people, devices, alerts, incidents, …) | `backend/apps/*` |
| Mobile SafeCheck API | `backend/apps/mobile_compat/` |
| Safety profile, escalation, SMS audit | `backend/apps/safety/` |
| Check-ins + scheduler | `backend/apps/checkins/` (+ `run_checkin_scheduler`) |
| Journeys / vault / FCM | `backend/apps/journeys`, `vault`, `push` |
| Deploy helpers | `backend/setup.ps1`, `run_scheduler.ps1`, `SCHEDULER_DEPLOY.md` |
| SMTP smoke test | `python manage.py test_email you@example.com` |
| Legacy user import | `python manage.py migrate_safecheck_users` |
| Env | `backend/.env` (present) |

URL parity vs old `server/api/urls.py`: **50 routes checked, none missing** (forgot/reset on accounts; bracelet incidents stay Blaces).

## Intentionally NOT copied (safe to drop with legacy folder)

- Old Django migrations `api/migrations/0001–0014` (replaced by new app migrations)
- Old `api/tests.py` (needs rewrite against new models)
- `venv/` inside legacy tree
- Binary `safebangle` helper from old server
- Admin SMS change_list template (optional polish)

## Delete only when you agree

`server_legacy_backup/` is the old SafeCheck tree. After you confirm production/local runs against `backend/`, delete it:

```powershell
Remove-Item -Recurse -Force server_legacy_backup
```

Do **not** delete `backend/`. `blaces/ui/` stays for the web UI.
