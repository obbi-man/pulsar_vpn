# Pulsar VPN — installers & artifacts

Built by GitHub Actions (`.github/workflows/build-apps.yml`) or locally with the scripts under `flutter/tool/`.

| Platform | Artifact | How to install |
|---|---|---|
| **Android** | `android/PulsarVPN.apk` | Download → open on phone → allow install from unknown sources. For Play Store use `PulsarVPN.aab` (needs your keystore). |
| **Windows** | `windows/PulsarVPN-Setup.exe` | Run the installer (Inno Setup). Or unzip `PulsarVPN-windows.zip` and run `PulsarVPN.exe`. Optional: place `wintun.dll` next to the exe for full tunnel. |
| **macOS** | `macos/PulsarVPN.dmg` | Open DMG → drag app to Applications. First launch: System Settings → Privacy → allow if Gatekeeper blocks (unsigned). |
| **iOS** | `ios/` notes + unsigned archive | Needs Apple Developer Program + signing; CI uploads build notes / xcarchive when secrets missing. |

## GitHub Actions

Workflow **Build Pulsar apps** uploads:

- `pulsar-android-apk`
- `pulsar-windows-installer` (Setup.exe + zip)
- `pulsar-macos-dmg`
- `pulsar-ios-notes` (signing checklist)

Download from the Actions run → Artifacts.

## Signing you must provide

| Platform | What you need |
|---|---|
| Android Play / release trust | Create a keystore; set `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` in repo secrets for signed AAB/APK. Unsigned debug/release APK from CI is fine for sideload testing. |
| iOS / App Store / TestFlight | Apple Developer account, distribution cert + provisioning profile. CI cannot produce a installable IPA without these secrets. |
| macOS notarization | Apple ID / Developer ID cert for Gatekeeper-clean DMG. Unsigned DMG works if users right-click → Open. |
| Windows SmartScreen | Optional code-signing certificate (EV/OV). Unsigned Setup.exe may show SmartScreen warning. |
