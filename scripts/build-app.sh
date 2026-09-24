#!/usr/bin/env bash
# Builds SpaceTab and wraps it in build/SpaceTab.app.
#
# Usage: scripts/build-app.sh [debug|release]
# Set SIGN_IDENTITY to a code signing identity to keep the Accessibility
# permission across rebuilds. Without it the app is signed ad hoc, and macOS
# asks for the permission again after every build.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/SpaceTab.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpaceTab" "$APP/Contents/MacOS/SpaceTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
