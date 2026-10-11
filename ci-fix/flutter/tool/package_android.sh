#!/usr/bin/env bash
# Copy release APK (and optional AAB) into repo dist/android/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
OUT="$REPO/dist/android"
mkdir -p "$OUT"

APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
AAB="$ROOT/build/app/outputs/bundle/release/app-release.aab"

if [[ -f "$APK" ]]; then
  cp -f "$APK" "$OUT/PulsarVPN.apk"
  echo "Wrote $OUT/PulsarVPN.apk"
else
  echo "Missing $APK — run: flutter build apk --release" >&2
  exit 1
fi

if [[ -f "$AAB" ]]; then
  cp -f "$AAB" "$OUT/PulsarVPN.aab"
  echo "Wrote $OUT/PulsarVPN.aab (Play Store)"
fi
