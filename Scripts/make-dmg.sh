#!/usr/bin/env bash
# Builds a drag-to-Applications installer: Scripts/make-dmg.sh <Tokenometer.app> <out.dmg>
# The app must already be Developer ID signed and stapled (release.sh does that).
# Layout is done by dmgbuild (pipx install dmgbuild), which writes the Finder .DS_Store
# programmatically, so it works headless. Window and icon settings live in dmg-settings.py;
# the background comes from make-dmg-background.swift.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$1"
DMG="$2"

[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }
command -v dmgbuild >/dev/null || { echo "error: dmgbuild not found; pipx install dmgbuild" >&2; exit 1; }

rm -f "$DMG"
dmgbuild -s "$DIR/dmg-settings.py" -D app="$APP" -D background="$DIR/dmg-background.tiff" "Tokenometer" "$DMG"

# Sign the disk image itself, so the download is signed end to end.
codesign --force --timestamp --sign "Developer ID Application" "$DMG"
echo "built: $DMG"
