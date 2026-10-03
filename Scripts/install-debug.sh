#!/usr/bin/env bash
# Builds Debug and installs it over /Applications/Tokenometer.app, then re-registers the widget
# extension and restarts chronod. Running a DerivedData build beside the installed app confuses
# WidgetKit ("Bundle version did not match"), so test builds go through here.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Tokenometer.xcodeproj -scheme Tokenometer -configuration Debug -destination 'platform=macOS' build -quiet
APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Tokenometer-*/Build/Products/Debug/Tokenometer.app | head -1)
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
pkill -x Tokenometer || true
sleep 1
"$LSREG" -u "$APP" >/dev/null 2>&1 || true
rm -rf /Applications/Tokenometer.app
ditto "$APP" /Applications/Tokenometer.app
"$LSREG" -f /Applications/Tokenometer.app >/dev/null 2>&1 || true
pluginkit -a /Applications/Tokenometer.app/Contents/PlugIns/TokenometerWidget.appex
killall chronod || true
open /Applications/Tokenometer.app
echo "Debug build installed to /Applications and running"
