#!/usr/bin/env bash
# Builds SpaceTab and packages it as build/SpaceTab-<version>.dmg, with an
# Applications shortcut for drag-and-drop installation.
#
# Usage: scripts/make-dmg.sh
# Set SIGN_IDENTITY to a Developer ID Application certificate for a build
# that other Macs can open without warnings. Notarize the result with:
#   xcrun notarytool submit build/SpaceTab-<version>.dmg --keychain-profile <profile> --wait
#   xcrun stapler staple build/SpaceTab-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh release

APP="build/SpaceTab.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/SpaceTab-$VERSION.dmg"
STAGING="build/dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "SpaceTab" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "Built $DMG"
