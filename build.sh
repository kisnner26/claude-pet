#!/bin/sh
# Compila y empaqueta ClaudePet.app en ./build (firma ad-hoc, sin cuenta de desarrollador).
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/ClaudePet" "$APP/Contents/MacOS/ClaudePet"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "listo: $APP"
