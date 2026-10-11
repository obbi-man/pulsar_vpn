#!/usr/bin/env bash
# Cross-compile CustomShield client as Flutter/Dart FFI libraries.
# Usage: ./build-libs.sh [OUT_DIR]
#
# CI-friendly env:
#   CS_TARGETS=android,windows,darwin,ios,linux   # only build these (default: all)
#   CS_STRICT=1                                   # exit 1 if a requested target fails/skips
#   ANDROID_NDK_HOME / ANDROID_API / CC_WINDOWS / CC_DARWIN
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/dist/libs}"
TAGS="csclient"
PKG="$ROOT"
mkdir -p "$OUT"

HOST_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
HOST_ARCH="$(uname -m)"
BUILT=0
SKIPPED=0
FAILED=0

# Default: build everything the host can. CI sets CS_TARGETS per job.
CS_TARGETS="${CS_TARGETS:-android,windows,darwin,ios,linux}"
CS_STRICT="${CS_STRICT:-0}"

want() {
  [[ ",${CS_TARGETS}," == *",$1,"* ]]
}

log() { printf '[build-libs] %s\n' "$*"; }
ok() { log "OK  $*"; BUILT=$((BUILT + 1)); }
skip() { log "SKIP $*"; SKIPPED=$((SKIPPED + 1)); }
fail_soft() {
  log "FAIL $*"
  FAILED=$((FAILED + 1))
  SKIPPED=$((SKIPPED + 1))
}

build_shared() {
  local goos="$1" goarch="$2" cc="$3" outfile="$4" extra_env="${5:-}"
  local dir
  dir="$(dirname "$outfile")"
  mkdir -p "$dir"

  if [[ -n "$cc" && ! -x "$cc" && ! -x "$(command -v "$cc" 2>/dev/null || true)" ]]; then
    fail_soft "$outfile (missing CC: $cc)"
    return 0
  fi

  log "Building $outfile (GOOS=$goos GOARCH=$goarch)"
  if (
    cd "$PKG"
    export CGO_ENABLED=1
    export GOOS="$goos"
    export GOARCH="$goarch"
    if [[ -n "$cc" ]]; then
      export CC="$cc"
    fi
    # shellcheck disable=SC2086
    eval "$extra_env"
    go build -tags "$TAGS" -buildmode=c-shared -o "$outfile" .
  ); then
    ok "$outfile"
  else
    fail_soft "$outfile"
  fi
}

build_archive() {
  local goos="$1" goarch="$2" cc="$3" outfile="$4" extra_env="${5:-}"
  local dir
  dir="$(dirname "$outfile")"
  mkdir -p "$dir"

  if [[ -n "$cc" && ! -x "$cc" && ! -x "$(command -v "$cc" 2>/dev/null || true)" ]]; then
    fail_soft "$outfile (missing CC: $cc)"
    return 0
  fi

  log "Building $outfile (GOOS=$goos GOARCH=$goarch c-archive)"
  if (
    cd "$PKG"
    export CGO_ENABLED=1
    export GOOS="$goos"
    export GOARCH="$goarch"
    if [[ -n "$cc" ]]; then
      export CC="$cc"
    fi
    # shellcheck disable=SC2086
    eval "$extra_env"
    go build -tags "$TAGS" -buildmode=c-archive -o "$outfile" .
  ); then
    ok "$outfile"
  else
    fail_soft "$outfile"
  fi
}

# --- Host Linux .so ---
if want linux; then
  if [[ "$HOST_OS" == "linux" ]]; then
    build_shared linux amd64 gcc "$OUT/linux/amd64/libcustomshield.so"
  else
    skip "linux (host is $HOST_OS)"
  fi
fi

# --- Android (.so) ---
if want android; then
  NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
  if [[ -z "$NDK" && -d "${ANDROID_HOME:-}/ndk" ]]; then
    NDK="$(ls -d "${ANDROID_HOME}/ndk"/* 2>/dev/null | sort -V | tail -1 || true)"
  fi

  if [[ -n "$NDK" && -d "$NDK" ]]; then
    PREBUILT=""
    for candidate in \
      "$NDK/toolchains/llvm/prebuilt/linux-x86_64" \
      "$NDK/toolchains/llvm/prebuilt/darwin-x86_64" \
      "$NDK/toolchains/llvm/prebuilt/darwin-arm64" \
      "$NDK/toolchains/llvm/prebuilt/windows-x86_64"; do
      if [[ -d "$candidate" ]]; then
        PREBUILT="$candidate"
        break
      fi
    done
    API="${ANDROID_API:-24}"
    # NDK r23+ uses versioned clang wrappers; also try bare names.
    resolve_clang() {
      local base="$1"
      if [[ -x "$PREBUILT/bin/${base}${API}-clang" ]]; then
        echo "$PREBUILT/bin/${base}${API}-clang"
      elif [[ -x "$PREBUILT/bin/${base}-clang" ]]; then
        echo "$PREBUILT/bin/${base}-clang"
      else
        # Newest API wrapper present
        ls "$PREBUILT/bin/${base}"*"-clang" 2>/dev/null | sort -V | tail -1 || true
      fi
    }
    if [[ -n "$PREBUILT" ]]; then
      CC_ARM64="$(resolve_clang aarch64-linux-android)"
      CC_ARM="$(resolve_clang armv7a-linux-androideabi)"
      CC_X64="$(resolve_clang x86_64-linux-android)"
      build_shared android arm64 "$CC_ARM64" "$OUT/android/arm64-v8a/libcustomshield.so"
      build_shared android arm "$CC_ARM" "$OUT/android/armeabi-v7a/libcustomshield.so" "export GOARM=7"
      build_shared android amd64 "$CC_X64" "$OUT/android/x86_64/libcustomshield.so"
    else
      fail_soft "Android (NDK prebuilt toolchain not found under $NDK)"
    fi
  else
    fail_soft "Android (set ANDROID_NDK_HOME or ANDROID_HOME/ndk)"
  fi
fi

# --- Windows (.dll) ---
if want windows; then
  MINGW="${CC_WINDOWS:-}"
  if [[ -z "$MINGW" ]]; then
    for candidate in x86_64-w64-mingw32-gcc x86_64-w64-mingw32-gcc.exe gcc; do
      if command -v "$candidate" >/dev/null 2>&1; then
        # On windows-latest, native gcc can build c-shared for windows.
        if [[ "$HOST_OS" == mingw* || "$HOST_OS" == msys* || "$HOST_OS" == cygwin* || "$HOST_OS" == windows* || -n "${WINDIR:-}" ]]; then
          MINGW="$candidate"
          break
        fi
        if [[ "$candidate" == *mingw* ]]; then
          MINGW="$candidate"
          break
        fi
      fi
    done
  fi
  # GitHub windows-latest: use default CC (no mingw prefix needed when GOOS=windows).
  if [[ -z "$MINGW" && ( "$HOST_OS" == mingw* || "$HOST_OS" == msys* || -n "${WINDIR:-}" || "$RUNNER_OS" == "Windows" ) ]]; then
    MINGW="gcc"
  fi
  if [[ -n "$MINGW" ]] && command -v "$MINGW" >/dev/null 2>&1; then
    build_shared windows amd64 "$MINGW" "$OUT/windows/amd64/customshield.dll"
  else
    fail_soft "Windows DLL (install mingw-w64; CC_WINDOWS=x86_64-w64-mingw32-gcc)"
  fi
fi

# --- macOS (.dylib) ---
if want darwin; then
  if [[ "$HOST_OS" == "darwin" ]]; then
    build_shared darwin arm64 clang "$OUT/darwin/arm64/libcustomshield.dylib"
    build_shared darwin amd64 clang "$OUT/darwin/amd64/libcustomshield.dylib"
  elif command -v o64-clang >/dev/null 2>&1 || command -v x86_64-apple-darwin-clang >/dev/null 2>&1; then
    CC_MAC="${CC_DARWIN:-$(command -v o64-clang || command -v x86_64-apple-darwin-clang)}"
    build_shared darwin amd64 "$CC_MAC" "$OUT/darwin/amd64/libcustomshield.dylib"
  else
    fail_soft "macOS dylib (build on macOS with Xcode CLT, or provide osxcross CC_DARWIN)"
  fi
fi

# --- iOS (static .a / xcframework) ---
if want ios; then
  IOS_OUT="$OUT/ios"
  mkdir -p "$IOS_OUT"
  if [[ "$HOST_OS" == "darwin" ]] && command -v xcrun >/dev/null 2>&1; then
    IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
    SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"
    if [[ -n "$IPHONEOS_SDK" ]]; then
      build_archive ios arm64 \
        "$(xcrun --sdk iphoneos -f clang)" \
        "$IOS_OUT/device/libcustomshield.a" \
        "export CGO_CFLAGS=\"-isysroot $IPHONEOS_SDK -arch arm64 -miphoneos-version-min=13.0\"; export CGO_LDFLAGS=\"-isysroot $IPHONEOS_SDK -arch arm64\""
      # c-archive emits header next to .a — keep a stable headers dir for xcframework
      if [[ -f "$IOS_OUT/device/libcustomshield.h" ]]; then
        mkdir -p "$IOS_OUT/device/Headers"
        cp "$IOS_OUT/device/libcustomshield.h" "$IOS_OUT/device/Headers/"
      fi
    else
      fail_soft "iOS device archive (iphoneos SDK missing)"
    fi
    if [[ -n "$SIM_SDK" ]]; then
      build_archive ios arm64 \
        "$(xcrun --sdk iphonesimulator -f clang)" \
        "$IOS_OUT/simulator/arm64/libcustomshield.a" \
        "export CGO_CFLAGS=\"-isysroot $SIM_SDK -arch arm64 -mios-simulator-version-min=13.0\"; export CGO_LDFLAGS=\"-isysroot $SIM_SDK -arch arm64\""
      if [[ -f "$IOS_OUT/simulator/arm64/libcustomshield.h" ]]; then
        mkdir -p "$IOS_OUT/simulator/arm64/Headers"
        cp "$IOS_OUT/simulator/arm64/libcustomshield.h" "$IOS_OUT/simulator/arm64/Headers/"
      fi
    fi
    if command -v xcodebuild >/dev/null 2>&1 && [[ -f "$IOS_OUT/device/libcustomshield.a" ]]; then
      FW="$IOS_OUT/CustomShield.xcframework"
      rm -rf "$FW"
      DEVICE_HEADERS="$IOS_OUT/device/Headers"
      [[ -d "$DEVICE_HEADERS" ]] || DEVICE_HEADERS="$IOS_OUT/device"
      XCF_ARGS=(-create-xcframework -library "$IOS_OUT/device/libcustomshield.a" -headers "$DEVICE_HEADERS")
      if [[ -f "$IOS_OUT/simulator/arm64/libcustomshield.a" ]]; then
        SIM_HEADERS="$IOS_OUT/simulator/arm64/Headers"
        [[ -d "$SIM_HEADERS" ]] || SIM_HEADERS="$IOS_OUT/simulator/arm64"
        XCF_ARGS+=(-library "$IOS_OUT/simulator/arm64/libcustomshield.a" -headers "$SIM_HEADERS")
      fi
      if xcodebuild "${XCF_ARGS[@]}" -output "$FW"; then
        ok "$FW"
      else
        fail_soft "$FW (xcodebuild -create-xcframework)"
      fi
    else
      fail_soft "CustomShield.xcframework (need device .a + xcodebuild)"
    fi
  else
    fail_soft "iOS .xcframework / .a (requires macOS + Xcode)"
  fi
fi

# --- Header convenience copy ---
HEADER_SRC="$(find "$OUT" \( -name 'libcustomshield.h' -o -name 'customshield.h' \) 2>/dev/null | head -1 || true)"
if [[ -n "${HEADER_SRC:-}" ]]; then
  mkdir -p "$OUT/include"
  cp "$HEADER_SRC" "$OUT/include/libcustomshield.h"
  cat > "$OUT/include/customshield_ffi.h" <<'EOF'
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

/* Returns 0 on success. See client.go constants. */
int StartClient(char* serverIP, int port, char* secretKey, char* connectionID, int localProxyPort);
int StopClient(void);

#ifdef __cplusplus
}
#endif
EOF
  ok "$OUT/include/libcustomshield.h"
fi

# Flutter drop-in hints (written into artifact)
mkdir -p "$OUT"
cat > "$OUT/FLUTTER_DROP_IN.md" <<EOF
# Drop CI artifacts into Flutter

Layout under \`dist/libs/\` (this artifact root):

\`\`\`
android/arm64-v8a/libcustomshield.so
android/armeabi-v7a/libcustomshield.so
android/x86_64/libcustomshield.so
windows/amd64/customshield.dll
darwin/arm64/libcustomshield.dylib
darwin/amd64/libcustomshield.dylib
ios/device/libcustomshield.a
ios/simulator/arm64/libcustomshield.a
ios/CustomShield.xcframework/
include/libcustomshield.h
\`\`\`

## Android
\`\`\`bash
mkdir -p flutter/android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}
cp android/arm64-v8a/libcustomshield.so flutter/android/app/src/main/jniLibs/arm64-v8a/
cp android/armeabi-v7a/libcustomshield.so flutter/android/app/src/main/jniLibs/armeabi-v7a/
cp android/x86_64/libcustomshield.so flutter/android/app/src/main/jniLibs/x86_64/
\`\`\`

## iOS / macOS
- Link \`ios/CustomShield.xcframework\` (or \`.a\`) into the PacketTunnel extension
  (see \`flutter/ios/XCODE_PACKET_TUNNEL.md\`).
- Copy macOS dylibs next to the Runner or embed in Frameworks:
  \`darwin/arm64/libcustomshield.dylib\`, \`darwin/amd64/libcustomshield.dylib\`.

## Windows
\`\`\`bash
cp windows/amd64/customshield.dll flutter/windows/runner/  # or build output dir
\`\`\`
EOF

log "Done. built=$BUILT skipped=$SKIPPED failed=$FAILED out=$OUT targets=$CS_TARGETS"
log "FFI: StartClient(serverIP, port, secretKey, connectionID, localProxyPort), StopClient()"

if [[ "$BUILT" -eq 0 ]]; then
  log "No libraries built. Install prerequisites and re-run."
  exit 1
fi

if [[ "$CS_STRICT" == "1" && "$FAILED" -gt 0 ]]; then
  log "CS_STRICT=1 and $FAILED build(s) failed — exiting 1"
  exit 1
fi

exit 0
