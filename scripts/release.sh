#!/usr/bin/env bash
# Prepares a release: sets the version, builds the DMG, updates the Homebrew
# cask, commits and tags. Nothing is pushed or published unless --publish is
# given.
#
# Usage: scripts/release.sh <version> [--publish]
#   e.g. scripts/release.sh 1.0.0
#
# For a build other Macs can open without warnings, set SIGN_IDENTITY to a
# "Developer ID Application" certificate and NOTARY_PROFILE to a notarytool
# keychain profile (xcrun notarytool store-credentials). The DMG is then
# notarized and stapled before it is published.
#
# --publish pushes the commit and tag, creates the GitHub release with the
# DMG, and updates Casks/spacetab.rb in the muhammad-Osman/homebrew-tap
# repository (clone it next to this one first).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
PUBLISH="${2:-}"
CASK="packaging/homebrew/spacetab.rb"
TAP_DIR="../homebrew-tap"

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi

BUILD_NUMBER="$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist) + 1 ))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" Resources/Info.plist

scripts/make-dmg.sh
DMG="build/SpaceTab-$VERSION.dmg"

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

git add Resources/Info.plist "$CASK"
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "SpaceTab $VERSION"
echo "Committed and tagged v$VERSION. DMG: $DMG (sha256 $SHA)"

if [ "$PUBLISH" != "--publish" ]; then
    echo "Run again with --publish to push, create the GitHub release and update the tap."
    exit 0
fi

git push
git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --title "SpaceTab $VERSION" --generate-notes

if [ -d "$TAP_DIR" ]; then
    mkdir -p "$TAP_DIR/Casks"
    cp "$CASK" "$TAP_DIR/Casks/spacetab.rb"
    git -C "$TAP_DIR" add Casks/spacetab.rb
    git -C "$TAP_DIR" commit -q -m "spacetab $VERSION"
    git -C "$TAP_DIR" push
    echo "Tap updated: brew install --cask muhammad-Osman/tap/spacetab"
else
    echo "Tap repository not found at $TAP_DIR; copy $CASK to it by hand."
fi
