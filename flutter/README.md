# Pulsar VPN (Flutter)

Native app for **admins** (BYO-VPS constructor) and **clients** (connect with key).
Not a webview of the old dashboard.

## Modes

1. **Я админ** — login → VPS setup → users/`pulsar://` keys → Pro gate  
2. **У меня есть ключ** — round connect button + OS VPN / Wintun / system proxy  

## Run (desktop)

```bash
# Terminal 1 — API
cd .. && npm run dev   # http://127.0.0.1:43127  (CS_LOCAL_DEMO=1)

# Terminal 2 — app
cd flutter
flutter pub get
flutter run -d linux \
  --dart-define=PULSAR_API_BASE=http://127.0.0.1:43127
```

Demo admin: `admin@pulsar.local` / `demo-admin`

Windows / macOS: `-d windows` / `-d macos` (same dart-define).

## Keys

UI prefers `pulsar://…`. Legacy `cs://…` still parses.

## Capture path (client)

| Platform | Path |
|---|---|
| Android | VpnService + tun2socks → Go SOCKS |
| iOS / macOS | Network Extension |
| Windows | Wintun (preferred) or WinInet proxy → Go SOCKS |

Place `customshield.dll` (+ optional `wintun.dll`) next to the Windows runner.
Technical channel id remains `customshield/vpn` for native compat.
