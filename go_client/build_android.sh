#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build_android.sh  — Build Go client as Android AAR via gomobile
# ─────────────────────────────────────────────────────────────────────────────
# Prerequisites:
#   1. Go 1.21+      : https://go.dev/dl/
#   2. Android NDK   : installed via Android Studio SDK Manager
#      Set ANDROID_NDK_HOME or ensure it's on PATH
#   3. gomobile      : go install golang.org/x/mobile/cmd/gomobile@latest
#   4. gomobile init : run once after installing gomobile
#
# Usage:
#   cd flutter_vpn_go/go_client
#   ./build_android.sh
#
# Output:
#   ../android/vpnplugin/libs/goclient.aar
#   ../android/vpnplugin/libs/goclient-sources.jar  (optional, for IDE)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../android/vpnplugin/libs"
OUTPUT_AAR="${OUTPUT_DIR}/goclient.aar"

echo "==> Checking gomobile..."
if ! command -v gomobile &> /dev/null; then
    echo "❌ gomobile not found."
    echo "   Install: go install golang.org/x/mobile/cmd/gomobile@latest"
    echo "   Init:    gomobile init"
    exit 1
fi

echo "==> Checking ANDROID_NDK_HOME..."
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    # Try common locations
    if [ -d "$HOME/Library/Android/sdk/ndk-bundle" ]; then
        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk-bundle"
    elif [ -d "$HOME/Android/Sdk/ndk-bundle" ]; then
        export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk-bundle"
    else
        echo "⚠️  ANDROID_NDK_HOME not set. Set it to your NDK path."
        echo "   Example: export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/25.x.x"
    fi
fi

echo "==> Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "==> Building Android AAR (minSdk=26)..."
cd "${SCRIPT_DIR}"

gomobile bind \
    -target=android \
    -androidapi 26 \
    -o "${OUTPUT_AAR}" \
    ./client

echo ""
echo "✅ Build complete!"
echo "   Output: ${OUTPUT_AAR}"
echo ""
echo "==> Next steps:"
echo "   1. The AAR is already in the correct location for android/vpnplugin."
echo "   2. Ensure android/vpnplugin/build.gradle references:"
echo "      implementation fileTree(dir: 'libs', include: ['*.aar'])"
echo "   3. Run: flutter build apk --debug"
