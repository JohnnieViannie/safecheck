# SafeBangle UI

React + TypeScript + Tailwind frontend for the SafeBangle platform.

```bash
cd ui
npm install
cp .env.example .env   # local API
npm run dev
```

Open http://localhost:3000

| Mode | API |
|------|-----|
| Local (`.env`) | `http://127.0.0.1:8001/api` |
| Production build (`.env.production`) | `https://server.safebangle.com/api` |

```bash
npm run build   # ships with production API URL
```
