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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"

# Sparkle, for automatic updates. Its helpers are signed first, then the
# framework, then the app, as Sparkle's documentation asks.
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE" "$FRAMEWORK"
# The hardened runtime only loads frameworks signed by the same team, so it
# is used with a real identity (as notarization requires), not for ad hoc builds.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    SIGN_OPTIONS="--options runtime"
else
    SIGN_OPTIONS=""
fi
sign() {
    # shellcheck disable=SC2086
    codesign --force $SIGN_OPTIONS --sign "${SIGN_IDENTITY:--}" "$@"
}
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"

sign "$APP"

echo "Built $APP"

NEW_REQ="$(designated_requirement "$APP")"
if [ "$OLD_REQ" != "$NEW_REQ" ]; then
    # Screen Recording is tied to the signature too; it is only needed for thumbnails.
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    if tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "Signature changed: Accessibility and Screen Recording permissions reset. Grant them again after opening the app."
    elif [ -n "$OLD_REQ" ]; then
        echo "Signature changed: if SpaceTab shows as allowed in Accessibility settings but doesn't work,"
        echo "remove it from the list with the minus button and add it again."
    fi
fi
