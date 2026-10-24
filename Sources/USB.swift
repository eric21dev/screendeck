import Foundation
import CLibUSB

// Pantallas Turing / UsbMonitor 3.5" (Rev. A). En macOS el puerto serie (/dev/cu.usbmodem*) corrompe las imágenes:
// el firmware lee un comando al principio de cada transferencia USB y cuenta él mismo los píxeles. Por eso se escribe
// directo al endpoint USB bulk OUT 0x03 con libusb: un comando por transferencia y los píxeles en bloques de 64 bytes.

let turingVID: UInt16 = 0x1A86
let turingPID: UInt16 = 0x5722
private let usbInterface: Int32 = 1
private let outEndpoint: UInt8 = 0x03
private let chunkSize = 4096          // múltiplo de 64
private let writeTimeoutMs: UInt32 = 5000

enum ScreenOrientation: Int, Codable, CaseIterable, Identifiable {
    case portrait = 0, reversePortrait = 1, landscape = 2, reverseLandscape = 3
    var id: Int { rawValue }
    var isPortrait: Bool { self == .portrait || self == .reversePortrait }
    var pixelSize: (w: Int, h: Int) { isPortrait ? (320, 480) : (480, 320) }
    var title: String {
        switch self {
        case .portrait: return "Vertical"
        case .landscape: return "Horizontal"
        case .reversePortrait: return "Vertical ↻"
        case .reverseLandscape: return "Horizontal ↻"
        }
    }
    var symbol: String { isPortrait ? "rectangle.portrait" : "rectangle" }
}

/// Acceso a libusb y localización de pantallas conectadas.
final class USBBus {
    static let shared = USBBus()
    private var ctx: OpaquePointer?
    private let lock = NSLock()

    private init() { libusb_init(&ctx) }

    private func key(of dev: OpaquePointer) -> String {
        var ports = [UInt8](repeating: 0, count: 8)
        let n = Int(libusb_get_port_numbers(dev, &ports, 8))
        let path = ports.prefix(max(n, 0)).map { String($0) }.joined(separator: ".")
        return "\(libusb_get_bus_number(dev))-\(path)"
    }

    /// Identificadores estables (bus + ruta de puertos) de todas las pantallas conectadas.
    func connectedKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        var list: UnsafeMutablePointer<OpaquePointer?>?
        let n = libusb_get_device_list(ctx, &list)
        guard n > 0, let list else { return [] }
        defer { libusb_free_device_list(list, 1) }
        var keys: [String] = []
        for i in 0..<n {
            guard let dev = list[i] else { continue }
            var d = libusb_device_descriptor()
            if libusb_get_device_descriptor(dev, &d) == 0, d.idVendor == turingVID, d.idProduct == turingPID {
                keys.append(key(of: dev))
            }
        }
        return keys.sorted()
    }

    func open(key wanted: String) -> OpaquePointer? {
        lock.lock(); defer { lock.unlock() }
        var list: UnsafeMutablePointer<OpaquePointer?>?
        let n = libusb_get_device_list(ctx, &list)
        guard n > 0, let list else { return nil }
        defer { libusb_free_device_list(list, 1) }
        for i in 0..<n {
            guard let dev = list[i] else { continue }
            var d = libusb_device_descriptor()
            guard libusb_get_device_descriptor(dev, &d) == 0, d.idVendor == turingVID, d.idProduct == turingPID,
                  key(of: dev) == wanted else { continue }
            var handle: OpaquePointer?
            if libusb_open(dev, &handle) == 0 { return handle }
        }
        return nil
    }
}

/// Conexión con una pantalla. Todos los métodos deben llamarse desde la misma cola serie.
final class TuringLink: @unchecked Sendable {
    private var handle: OpaquePointer
    private var previous: [UInt8]?
    private var lastFull = Date.distantPast
    private(set) var failed = false

    init?(key: String) {
        guard let h = USBBus.shared.open(key: key) else { return nil }
        var cfg: Int32 = 0
        if libusb_get_configuration(h, &cfg) != 0 || cfg != 1 { _ = libusb_set_configuration(h, 1) }
        guard libusb_claim_interface(h, usbInterface) == 0 else { libusb_close(h); return nil }
        handle = h
    }

    deinit {
        libusb_release_interface(handle, usbInterface)
        libusb_close(handle)
    }

    // MARK: transferencias

    @discardableResult
    private func write(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return true }
        var sent: Int32 = 0
        let r = libusb_bulk_transfer(handle, outEndpoint, UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: UInt8.self)),
                                     Int32(bytes.count), &sent, writeTimeoutMs)
        if r != 0 || Int(sent) != bytes.count { failed = true; return false }
        return true
    }

    private func command(_ c: UInt8, _ x: Int = 0, _ y: Int = 0, _ ex: Int = 0, _ ey: Int = 0) -> Bool {
        var b = [UInt8](repeating: 0, count: 6)
        b[0] = UInt8(truncatingIfNeeded: x >> 2)
        b[1] = UInt8(truncatingIfNeeded: ((x & 3) << 6) + (y >> 4))
        b[2] = UInt8(truncatingIfNeeded: ((y & 15) << 4) + (ex >> 6))
        b[3] = UInt8(truncatingIfNeeded: ((ex & 63) << 2) + (ey >> 8))
        b[4] = UInt8(truncatingIfNeeded: ey & 255)
        b[5] = c
        let ok = b.withUnsafeBytes { write($0) }
        usleep(5000)
        return ok
    }

    // MARK: operaciones

    @discardableResult func screenOn() -> Bool { command(109) }
    @discardableResult func screenOff() -> Bool { previous = nil; return command(108) }
    @discardableResult func reset() -> Bool { previous = nil; return command(101) }

    @discardableResult func setBrightness(_ percent: Int) -> Bool {
        let p = max(0, min(100, percent))
        return command(110, Int(255 - (Double(p) / 100 * 255)))
    }

    @discardableResult func setOrientation(_ o: ScreenOrientation) -> Bool {
        let (w, h) = o.pixelSize
        var b = [UInt8](repeating: 0, count: 11)   // 11 bytes, no 16
        b[5] = 121
        b[6] = UInt8(o.rawValue + 100)
        b[7] = UInt8(w >> 8); b[8] = UInt8(w & 255)
        b[9] = UInt8(h >> 8); b[10] = UInt8(h & 255)
        previous = nil
        let ok = b.withUnsafeBytes { write($0) }
        usleep(5000)
        return ok
    }

    /// Envía solo las filas que han cambiado (o la imagen entera si hace falta). `frame` es RGB565 little-endian.
    @discardableResult func present(frame: [UInt8], width: Int, height: Int) -> Bool {
        let rowBytes = width * 2
        guard frame.count == rowBytes * height else { return false }
        var r0 = 0, r1 = height - 1
        let forceFull = Date().timeIntervalSince(lastFull) > 30
        if let prev = previous, prev.count == frame.count, !forceFull {
            var first = -1, last = -1
            frame.withUnsafeBytes { f in
                prev.withUnsafeBytes { p in
                    for row in 0..<height {
                        let o = row * rowBytes
                        if memcmp(f.baseAddress! + o, p.baseAddress! + o, rowBytes) != 0 {
                            if first < 0 { first = row }
                            last = row
                        }
                    }
                }
            }
            if first < 0 { return true }       // nada que enviar
            r0 = first; r1 = last
        } else {
            lastFull = Date()
        }
        guard command(197, 0, r0, width - 1, r1) else { return false }
        let ok: Bool = frame.withUnsafeBytes { f in
            var off = r0 * rowBytes
            let end = (r1 + 1) * rowBytes
            while off < end {
                let n = min(chunkSize, end - off)
                if !write(UnsafeRawBufferPointer(rebasing: f[off..<off + n])) { return false }
                off += n
            }
            return true
        }
        if ok { previous = frame }
        return ok
    }

    func forgetFrame() { previous = nil }
}
