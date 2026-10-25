import Foundation
import IOKit
import IOKit.ps
import AppKit

// Lectores del sistema para los widgets Discos, Procesos y GPU y temperatura.
// Se llaman desde un hilo en segundo plano: ninguno toca la interfaz.

// MARK: - Discos

struct VolumeInfo: Hashable {
    var name: String
    var path: String
    var total: Double       // bytes
    var free: Double        // bytes
    var isExternal: Bool
    var used: Double { total > 0 ? max(0, min(1, 1 - free / total)) : 0 }
}

enum VolumeReader {
    static func read() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsLocalKey,
                                      .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }
        var out: [VolumeInfo] = []
        for u in urls {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsLocal == true, v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = (u.path == "/" ? v.volumeAvailableCapacityForImportantUsage.map { Int($0) } : nil) ?? v.volumeAvailableCapacity ?? 0
            out.append(VolumeInfo(name: v.volumeName ?? u.lastPathComponent, path: u.path, total: Double(total), free: Double(free),
                                  isExternal: v.volumeIsInternal == false))
        }
        // El disco del sistema primero, luego los demás por nombre
        return out.sorted { ($0.path == "/" ? 0 : 1, $0.name.lowercased()) < ($1.path == "/" ? 0 : 1, $1.name.lowercased()) }
    }
}

// MARK: - Procesos

struct ProcessUsage: Hashable {
    var name: String
    var appPath: String?     // ruta del .app, para sacar su icono
    var cpu: Double          // % de un núcleo, como el Monitor de Actividad
    var memBytes: Double
}

enum ProcessReader {
    /// Las apps con sus procesos auxiliares agrupados (Chrome y sus «Helper» cuentan como una sola).
    static func read() -> (cpu: [ProcessUsage], mem: [ProcessUsage]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "pcpu=,rss=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return ([], []) }

        var groups: [String: ProcessUsage] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let cpu = Double(parts[0]), let rss = Double(parts[1]) else { continue }
            let path = parts[2].trimmingCharacters(in: .whitespaces)
            let comps = path.split(separator: "/").map(String.init)
            var name: String, app: String?
            if let i = comps.firstIndex(where: { $0.hasSuffix(".app") }) {
                name = String(comps[i].dropLast(4))
                app = "/" + comps[0...i].joined(separator: "/")
            } else {
                name = comps.last ?? path
            }
            if name == "ps" { continue }
            var g = groups[name] ?? ProcessUsage(name: name, appPath: app, cpu: 0, memBytes: 0)
            g.cpu += cpu
            g.memBytes += rss * 1024
            if g.appPath == nil { g.appPath = app }
            groups[name] = g
        }
        let all = Array(groups.values)
        return (Array(all.sorted { $0.cpu > $1.cpu }.prefix(5)), Array(all.sorted { $0.memBytes > $1.memBytes }.prefix(5)))
    }
}

/// Iconos de las apps, guardados en memoria.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ path: String?) -> NSImage? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        i.size = NSSize(width: 64, height: 64)
        cache[path] = i
        return i
    }
}

// MARK: - GPU

enum GPUReader {
    /// Uso de la GPU en 0…1 (el mayor de los aceleradores). Funciona sin permisos en Apple Silicon.
    static func utilization() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  let perf = d["PerformanceStatistics"] as? [String: Any] else { continue }
            let v = (perf["Device Utilization %"] as? NSNumber) ?? (perf["GPU Activity(%)"] as? NSNumber)
            if let v { best = max(best ?? 0, v.doubleValue / 100) }
        }
        return best
    }
}

// MARK: - Temperaturas

struct TempReading: Hashable {
    var name: String      // CPU, GPU, SSD, Batería
    var celsius: Double
}

enum TemperatureReader {
    /// Estado térmico que da macOS: es público y existe en todos los Mac.
    static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Algo alto"
        case .serious: return "Alto"
        case .critical: return "Crítico"
        @unknown default: return "—"
        }
    }

    // Los sensores de Apple Silicon solo se leen con funciones privadas de IOKit (las mismas que usa el Monitor de
    // Actividad y otras utilidades). Se buscan en tiempo de ejecución: si en tu Mac no existen o cambian, el widget
    // lo dice y sigue funcionando con el estado térmico.
    private typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeRawPointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, CFString) -> UnsafeRawPointer?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeRawPointer?
    private typealias FloatValueFn = @convention(c) (UnsafeRawPointer, Int32) -> Double

    private static func sym<T>(_ name: String, _ t: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(p, to: t)
    }

    static func read() -> [TempReading] {
        guard let create = sym("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let floatValue = sym("IOHIDEventGetFloatValue", FloatValueFn.self),
              let clientPtr = create(kCFAllocatorDefault) else { return [] }
        let client = Unmanaged<AnyObject>.fromOpaque(clientPtr).takeRetainedValue()
        let clientRaw = UnsafeRawPointer(Unmanaged.passUnretained(client).toOpaque())
        _ = setMatching(clientRaw, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let listPtr = copyServices(clientRaw) else { return [] }
        let list = Unmanaged<CFArray>.fromOpaque(listPtr).takeRetainedValue()

        var groups: [String: [Double]] = [:]
        for i in 0..<CFArrayGetCount(list) {
            guard let svc = CFArrayGetValueAtIndex(list, i) else { continue }
            var name = ""
            if let np = copyProperty(svc, "Product" as CFString) {
                name = (Unmanaged<AnyObject>.fromOpaque(np).takeRetainedValue() as? String) ?? ""
            }
            guard let ev = copyEvent(svc, 15, 0, 0) else { continue }          // 15 = temperatura
            let event = Unmanaged<AnyObject>.fromOpaque(ev).takeRetainedValue()
            let c = floatValue(UnsafeRawPointer(Unmanaged.passUnretained(event).toOpaque()), 15 << 16)
            guard c > 5, c < 125 else { continue }
            let n = name.lowercased()
            let group: String?
            if n.contains("gpu") { group = "GPU" }
            else if n.contains("tdie") || n.contains("cpu") || n.contains("soc") { group = "CPU" }
            else if n.contains("nand") || n.contains("ssd") { group = "SSD" }
            else if n.contains("gas gauge") || n.contains("battery") { group = "Batería" }
            else { group = nil }
            if let group { groups[group, default: []].append(c) }
        }
        let order = ["CPU", "GPU", "SSD", "Batería"]
        return order.compactMap { g in
            guard let v = groups[g], !v.isEmpty else { return nil }
            return TempReading(name: g, celsius: v.reduce(0, +) / Double(v.count))
        }
    }
}

// MARK: - Baterías de todos los dispositivos

struct BatteryDevice: Hashable {
    var name: String
    var percent: Int
    var charging: Bool
    var detail: String?        // «I 80% · D 78% · Estuche 100%»
    var isInternal: Bool

    var symbol: String { BatteryDevice.symbol(for: name, isInternal: isInternal) }

    /// Primer símbolo que exista en este macOS (algunos son recientes).
    private static func firstAvailable(_ names: [String]) -> String {
        names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "battery.75percent"
    }

    static func symbol(for name: String, isInternal: Bool) -> String {
        let n = name.lowercased()
        if isInternal { return firstAvailable(["laptopcomputer", "desktopcomputer"]) }
        if n.contains("airpods pro") { return firstAvailable(["airpodspro", "airpods", "headphones"]) }
        if n.contains("airpods max") { return firstAvailable(["airpodsmax", "headphones"]) }
        if n.contains("airpods") { return firstAvailable(["airpods", "headphones"]) }
        if n.contains("trackpad") { return firstAvailable(["trackpad.fill", "trackpad", "rectangle.fill"]) }
        if n.contains("mouse") || n.contains("mx master") || n.contains("mx anywhere") || n.contains("ratón") || n.contains("raton") {
            return firstAvailable(["magicmouse.fill", "computermouse.fill", "magicmouse"])
        }
        if n.contains("keyboard") || n.contains("teclado") || n.contains("keys") { return firstAvailable(["keyboard.fill", "keyboard"]) }
        if n.contains("watch") { return firstAvailable(["applewatch", "watch.analog"]) }
        if n.contains("iphone") { return firstAvailable(["iphone", "iphone.gen3"]) }
        if n.contains("ipad") { return firstAvailable(["ipad", "ipad.gen2"]) }
        if n.contains("controller") || n.contains("gamepad") || n.contains("dualsense") || n.contains("xbox") { return firstAvailable(["gamecontroller.fill", "gamecontroller"]) }
        if n.contains("headphone") || n.contains("headset") || n.contains("buds") || n.contains("ear") || n.contains("wh-") || n.contains("beats") || n.contains("auricular") {
            return firstAvailable(["headphones", "earbuds"])
        }
        return firstAvailable(["battery.75percent", "battery.100"])
    }
}

enum BatteryReader {
    /// Todo lo que macOS expone con batería, sin repetir: el Mac, los accesorios Bluetooth (trackpad, ratón, teclado,
    /// auriculares…) y lo que den los dispositivos HID. Es rápido: se puede llamar cada segundo.
    static func read(extras: [BatteryDevice] = []) -> [BatteryDevice] {
        var out: [BatteryDevice] = []
        func add(_ d: BatteryDevice) {
            guard d.percent >= 0, d.percent <= 100 else { return }
            if !out.contains(where: { $0.name.lowercased() == d.name.lowercased() }) { out.append(d) }
        }
        powerSources().forEach(add)
        hidDevices().forEach(add)
        extras.forEach(add)
        // El Mac primero; el resto, de menos a más carga (lo que antes necesita cargador, arriba)
        return out.sorted { a, b in
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.percent == b.percent ? a.name < b.name : a.percent < b.percent
        }
    }

    /// Fuentes de energía de macOS: la batería del Mac y los accesorios que se ven en `pmset -g accps`.
    private static func powerSources() -> [BatteryDevice] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var out: [BatteryDevice] = []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = (d[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue else { continue }
            let maxCap = (d[kIOPSMaxCapacityKey] as? NSNumber)?.intValue ?? 100
            let pct = maxCap > 0 && maxCap != 100 ? cur * 100 / maxCap : cur
            let type = d[kIOPSTypeKey] as? String
            let isInternal = type == kIOPSInternalBatteryType
            var name = (d[kIOPSNameKey] as? String) ?? "Batería"
            if isInternal { name = "Este Mac" }
            out.append(BatteryDevice(name: name, percent: pct, charging: (d[kIOPSIsChargingKey] as? Bool) ?? false,
                                     detail: nil, isInternal: isInternal))
        }
        return out
    }

    /// Accesorios con batería (trackpad, ratón, teclado, auriculares…). La API pública de fuentes de energía solo da la
    /// batería del Mac, así que se lee lo mismo que muestra `pmset -g accps`. Tarda unos milisegundos: va en segundo plano.
    static func accessories() -> [BatteryDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "accps"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8),
              let re = try? NSRegularExpression(pattern: #"^\s*-(.+?)\s+\(id=\d+\)\s+(\d+)%;?\s*([A-Za-z ]*)"#) else { return [] }
        var out: [BatteryDevice] = []
        for l in text.split(separator: "\n") {
            let line = String(l)
            guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let n = Range(m.range(at: 1), in: line), let pc = Range(m.range(at: 2), in: line),
                  let percent = Int(line[pc]) else { continue }
            let name = String(line[n]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("InternalBattery") { continue }          // la del Mac ya se lee aparte
            let state = Range(m.range(at: 3), in: line).map { String(line[$0]).lowercased() } ?? ""
            out.append(BatteryDevice(name: name, percent: percent, charging: state.contains("charging") && !state.contains("discharging"),
                                     detail: nil, isInternal: false))
        }
        return out
    }

    /// Dispositivos HID de Apple y Bluetooth que publican `BatteryPercent`.
    private static func hidDevices() -> [BatteryDevice] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [BatteryDevice] = []
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  let pct = (d["BatteryPercent"] as? NSNumber)?.intValue,
                  let name = d["Product"] as? String else { continue }
            out.append(BatteryDevice(name: name, percent: pct, charging: false, detail: nil, isInternal: false))
        }
        return out
    }

    /// Auriculares, AirPods y demás que macOS lista en Bluetooth con su batería (izquierdo, derecho, estuche).
    /// `system_profiler` tarda cerca de un segundo: se llama muy de vez en cuando y en segundo plano.
    static func bluetoothExtras() -> [BatteryDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = (j["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: Any]] else { return [] }

        func pct(_ v: Any?) -> Int? {
            guard let s = v as? String else { return nil }
            return Int(s.filter(\.isNumber))
        }
        var out: [BatteryDevice] = []
        for entry in connected {
            for (name, anyProps) in entry {
                guard let props = anyProps as? [String: Any] else { continue }
                let main = pct(props["device_batteryLevelMain"]), left = pct(props["device_batteryLevelLeft"])
                let right = pct(props["device_batteryLevelRight"]), box = pct(props["device_batteryLevelCase"])
                var parts: [String] = []
                if let left { parts.append("I \(left)%") }
                if let right { parts.append("D \(right)%") }
                if let box { parts.append("Estuche \(box)%") }
                let level = main ?? [left, right].compactMap { $0 }.min() ?? box
                guard let level else { continue }
                out.append(BatteryDevice(name: name, percent: level, charging: false,
                                         detail: parts.isEmpty ? nil : parts.joined(separator: " · "), isInternal: false))
            }
        }
        return out
    }
}
