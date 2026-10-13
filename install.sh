#!/bin/sh
# Builds a release copy and installs it into /Applications, replacing the running app.
set -e
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project BTHomeControl.xcodeproj -scheme BTHomeControl -configuration Release -derivedDataPath build build | grep -E "error|BUILD"
pkill -f "MacOS/BT Home Control" || true
rm -rf "/Applications/BT Home Control.app"
ditto "build/Build/Products/Release/BT Home Control.app" "/Applications/BT Home Control.app"
# A second copy would make macOS register the widget twice.
rm -rf build/Build/Products
open "/Applications/BT Home Control.app"
