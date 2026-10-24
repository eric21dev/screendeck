#!/bin/bash
# Compila ScreenDeck.app en ./build (sin Xcode: solo las herramientas de línea de comandos).
# Necesita libusb para compilar (brew install libusb); queda incluido dentro de la app, así que
# quien la use no necesita instalar nada.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/ScreenDeck.app
VERSION=${VERSION:-1.0}
LIBUSB_DIR=${LIBUSB_DIR:-/opt/homebrew/opt/libusb}
[ -f "$LIBUSB_DIR/lib/libusb-1.0.0.dylib" ] || { echo "Falta libusb: brew install libusb"; exit 1; }
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" build/tmp

# 1) Compilar
swiftc -O -target "$(uname -m)-apple-macos13.0" -I Sources/CLibUSB -L "$LIBUSB_DIR/lib" -lusb-1.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/ScreenDeck"

# 2) Meter libusb dentro de la app
cp "$LIBUSB_DIR/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
chmod u+w "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
OLD=$(otool -L "$APP/Contents/MacOS/ScreenDeck" | awk '/libusb-1.0/{print $1; exit}')
install_name_tool -change "$OLD" "@rpath/libusb-1.0.0.dylib" "$APP/Contents/MacOS/ScreenDeck"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ScreenDeck"

# 3) Icono
swiftc -O tools/make-icon.swift -o build/tmp/make-icon
build/tmp/make-icon build/tmp/AppIcon.iconset && iconutil -c icns build/tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# 4) Versión (rama · commit · fecha) para la etiqueta de la interfaz
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?"); COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "sin-commit")
DATE=$(git log -1 --format=%cI 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S%z); DIRTY=0; [ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=1
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.bugus.screendeck</string>
  <key>CFBundleName</key><string>ScreenDeck</string>
  <key>CFBundleDisplayName</key><string>ScreenDeck</string>
  <key>CFBundleExecutable</key><string>ScreenDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SDBranch</key><string>$BRANCH</string>
  <key>SDCommit</key><string>$COMMIT</string>
  <key>SDDate</key><string>$DATE</string>
  <key>SDDirty</key><string>$DIRTY</string>
</dict></plist>
PLIST

# 5) Firma (con certificado si hay; si no, ad-hoc)
IDENT=""; [ "${SIGN:-}" = adhoc ] || IDENT=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')
S=${IDENT:--}
codesign --force -s "$S" "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
codesign --force --deep -s "$S" "$APP"
echo "OK → $APP  (${IDENT:+firmada con $IDENT}${IDENT:-firma ad-hoc})"
