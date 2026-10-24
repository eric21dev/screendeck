# Componentes de terceros

## libusb

ScreenDeck incluye una copia de **libusb 1.0.x** (`ScreenDeck.app/Contents/Frameworks/libusb-1.0.0.dylib`), tal y como la distribuye Homebrew, sin modificar.

- Proyecto: <https://libusb.info> · código: <https://github.com/libusb/libusb>
- Licencia: **GNU LGPL 2.1** (<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>)

La biblioteca va como un archivo `.dylib` independiente y la app la enlaza dinámicamente, de modo que puedes sustituirla por otra versión compilada de libusb: reemplaza ese archivo dentro de la app y vuelve a firmarla con `codesign --force --deep -s - ScreenDeck.app`.

El código de ScreenDeck (carpeta `Sources/`) es independiente de libusb y se distribuye bajo licencia MIT (ver `LICENSE`).
