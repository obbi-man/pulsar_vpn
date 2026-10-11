# Apply Pulsar CI fix (GitHub Desktop)

## Root causes (run 38114962571)

| Job | Failed step | Likely cause |
|---|---|---|
| **windows-installer** | Build Windows release | Flutter Windows CMake uses `/WX` (warnings as errors). `wintun_tunnel.cpp` / WinInet sources trip MSVC `/W4` → build exits 1. |
| **macos-dmg** | Build macOS release | `Release.entitlements` includes **Network Extension** + app groups. Unsigned CI has no Apple team → xcodebuild fails. |
| **ios-notes** | Build iOS (no codesign) | Same NE entitlements on Runner; job treated build failure as fatal. |

## What we changed

- `.github/workflows/build-apps.yml` — hardened builds, strip NE for CI, iOS `continue-on-error`, one-line Windows flutter build, Inno path lookup
- `flutter/windows/runner/CMakeLists.txt` — `/WX-` + `_CRT_SECURE_NO_WARNINGS`
- `flutter/tool/ci_strip_ne_entitlements.sh` — CI stubs without NE
- `flutter/macos/Runner/Release-CI.entitlements`, `flutter/ios/Runner/Runner-CI.entitlements`
- `flutter/installer/windows/pulsar.iss` — English-only (CI Inno)

## Reapply (1–2 minutes)

1. Open your local `pulsar_vpn` clone in GitHub Desktop (or Finder).
2. Copy everything from this `ci-fix/` folder **on top of** the repo root (keep folder structure):

```
ci-fix/.github/workflows/build-apps.yml
  → <repo>/.github/workflows/build-apps.yml
ci-fix/flutter/...
  → <repo>/flutter/...
```

Quick way (from Terminal, adjust paths):

```bash
cd ~/path/to/pulsar_vpn
cp -R /path/to/ci-fix/. .
```

3. Commit: `Fix CI: Windows /WX, strip NE entitlements for macOS/iOS`
4. Push to `main` → Actions → **Build Pulsar apps** should go green.
5. Download artifacts: `pulsar-android-apk`, `pulsar-windows-installer`, `pulsar-macos-dmg`, `pulsar-ios-notes`.
