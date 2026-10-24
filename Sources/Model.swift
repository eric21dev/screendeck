import SwiftUI
import AppKit

// MARK: - Datos configurables

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, system, network, battery, calendar, text, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clock: return "Reloj"
        case .system: return "Sistema"
        case .network: return "Red"
        case .battery: return "Energía"
        case .calendar: return "Calendario"
        case .text: return "Mensaje"
        case .photo: return "Foto"
        }
    }
    var subtitle: String {
        switch self {
        case .clock: return "Hora y fecha"
        case .system: return "CPU, memoria y disco"
        case .network: return "Velocidad de subida y bajada"
        case .battery: return "Batería y tiempo encendido"
        case .calendar: return "El mes actual"
        case .text: return "Tu texto en grande"
        case .photo: return "Una imagen a pantalla completa"
        }
    }
    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .system: return "cpu.fill"
        case .network: return "network"
        case .battery: return "bolt.fill"
        case .calendar: return "calendar"
        case .text: return "textformat"
        case .photo: return "photo.fill"
        }
    }
    var defaultAccent: String {
        switch self {
        case .clock: return "#34C8FF"
        case .system: return "#7C5CFF"
        case .network: return "#34C8FF"
        case .battery: return "#2ED573"
        case .calendar: return "#FF5C8A"
        case .text: return "#FFD93D"
        case .photo: return "#34C8FF"
        }
    }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
    var accent: String
    var text = "¡Hola!"
    var photoPath: String?

    init(kind: WidgetKind) {
        self.kind = kind
        self.accent = kind.defaultAccent
    }
}

struct ScreenConfig: Codable, Equatable {
    var name: String
    var brightness = 60
    var orientation = ScreenOrientation.portrait
    var items: [WidgetItem] = [WidgetItem(kind: .system)]
    var rotationSeconds = 8
    var isOn = true

    static func == (a: ScreenConfig, b: ScreenConfig) -> Bool {
        a.name == b.name && a.brightness == b.brightness && a.orientation == b.orientation
            && a.items == b.items && a.rotationSeconds == b.rotationSeconds && a.isOn == b.isOn
    }
}

enum Store {
    private static let key = "screens.v1"
    static func load() -> [String: ScreenConfig] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([String: ScreenConfig].self, from: d) else { return [:] }
        return v
    }
    /// En el modo de capturas no se toca la configuración guardada.
    static var disabled = false
    static func save(_ v: [String: ScreenConfig]) {
        if disabled { return }
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct BuildInfo {
    let branch, commit, date: String
    let dirty: Bool
    static let current: BuildInfo = {
        let i = Bundle.main.infoDictionary ?? [:]
        return BuildInfo(branch: i["SDBranch"] as? String ?? "dev", commit: i["SDCommit"] as? String ?? "sin-commit",
                         date: i["SDDate"] as? String ?? "", dirty: (i["SDDirty"] as? String) == "1")
    }()
    var label: String {
        var d = date
        if let t = ISO8601DateFormatter().date(from: date) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; d = f.string(from: t)
        }
        return "\(branch) · \(commit)\(dirty ? "*" : "") · \(d)"
    }
}

// MARK: - Render

enum Renderer {
    /// Renderiza el widget a un CGImage de exactamente `size` píxeles.
    @MainActor static func image(_ item: WidgetItem, snap: StatsSnapshot, date: Date, size: CGSize) -> CGImage? {
        let r = ImageRenderer(content: WidgetCanvas(item: item, snap: snap, date: date, size: size))
        r.scale = 1
        r.isOpaque = true
        return r.cgImage
    }

    /// RGB565 little-endian, como espera la pantalla.
    static func rgb565(_ cg: CGImage, width: Int, height: Int) -> [UInt8]? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var out = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            let r = UInt16(rgba[i * 4]), g = UInt16(rgba[i * 4 + 1]), b = UInt16(rgba[i * 4 + 2])
            let v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            out[i * 2] = UInt8(v & 255)
            out[i * 2 + 1] = UInt8(v >> 8)
        }
        return out
    }
}

// MARK: - Una pantalla conectada

@MainActor
final class ScreenController: ObservableObject, Identifiable {
    enum Status: Equatable { case connecting, ready, error(String) }

    let key: String
    nonisolated var id: String { key }
    @Published var config: ScreenConfig { didSet { configChanged(old: oldValue) } }
    @Published private(set) var status: Status = .connecting
    @Published private(set) var preview: NSImage?
    @Published private(set) var currentKind: WidgetKind?
    /// Widget cuyos ajustes se muestran en la ventana (estado de la interfaz).
    @Published var editingKind: WidgetKind?

    private let queue: DispatchQueue
    private var link: TuringLink?
    private var linkReady = false
    private var busy = false
    private var timer: Timer?
    private var brightnessWork: DispatchWorkItem?
    private var failures = 0
    var onChange: ((String, ScreenConfig) -> Void)?

    init(key: String, config: ScreenConfig) {
        self.key = key
        self.config = config
        self.queue = DispatchQueue(label: "screendeck.\(key)")
    }

    func start() {
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let l = link; link = nil; linkReady = false
        queue.async { if let l { l.screenOff(); _ = l } }
    }

    // MARK: conexión

    private func connect() {
        status = .connecting
        let cfg = config
        let key = key
        queue.async { [weak self] in
            let l = TuringLink(key: key)
            var ok = false
            if let l {
                ok = l.screenOn() && l.setOrientation(cfg.orientation) && l.setBrightness(cfg.brightness)
            }
            Task { @MainActor in
                guard let self else { return }
                if ok, let l {
                    self.link = l; self.linkReady = true; self.failures = 0; self.status = .ready
                } else {
                    self.link = nil; self.linkReady = false; self.failures += 1
                    self.status = .error(self.failures > 2
                        ? "La pantalla no responde. Desenchúfala y vuelve a enchufarla."
                        : "No se puede abrir la pantalla…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self, self.timer != nil, !self.linkReady else { return }
                        self.connect()
                    }
                }
            }
        }
    }

    /// Reinicia la pantalla (solo funciona si no se ha desincronizado; si no, hay que desenchufarla).
    func restart() {
        let l = link
        linkReady = false; link = nil; status = .connecting
        queue.async { [weak self] in
            l?.reset()
            Thread.sleep(forTimeInterval: 4)
            Task { @MainActor in self?.connect() }
        }
    }

    // MARK: cambios de configuración

    private func configChanged(old: ScreenConfig) {
        onChange?(key, config)
        if config.brightness != old.brightness {
            brightnessWork?.cancel()
            let b = config.brightness
            let l = link
            let w = DispatchWorkItem { l?.setBrightness(b) }
            brightnessWork = w
            queue.asyncAfter(deadline: .now() + 0.15, execute: w)
        }
        if config.orientation != old.orientation {
            let o = config.orientation
            let l = link
            queue.async { l?.setOrientation(o) }
            tick()
        }
        if config.isOn != old.isOn {
            let on = config.isOn
            let l = link
            queue.async {
                guard let l else { return }
                if on { l.screenOn(); l.forgetFrame() } else { l.screenOff() }
            }
        }
    }

    // MARK: render + envío

    func currentItem(at date: Date = Date()) -> WidgetItem? {
        let items = config.items
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return items[0] }
        let step = max(2, config.rotationSeconds)
        return items[Int(date.timeIntervalSince1970) / step % items.count]
    }

    func tick() {
        let now = Date()
        let (w, h) = config.orientation.pixelSize
        guard let item = currentItem(at: now) else { preview = nil; currentKind = nil; return }
        currentKind = item.kind
        guard let cg = Renderer.image(item, snap: SystemStats.shared.snapshot, date: now, size: CGSize(width: w, height: h)) else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        guard config.isOn, linkReady, !busy, let link else { return }
        guard let frame = Renderer.rgb565(cg, width: w, height: h) else { return }
        busy = true
        queue.async { [weak self] in
            let ok = link.present(frame: frame, width: w, height: h)
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                if !ok, self.link === link {
                    self.linkReady = false; self.link = nil
                    self.status = .error("Se perdió la conexión con la pantalla")
                    self.connect()
                }
            }
        }
    }

    // MARK: edición de widgets

    func isUsing(_ kind: WidgetKind) -> Bool { config.items.contains { $0.kind == kind } }

    func toggle(_ kind: WidgetKind) {
        if let i = config.items.firstIndex(where: { $0.kind == kind }) {
            if config.items.count > 1 { config.items.remove(at: i) }   // siempre queda al menos una
        } else {
            config.items.append(WidgetItem(kind: kind))
            config.items.sort { order($0.kind) < order($1.kind) }
        }
    }

    func useOnly(_ kind: WidgetKind) {
        let existing = config.items.first { $0.kind == kind } ?? WidgetItem(kind: kind)
        config.items = [existing]
    }

    private func order(_ k: WidgetKind) -> Int { WidgetKind.allCases.firstIndex(of: k) ?? 0 }

    func update(_ kind: WidgetKind, _ change: (inout WidgetItem) -> Void) {
        guard let i = config.items.firstIndex(where: { $0.kind == kind }) else { return }
        var it = config.items[i]
        change(&it)
        config.items[i] = it
    }
}

// MARK: - Todas las pantallas

@MainActor
final class ScreenManager: ObservableObject {
    static let shared = ScreenManager()
    @Published private(set) var screens: [ScreenController] = []
    @Published private(set) var scanning = true
    @Published var selection: String?

    private var saved = Store.load()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        SystemStats.shared.start()
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func scan() {
        let keys = USBBus.shared.connectedKeys()
        // Desconectadas
        for s in screens where !keys.contains(s.key) { s.stop() }
        screens.removeAll { !keys.contains($0.key) }
        // Nuevas
        for k in keys where !screens.contains(where: { $0.key == k }) {
            let cfg = saved[k] ?? ScreenConfig(name: "Pantalla \(saved.count + 1)")
            saved[k] = cfg
            let c = ScreenController(key: k, config: cfg)
            c.onChange = { [weak self] key, cfg in self?.saved[key] = cfg; Store.save(self?.saved ?? [:]) }
            screens.append(c)
            c.start()
        }
        Store.save(saved)
        if selection == nil || !screens.contains(where: { $0.key == selection }) { selection = screens.first?.key }
        scanning = screens.isEmpty
    }

    func copySettings(from source: ScreenController) {
        for s in screens where s.key != source.key {
            s.config.items = source.config.items
            s.config.rotationSeconds = source.config.rotationSeconds
            s.config.brightness = source.config.brightness
        }
    }

    func setAll(on: Bool) { screens.forEach { $0.config.isOn = on } }
}
