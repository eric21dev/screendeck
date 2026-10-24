#!/bin/bash
# Instala ScreenDeck: compila la app, la copia a Aplicaciones, la abre y comprueba que ve tus pantallas.
#   ./install.sh              instalar o actualizar
#   ./install.sh --uninstall  quitar la app (la configuración se conserva)
#   ./install.sh --purge      quitar la app y su configuración
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME=ScreenDeck; BUNDLE_ID=com.bugus.screendeck
say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
ko() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
screens() { ioreg -p IOUSB -w0 2>/dev/null | grep -c "UsbMonitor" || true; }
dest_dir() { if [ -w /Applications ]; then echo /Applications; else mkdir -p "$HOME/Applications"; echo "$HOME/Applications"; fi; }

if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "--purge" ]; then
  say "Quitando ScreenDeck…"
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true; sleep 1; pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
  if [ "${1:-}" = "--purge" ]; then
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    echo "  Configuración borrada."
  fi
  ok "Hecho"; exit 0
fi

say "1/4 Requisitos"
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || { ko "Hace falta macOS 15 o superior"; exit 1; }
[ "$(uname -m)" = arm64 ] || { ko "Esta versión es solo para Apple Silicon"; exit 1; }
command -v swiftc >/dev/null || { ko "Falta swiftc. Instala las herramientas con:  xcode-select --install"; exit 1; }
LIBUSB=${LIBUSB_DIR:-/opt/homebrew/opt/libusb}
if [ ! -f "$LIBUSB/lib/libusb-1.0.0.dylib" ]; then
  ko "Falta libusb (solo hace falta para compilar). Instálala con:  brew install libusb"; exit 1
fi
ok "macOS $(sw_vers -productVersion), $(swiftc --version 2>&1 | head -1 | cut -c1-50), libusb"

say "2/4 Compilando"
./build.sh > /tmp/screendeck-build.log 2>&1 || { ko "Falló la compilación (log: /tmp/screendeck-build.log)"; tail -15 /tmp/screendeck-build.log; exit 1; }
ok "ScreenDeck.app compilada"

say "3/4 Instalando"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true; sleep 1; pkill -x "$APP_NAME" 2>/dev/null || true
DEST="$(dest_dir)"; rm -rf "$DEST/$APP_NAME.app"; ditto build/$APP_NAME.app "$DEST/$APP_NAME.app"
ok "Instalada en $DEST/$APP_NAME.app"
open "$DEST/$APP_NAME.app"

say "4/4 Comprobando"
for i in $(seq 1 10); do pgrep -x "$APP_NAME" >/dev/null && break; sleep 1; done
pgrep -x "$APP_NAME" >/dev/null && ok "ScreenDeck está abierta" || { ko "No se ha abierto"; exit 1; }
n=$(screens)
if [ "$n" -gt 0 ]; then ok "$n pantalla(s) conectada(s) detectada(s) por USB"
else echo "  Aún no hay pantallas conectadas: enchúfalas y aparecerán solas en la barra lateral."; fi
echo
say "Listo. ScreenDeck no necesita ningún permiso de macOS."
echo "Para que se abra sola al iniciar sesión, marca «Abrir al iniciar sesión» en la barra lateral."
