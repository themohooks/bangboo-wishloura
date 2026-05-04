#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build_ios.sh  — Build Go client as iOS XCFramework via gomobile
# ─────────────────────────────────────────────────────────────────────────────
# Prerequisites:
#   1. Go 1.21+    : https://go.dev/dl/
#   2. Xcode 15+   : installed and command line tools configured
#      xcode-select --install
#   3. gomobile    : go install golang.org/x/mobile/cmd/gomobile@latest
#   4. gomobile init (run once):
#      gomobile init
#
# Usage:
#   cd flutter_vpn_go/go_client
#   ./build_ios.sh
#
# Output:
#   ../ios/Frameworks/GoClient.xcframework
#
# The XCFramework is a fat framework containing slices for:
#   - ios-arm64          (real device)
#   - ios-arm64-simulator (M1/M2 simulator)
#   - ios-x86_64-simulator (Intel simulator)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../ios/Frameworks"
OUTPUT_XCF="${OUTPUT_DIR}/GoClient.xcframework"

echo "==> Checking gomobile..."
if ! command -v gomobile &> /dev/null; then
    echo "❌ gomobile not found."
    echo "   Install: go install golang.org/x/mobile/cmd/gomobile@latest"
    echo "   Init:    gomobile init"
    exit 1
fi

echo "==> Checking Xcode..."
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode command line tools not configured."
    echo "   Run: xcode-select --install"
    exit 1
fi

echo "==> Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Remove old framework
if [ -d "${OUTPUT_XCF}" ]; then
    echo "==> Removing old XCFramework..."
    rm -rf "${OUTPUT_XCF}"
fi

echo "==> Building iOS XCFramework..."
cd "${SCRIPT_DIR}"

gomobile bind \
    -target=ios \
    -o "${OUTPUT_XCF}" \
    ./client

echo ""
echo "✅ Build complete!"
echo "   Output: ${OUTPUT_XCF}"
echo ""
echo "==> Next steps:"
echo "   1. Open ios/Runner.xcworkspace in Xcode."
echo "   2. In Runner target -> General -> Frameworks, Libraries, Embedded Content:"
echo "      Add GoClient.xcframework from ios/Frameworks/."
echo "      Set to 'Embed & Sign'."
echo "   3. In PacketTunnel target -> General -> Frameworks and Libraries:"
echo "      Add GoClient.xcframework."
echo "      Set to 'Do Not Embed' (already embedded in Runner)."
echo "   4. Build the project: Product -> Build (Cmd+B)."
