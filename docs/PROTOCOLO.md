# Protocolo de la Turing Smart Screen 3,5" (Rev. A) por USB

Notas técnicas de lo que usa ScreenDeck (`Sources/USB.swift`). Se han comprobado con una pantalla `UsbMonitor` (`1a86:5722`, serie `USB35INCHIPSV2`) en macOS 26 con Apple Silicon.

## El dispositivo

| | |
|---|---|
| VID : PID | `0x1A86 : 0x5722` |
| Fabricante / producto / serie | `Turing` (o `2017-2-25`) · `UsbMonitor` · `USB35INCHIPSV2` |
| Interfaces | 2 (CDC). Los datos van en la **interfaz 1** |
| Endpoint de datos | **bulk OUT `0x03`** |
| Píxeles | RGB565 **little-endian** (`(r>>3)<<11 \| (g>>2)<<5 \| b>>3`, byte bajo primero) |
| Resolución | 320 × 480 en vertical, 480 × 320 en horizontal |
| Identificación | No responde al comando `HELLO`; se asume 3,5" |

## Reglas de la transferencia

Lo importante, y lo que hace que falle en macOS por puerto serie:

1. **El firmware lee un comando al principio de cada transferencia USB y descarta el resto de esa transferencia.** Un comando debe ir **solo** en su transferencia.
2. Tras `DISPLAY_BITMAP`, la pantalla **cuenta exactamente `ancho × alto × 2` bytes** de píxeles. Cualquier byte que llegue antes de completar el rectángulo, aunque parezca un comando, se traga como píxel.
3. Si la cuenta se desincroniza (un byte perdido o mal agrupado), todos los comandos siguientes se interpretan como píxeles y la imagen queda corrupta **hasta cortar la corriente**. El comando `RESET` solo llega si el flujo está sincronizado.
4. Los píxeles se envían en bloques múltiplo de 64 bytes (ScreenDeck usa 4096), sumando exactamente `ancho × alto × 2`. No se escribe nada más mientras hay una imagen en curso.

## Comandos

Un comando son **6 bytes**, con coordenadas empaquetadas en 10 bits cada una:

```
b0 = x  >> 2
b1 = ((x  & 3)  << 6) + (y  >> 4)
b2 = ((y  & 15) << 4) + (ex >> 6)
b3 = ((ex & 63) << 2) + (ey >> 8)
b4 = ey & 255
b5 = código de comando
```

| Código | Comando | Parámetros |
|---|---|---|
| 101 | `RESET` | — |
| 102 | `CLEAR` | — (pone la pantalla en blanco) |
| 108 | `SCREEN_OFF` | — |
| 109 | `SCREEN_ON` | — |
| 110 | `SET_BRIGHTNESS` | `x` = `255 − porcentaje × 2,55` (0 es el máximo brillo, 255 apagado) |
| 121 | `SET_ORIENTATION` | **11 bytes**, ver abajo |
| 197 | `DISPLAY_BITMAP` | `(x, y)` esquina superior izquierda, `(ex, ey)` esquina inferior derecha, **inclusivas**; a continuación los píxeles |

### `SET_ORIENTATION` (11 bytes)

```
b5  = 121
b6  = orientación + 100      (0 vertical, 1 vertical invertida, 2 horizontal, 3 horizontal invertida)
b7  = ancho >> 8     b8  = ancho & 255
b9  = alto  >> 8     b10 = alto  & 255
```

`ancho` y `alto` son los del marco ya girado (320 × 480 en vertical, 480 × 320 en horizontal). Por el puerto serie algunas implementaciones mandan 16 bytes; por USB directo deben ser 11.

## Secuencia de una imagen

```
write( comando DISPLAY_BITMAP (6 bytes) )      ← transferencia propia
pausa ≈ 5 ms
write( píxeles[0 ..< 4096] )
write( píxeles[4096 ..< 8192] )
…                                              ← total exacto: ancho × alto × 2 bytes
```

Para actualizar solo una zona, se manda un rectángulo más pequeño (ScreenDeck manda las filas completas entre la primera y la última que han cambiado).

## Por el puerto serie en macOS

El driver CDC de macOS reagrupa y fragmenta el flujo de bytes, así que el comando acaba pegado a los píxeles o partido por la mitad: se rompe la regla 1 y se pierde la cuenta (regla 3). Se probó sin éxito: trozos más pequeños, pausas, `flush`, quitar `RTS/CTS`, bajar el brillo, otro cable y otros puertos. Los **colores lisos** sí se ven bien porque todos los bytes son iguales y perder alguno no cambia la imagen, lo que oculta el problema.

## Fuentes

- [Issue #7 de turing-smart-screen-python](https://github.com/mathoudebine/turing-smart-screen-python/issues/7): hallazgos de **marcelors27** (escritura directa al endpoint bulk `0x03` con PyUSB/libusb, comprobado con una captura de tráfico USB del software oficial en Windows) y de **amarok30** (semántica de transferencia del firmware).
- Formato de los comandos de la Rev. A: [turing-smart-screen-python](https://github.com/mathoudebine/turing-smart-screen-python) (`library/lcd/lcd_comm_rev_a.py`).
