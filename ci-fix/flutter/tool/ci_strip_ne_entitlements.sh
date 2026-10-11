#!/usr/bin/env bash
# Replace Network Extension entitlements with CI-safe stubs so unsigned
# macOS/iOS builds succeed on GitHub Actions without an Apple team.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT/macos/Runner/Release-CI.entitlements" ]]; then
  cp "$ROOT/macos/Runner/Release-CI.entitlements" \
     "$ROOT/macos/Runner/Release.entitlements"
  cp "$ROOT/macos/Runner/Release-CI.entitlements" \
     "$ROOT/macos/Runner/DebugProfile.entitlements"
  echo "macOS: applied Release-CI.entitlements (no NE)"
fi

if [[ -f "$ROOT/ios/Runner/Runner-CI.entitlements" ]]; then
  cp "$ROOT/ios/Runner/Runner-CI.entitlements" \
     "$ROOT/ios/Runner/Runner.entitlements"
  echo "iOS: applied Runner-CI.entitlements (no NE)"
fi

# PacketTunnel extension (if present): empty entitlements for CI compile
if [[ -f "$ROOT/ios/PacketTunnel/PacketTunnel.entitlements" ]]; then
  cat > "$ROOT/ios/PacketTunnel/PacketTunnel.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
  echo "iOS: stripped PacketTunnel entitlements"
fi

if [[ -f "$ROOT/macos/PacketTunnel/PacketTunnel.entitlements" ]]; then
  cat > "$ROOT/macos/PacketTunnel/PacketTunnel.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
  echo "macOS: stripped PacketTunnel entitlements"
fi
