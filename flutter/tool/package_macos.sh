#!/usr/bin/env bash
# Build a .dmg from `flutter build macos --release` output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
APP_NAME="Pulsar VPN"
# Flutter default product name often matches Runner; detect .app
BUILD_DIR="$ROOT/build/macos/Build/Products/Release"
OUT_DIR="$REPO/dist/macos"
mkdir -p "$OUT_DIR"

APP_PATH="$(find "$BUILD_DIR" -maxdepth 1 -name '*.app' | head -1 || true)"
if [[ -z "$APP_PATH" ]]; then
  echo "No .app in $BUILD_DIR — run: flutter build macos --release" >&2
  exit 1
fi

DMG="$OUT_DIR/PulsarVPN.dmg"
rm -f "$DMG"
VOL="PulsarVPN"
STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Wrote $DMG"
