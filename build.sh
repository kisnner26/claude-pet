#!/bin/sh
# Compila y empaqueta ClaudePet.app en ./build (firma Apple Development si existe; si no, ad-hoc).
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClaudePet" "$APP/Contents/MacOS/ClaudePet"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/ClaudePet.icns "$APP/Contents/Resources/ClaudePet.icns"
# Con un certificado estable macOS conserva el permiso de Accesibilidad entre compilaciones; ad-hoc lo pierde cada vez.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "listo: $APP"
