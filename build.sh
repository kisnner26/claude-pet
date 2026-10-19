#!/bin/sh
# Compila y empaqueta ClaudePet.app en ./build (firma ad-hoc, sin cuenta de desarrollador).
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClaudePet" "$APP/Contents/MacOS/ClaudePet"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/ClaudePet.icns "$APP/Contents/Resources/ClaudePet.icns"
codesign --force --sign - "$APP"
echo "listo: $APP"
