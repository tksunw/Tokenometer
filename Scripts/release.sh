#!/usr/bin/env bash
# Build, sign, notarize, and package a release as a zip and a drag-to-Applications DMG. Run from the repo root.
# Prereqs (one time): xcrun notarytool store-credentials tksunw-notary --apple-id <id> --team-id F5ED28X889
#                     pipx install dmgbuild
# Usage: Scripts/release.sh [version]   (version defaults to MARKETING_VERSION in project.yml)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-$(grep MARKETING_VERSION project.yml | head -1 | awk '{print $2}')}"
DIST="dist/$VERSION"
ARCHIVE="$DIST/Tokenometer.xcarchive"
rm -rf "$DIST" && mkdir -p "$DIST"

xcodebuild -project Tokenometer.xcodeproj -scheme Tokenometer -configuration Release \
  -destination 'platform=macOS' -archivePath "$ARCHIVE" archive MARKETING_VERSION="$VERSION" | grep -E 'error|ARCHIVE' || true

cat > "$DIST/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>F5ED28X889</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$DIST/export.plist" -exportPath "$DIST/export" | grep -E 'error|EXPORT' || true

APP="$DIST/export/Tokenometer.app"
ZIP="$DIST/Tokenometer-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile tksunw-notary --wait
xcrun stapler staple "$APP"
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"

# Drag-to-Applications installer from the stapled app, notarized and stapled itself.
DMG="$DIST/Tokenometer-$VERSION.dmg"
Scripts/make-dmg.sh "$APP" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile tksunw-notary --wait
xcrun stapler staple "$DMG"

# Sparkle appcast: signs the DMG with the EdDSA key in the login keychain and writes dist/<ver>/appcast.xml
# with enclosure URLs pointing at this version's GitHub release assets.
SPARKLE_BIN=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Tokenometer-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
if [ -n "$SPARKLE_BIN" ]; then
  rm -rf "$DIST/appcast" && mkdir -p "$DIST/appcast" && cp "$DMG" "$DIST/appcast/"
  "$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/tksunw/Tokenometer/releases/download/v$VERSION/" \
    --maximum-versions 1 -o "$DIST/appcast.xml" "$DIST/appcast" >/dev/null
  echo "Appcast: $DIST/appcast.xml"
else
  echo "Sparkle tools not found in DerivedData; build once in Xcode to fetch the package. No appcast generated." >&2
fi
echo "Release zip: $ZIP"
echo "Release dmg: $DMG"
echo "Next: gh release create v$VERSION $DMG $ZIP $DIST/appcast.xml --title v$VERSION --notes '...'"
