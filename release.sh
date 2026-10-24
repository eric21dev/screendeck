#!/bin/bash
# Crea build/ScreenDeck-<versión>.dmg: firma ad-hoc, libusb incluido y acceso directo a Aplicaciones.
# Solo Apple Silicon (libusb viene compilado para arm64).
#   ./release.sh [versión]
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${1:-1.0}
SIGN=adhoc VERSION=$VERSION ./build.sh
rm -rf build/dmg && mkdir -p build/dmg
ditto build/ScreenDeck.app build/dmg/ScreenDeck.app
ln -s /Applications build/dmg/Applications
cp tools/dmg-leeme.txt build/dmg/LEEME.txt
DMG="build/ScreenDeck-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "ScreenDeck $VERSION" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
echo "OK → $DMG"; shasum -a 256 "$DMG"
