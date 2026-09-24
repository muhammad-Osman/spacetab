#!/usr/bin/env bash
# Builds SpaceTab and wraps it in build/SpaceTab.app. Quits a running SpaceTab
# first, so the next launch runs the new build.
#
# Usage: scripts/build-app.sh [debug|release]
#
# Set SIGN_IDENTITY to a code signing identity to keep the Accessibility
# permission across rebuilds. Without it the app is signed ad hoc. macOS stops
# trusting a build whose signature changed, while System Settings still shows
# it switched on, so the script then resets the permission and you grant it
# again after launching.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/SpaceTab.app"
BUNDLE_ID="io.github.muhammad-osman.spacetab"

designated_requirement() {
    codesign -d -r- "$1" 2>/dev/null | sed -n 's/^#* *designated => //p' || true
}

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if pgrep -x SpaceTab >/dev/null; then
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in $(seq 50); do
        pgrep -x SpaceTab >/dev/null || break
        sleep 0.1
    done
    pkill -x SpaceTab 2>/dev/null || true
fi

OLD_REQ=""
if [ -d "$APP" ]; then
    OLD_REQ="$(designated_requirement "$APP")"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpaceTab" "$APP/Contents/MacOS/SpaceTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"

NEW_REQ="$(designated_requirement "$APP")"
if [ "$OLD_REQ" != "$NEW_REQ" ]; then
    if tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "Signature changed: Accessibility permission reset. Grant it again after opening the app."
    elif [ -n "$OLD_REQ" ]; then
        echo "Signature changed: if SpaceTab shows as allowed in Accessibility settings but doesn't work,"
        echo "remove it from the list with the minus button and add it again."
    fi
fi
