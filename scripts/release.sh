#!/usr/bin/env bash
# Prepares a release: sets the version, builds the DMG, updates the Homebrew
# cask, commits and tags. Nothing is pushed or published unless --publish is
# given. With --dry-run, nothing is changed in the repository either.
#
# Usage: scripts/release.sh <version> [--publish|--dry-run]
#   e.g. scripts/release.sh 1.0.0
#
# For a build other Macs can open without warnings, set SIGN_IDENTITY to a
# "Developer ID Application" certificate and NOTARY_PROFILE to a notarytool
# keychain profile (xcrun notarytool store-credentials). The DMG is then
# notarized and stapled, and published with its update feed.
#
# Without SIGN_IDENTITY the release is unsigned: it is published as a
# pre-release, users open it with right-click > Open the first time, and the
# app doesn't update itself (an update would lose its permissions).
#
# --publish pushes the commit and tag, creates the GitHub release with the
# DMG, and updates Casks/spacetab.rb in the muhammad-Osman/homebrew-tap
# repository (clone it next to this one first).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--publish|--dry-run]}"
MODE="${2:-}"
CASK="packaging/homebrew/spacetab.rb"
TAP_DIR="../homebrew-tap"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi

SIGNED=""
if [ -n "${SIGN_IDENTITY:-}" ]; then
    SIGNED=1
else
    echo "No SIGN_IDENTITY: building an unsigned release without automatic updates."
fi

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "Tag v$VERSION already exists. Pick a new version." >&2
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

# The update feed, for signed releases only. Sparkle signs the DMG with the
# private key in the keychain (created with generate_keys); the app checks
# the signature with the public key in Info.plist.
APPCAST=""
if [ -n "$SIGNED" ]; then
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
SIGNATURE="$("$TOOLS/sign_update" "$DMG")"
APPCAST="build/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SpaceTab</title>
    <item>
      <title>SpaceTab $VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>https://github.com/muhammad-Osman/spacetab/releases/tag/v$VERSION</link>
      <enclosure url="https://github.com/muhammad-Osman/spacetab/releases/download/v$VERSION/SpaceTab-$VERSION.dmg" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML
fi

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [ "$MODE" = "--dry-run" ]; then
    git checkout -- Resources/Info.plist
    echo "Dry run: built $DMG (sha256 $SHA)${APPCAST:+, update feed: $APPCAST}. Nothing committed."
    exit 0
fi

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

git add Resources/Info.plist "$CASK"
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "SpaceTab $VERSION"
echo "Committed and tagged v$VERSION. DMG: $DMG (sha256 $SHA)${APPCAST:+, update feed: $APPCAST}"

if [ "$MODE" != "--publish" ]; then
    echo "Run again with --publish to push, create the GitHub release and update the tap."
    exit 0
fi

git push
git push origin "v$VERSION"
if [ -n "$SIGNED" ]; then
    gh release create "v$VERSION" "$DMG" "$APPCAST" --title "SpaceTab $VERSION" --generate-notes
else
    gh release create "v$VERSION" "$DMG" --title "SpaceTab $VERSION" --generate-notes --prerelease \
        --notes-start-tag "" 2>/dev/null || gh release create "v$VERSION" "$DMG" --title "SpaceTab $VERSION" --generate-notes --prerelease
fi

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
