#!/usr/bin/env bash
# Vendor hev-socks5-tunnel for Android JNI builds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/android/app/src/main/cpp/third_party/hev-socks5-tunnel"
REPO="${HEV_TUNNEL_REPO:-https://github.com/heiher/hev-socks5-tunnel.git}"
REF="${HEV_TUNNEL_REF:-master}"

mkdir -p "$(dirname "$DEST")"
if [[ -d "$DEST/.git" ]]; then
  git -C "$DEST" fetch --depth 1 origin "$REF"
  git -C "$DEST" checkout -q FETCH_HEAD
else
  rm -rf "$DEST"
  git clone --depth 1 --branch "$REF" "$REPO" "$DEST" || \
    git clone --depth 1 "$REPO" "$DEST"
fi
echo "Vendored hev-socks5-tunnel → $DEST"
echo "Rebuild the Android app so CMake picks up HAVE_HEV_SOCKS5_TUNNEL."
