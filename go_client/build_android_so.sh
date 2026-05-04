#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build_android_so.sh  — Build Go client as ELF executable for Android
#
# Output: libclient.so (actually an ELF executable with .so extension)
# Placed into jniLibs/ so Android unpacks it via extractNativeLibs="true".
# Kotlin launches it via ProcessBuilder from nativeLibraryDir.
#
# This mirrors exactly how proxy-turn-vk-android builds its Go client.
# ─────────────────────────────────────────────────────────────────────────────
# Prerequisites:
#   1. Go 1.21+      : https://go.dev/dl/
#   2. Android NDK   : installed via Android Studio
#      Set ANDROID_NDK_HOME or NDK_ROOT
#   3. Build entry point: go_client/cmd/android/main.go  (see below)
#
# Usage:
#   cd flutter_vpn_go/go_client
#   ./build_android_so.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── NDK detection ─────────────────────────────────────────────────────────────
if [ -z "${ANDROID_NDK_HOME:-}" ] && [ -z "${NDK_ROOT:-}" ]; then
    # Common locations
    for candidate in \
        "$HOME/Library/Android/sdk/ndk-bundle" \
        "$HOME/Library/Android/sdk/ndk/25.2.9519653" \
        "$HOME/Android/Sdk/ndk-bundle" \
        "/opt/android-ndk"; do
        if [ -d "$candidate" ]; then
            export ANDROID_NDK_HOME="$candidate"
            break
        fi
    done
fi
NDK="${ANDROID_NDK_HOME:-${NDK_ROOT:-}}"
if [ -z "$NDK" ]; then
    echo "❌ Android NDK not found. Set ANDROID_NDK_HOME."
    exit 1
fi
echo "==> NDK: $NDK"

# ── Output directories ────────────────────────────────────────────────────────
JNILIBS_DIR="${SCRIPT_DIR}/../android/vpnplugin/src/main/jniLibs"
mkdir -p \
    "${JNILIBS_DIR}/arm64-v8a" \
    "${JNILIBS_DIR}/armeabi-v7a" \
    "${JNILIBS_DIR}/x86_64"

# ── Entry point: cmd/android/main.go ─────────────────────────────────────────
# We need a package main wrapper that calls client.Main().
CMD_DIR="${SCRIPT_DIR}/cmd/android"
mkdir -p "$CMD_DIR"
cat > "${CMD_DIR}/main.go" << 'EOF'
package main

import "github.com/example/flutter_vpn_go/go_client/client"

func main() { client.Main() }
EOF

cd "${SCRIPT_DIR}"

# ── Build function ────────────────────────────────────────────────────────────
build_arch() {
    local ARCH="$1"
    local ABI="$2"
    local CC_PREFIX="$3"
    local API="${4:-26}"

    local CLANG="${NDK}/toolchains/llvm/prebuilt/$(uname | tr '[:upper:]' '[:lower:]')-x86_64/bin/${CC_PREFIX}${API}-clang"

    # Try both linux-x86_64 and darwin-x86_64 host toolchain paths
    if [ ! -f "$CLANG" ]; then
        CLANG="${NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${CC_PREFIX}${API}-clang"
    fi
    if [ ! -f "$CLANG" ]; then
        CLANG="${NDK}/toolchains/llvm/prebuilt/darwin-x86_64/bin/${CC_PREFIX}${API}-clang"
    fi
    if [ ! -f "$CLANG" ]; then
        echo "⚠️  Clang not found for $ABI at $CLANG — skipping"
        return 0
    fi

    local OUT="${JNILIBS_DIR}/${ABI}/libclient.so"
    echo "==> Building $ABI → $OUT"

    CGO_ENABLED=1 \
    GOOS=android \
    GOARCH="${ARCH}" \
    CC="${CLANG}" \
        go build \
        -trimpath \
        -ldflags="-s -w" \
        -o "${OUT}" \
        ./cmd/android

    echo "   ✓ $(du -sh "$OUT" | cut -f1)  $OUT"
}

echo "==> Building arm64-v8a..."
build_arch arm64 arm64-v8a aarch64-linux-android

echo "==> Building armeabi-v7a..."
build_arch arm armeabi-v7a armv7a-linux-androideabi

echo "==> Building x86_64..."
build_arch amd64 x86_64 x86_64-linux-android

echo ""
echo "✅ Build complete! Files in: ${JNILIBS_DIR}"
echo ""
echo "==> Next steps:"
echo "   1. Ensure android/vpnplugin/src/main/AndroidManifest.xml has"
echo "      android:extractNativeLibs=\"true\" in <application>"
echo "   2. Kotlin reads binary via:"
echo "      context.applicationInfo.nativeLibraryDir + \"/libclient.so\""
echo "   3. Run: flutter build apk --debug"
