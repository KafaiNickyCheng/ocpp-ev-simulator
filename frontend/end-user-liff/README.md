# OCPP EV Charge — LIFF App

A LINE LIFF (LINE Front-end Framework) web app for end users to manage EV charging sessions via the OCPP backend.

## Features

- **LINE Login** — authenticated via LIFF, no separate account needed
- **Stations** — view all charge points and connector availability
- **Start Charging** — triggers `RemoteStartTransaction` on your chosen connector
- **Stop Charging** — triggers `RemoteStopTransaction` for your active session
- **Live Session** — real-time energy, power, and duration (auto-refreshes every 15s)
- **History** — view all your past transactions
- **IdTag Management** — create or deactivate your RFID tag

## Stack

- React 18 + Vite
- LINE LIFF SDK v2
- No UI library — fully custom CSS

## Setup

### 1. Install dependencies
```bash
npm install
```

### 2. Configure environment
```bash
cp .env.example .env.local
```
Edit `.env.local`:
```
VITE_LIFF_ID=your_liff_id_from_line_developers_console
VITE_BACKEND_URL=https://your-ngrok-or-production-url
```

### 3. Run locally
```bash
npm run dev
```

### 4. Expose via ngrok (required for LIFF)
LIFF requires HTTPS. Use ngrok:
```bash
ngrok http 3000
```
Set the ngrok URL as your LIFF endpoint URL in LINE Developers Console.

### 5. Build for production
```bash
npm run build
```
Deploy the `dist/` folder to any static host (Vercel, Netlify, Railway, etc.).

## LINE Developers Console Setup

1. Create a **LINE Login channel**
2. Add a LIFF app under the **LIFF** tab
   - Size: `Full`
   - Endpoint URL: your deployed URL (or ngrok for dev)
   - Scopes: `profile`, `openid`
3. Copy the **LIFF ID** into `.env.local`

## Folder structure in the monorepo

```
OCPP/
  frontend/
    liff/          ← this app
      src/
        App.jsx    — main app + all tab components
        App.css    — all styles
        api.js     — REST calls to backend
        useLiff.js — LIFF init + login hook
        main.jsx   — React entry
      index.html
      vite.config.js
      package.json
      .env.example
```

## Backend endpoints expected

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/chargepoints` | List all charge points |
| GET | `/api/chargepoints/:id` | Single charge point |
| POST | `/api/chargepoints/:id/remote-start` | RemoteStartTransaction |
| POST | `/api/chargepoints/:id/remote-stop` | RemoteStopTransaction |
| GET | `/api/transactions?lineUserId=` | User's transaction history |
| GET | `/api/transactions/active?lineUserId=` | User's active session |
| GET | `/api/tags?lineUserId=` | Get user's IdTag |
| POST | `/api/tags` | Create IdTag |
| DELETE | `/api/tags/:id` | Deactivate IdTag |
