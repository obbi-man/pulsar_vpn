# Pulsar VPN

**BYO-VPS constructor** — you bring an Ubuntu VPS; Pulsar installs an obfuscated UDP protocol on *your* server. We do not sell VPN access.

The product is the **native Flutter app** (Android / iOS / Windows / macOS):

- **Admin** — login, paste VPS IP/password, setup progress, users + `pulsar://` keys, Free ≤ 20 / Pro
- **Client** — paste `pulsar://` (or legacy `cs://`) key and connect

Next.js is an **API-only backend** (SSH provision, users, billing mock). Not the product UI.

## Quick start

### API backend

```bash
npm install
cp .env.example .env.local   # CS_LOCAL_DEMO=1 for local panel/API without Supabase
npm run dev                  # http://127.0.0.1:43127
```

Local demo login: `admin@pulsar.local` / `demo-admin`

### Flutter (desktop)

```bash
cd flutter
flutter pub get
# Point at API (default 127.0.0.1:43127):
flutter run -d linux \
  --dart-define=PULSAR_API_BASE=http://127.0.0.1:43127
# Windows / macOS:
# flutter run -d windows --dart-define=PULSAR_API_BASE=http://127.0.0.1:43127
# flutter run -d macos   --dart-define=PULSAR_API_BASE=http://127.0.0.1:43127
```

## Installers (phone + PC)

GitHub Actions workflow **Build Pulsar apps** produces downloadable artifacts:

| OS | Artifact | Install |
|---|---|---|
| Android | `PulsarVPN.apk` (also `.aab` for Play) | Sideload APK; Play needs your keystore |
| Windows | `PulsarVPN-Setup.exe` (+ portable zip) | Run Setup; optional `wintun.dll` beside exe |
| macOS | `PulsarVPN.dmg` | Drag to Applications (unsigned → right-click Open) |
| iOS | signing notes | Apple Developer + Xcode Archive / `flutter build ipa` |

Details: [`dist/README.md`](dist/README.md). Local packaging: `flutter/tool/package_*.sh`, Inno `flutter/installer/windows/pulsar.iss`.

## Access keys

| Scheme | Status |
|---|---|
| `pulsar://secret@host:port/?id=aabbccdd` | Preferred (UI / new keys) |
| `cs://secret@host:port/?id=aabbccdd` | Compat — still accepted |

## Leftover API (Next.js)

| Route | Role |
|---|---|
| `POST /api/auth/demo-login` | Local demo cookie session |
| `POST /api/auth/logout` | Clear session |
| `POST /api/server/setup` | SSH deploy Pulsar on VPS (or mock in demo) |
| `GET/POST /api/users` | List / create clients + keys |
| `GET /api/billing/plan` | Free / Pro |
| `POST /api/billing/checkout` | Mock Pro checkout |
| `POST /api/billing/confirm` | Activate Pro (mock) |

## Protocol

`custom-protocol/` — Go UDP server/client (ChaCha20-Poly1305). Env `CS_SECRET_KEY` kept for deploy compat. Container still named historically under `/opt/customshield` on the VPS until a future rename pass.

## Env

See `.env.example`. `CS_LOCAL_DEMO=1` + `CS_BILLING_MODE=mock` for local testing without Supabase/Stripe.
