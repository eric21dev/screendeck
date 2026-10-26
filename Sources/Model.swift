import SwiftUI
import AppKit

// MARK: - Datos configurables

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, system, network, battery, calendar, text, photo
    case weather, disks, processes, thermal, news, panel
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
        case .weather: return "Tiempo"
        case .disks: return "Discos"
        case .processes: return "Procesos"
        case .thermal: return "GPU y temperatura"
        case .news: return "Noticias"
        case .panel: return "Panel"
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
        case .photo: return "Una foto o una carpeta que va rotando"
        case .weather: return "Temperatura y previsión de tu ciudad"
        case .disks: return "Espacio de cada disco y memoria USB"
        case .processes: return "Lo que más CPU y memoria usa"
        case .thermal: return "Uso de la GPU y temperaturas"
        case .news: return "Titulares y resúmenes que van pasando"
        case .panel: return "Varias secciones en una sola pantalla"
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
        case .weather: return "cloud.sun.fill"
        case .disks: return "internaldrive.fill"
        case .processes: return "chart.bar.fill"
        case .thermal: return "thermometer.medium"
        case .news: return "newspaper.fill"
        case .panel: return "square.grid.2x2.fill"
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
        case .weather: return "#FFB84D"
        case .disks: return "#34C8FF"
        case .processes: return "#FF5C8A"
        case .thermal: return "#FF7A59"
        case .news: return "#7C5CFF"
        case .panel: return "#34C8FF"
        }
    }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
    var accent: String
    var text = "¡Hola!"
    var photoPath: String?
    // Foto en modo carpeta (opcionales para que la configuración antigua siga cargando)
    var photoUsesFolder: Bool?
    var photoFolder: String?
    var photoSeconds: Int?
    var photoShuffle: Bool?
    var photoFit: Bool?
    /// Segundos que dura este widget en la rotación; si no hay, se usa el general de la pantalla.
    var seconds: Int?
    // Tiempo
    var weatherPlace: WeatherPlace?
    // Panel
    var panelLayout: String?
    var panelTiles: [String]?
    // Noticias
    var newsCategories: [String]?
    var newsCustomURL: String?
    var newsSeconds: Int?

    init(kind: WidgetKind) {
        self.kind = kind
        self.accent = kind.defaultAccent
    }

    var usesFolder: Bool { photoUsesFolder ?? false }
    var slideSeconds: Int { max(3, photoSeconds ?? 10) }
    var shuffle: Bool { photoShuffle ?? false }
    /// true = la foto se ve entera, con barras negras; false = rellena la pantalla recortando los bordes
    var fitInside: Bool { photoFit ?? false }
    var newsIDs: [String] { newsCategories ?? ["portada"] }
    var newsSlideSeconds: Int { max(5, newsSeconds ?? 12) }
}

struct ScreenConfig: Codable, Equatable {
    var name: String
    var brightness = 60
    var orientation = ScreenOrientation.portrait
    var items: [WidgetItem] = [WidgetItem(kind: .system)]
    var rotationSeconds = 8
    var isOn = true
    /// Puertos USB en los que ha estado esta pantalla, del más reciente al más antiguo (para reconocerla si vuelve).
    var aliases: [String]?
    /// Última vez que estuvo conectada (segundos desde 1970).
    var lastSeen: Double?

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
    private static let orderKey = "screens.order.v1"
    /// Orden de las pantallas en la barra lateral (claves USB), conectadas o no.
    static func loadOrder() -> [String] { UserDefaults.standard.stringArray(forKey: orderKey) ?? [] }
    static func saveOrder(_ v: [String]) {
        if disabled { return }
        UserDefaults.standard.set(v, forKey: orderKey)
    }
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
    @MainActor static func image<V: View>(view: V, size: CGSize) -> CGImage? {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        r.scale = 1
        r.isOpaque = true
        return r.cgImage
    }

    /// Renderiza el widget a un CGImage de exactamente `size` píxeles.
    @MainActor static func image(_ item: WidgetItem, snap: StatsSnapshot, date: Date, size: CGSize, demo: Bool = false) -> CGImage? {
        let r = ImageRenderer(content: WidgetCanvas(item: item, snap: snap, date: date, size: size, demo: demo))
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
    /// La pantalla está apagada por el Mac (bloqueado, suspendido…), aunque en la configuración siga encendida.
    private(set) var suspended = false
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
        let sus = suspended
        queue.async { [weak self] in
            let l = TuringLink(key: key)
            var ok = false
            if let l {
                ok = l.screenOn() && l.setOrientation(cfg.orientation) && l.setBrightness(cfg.brightness)
                if ok && (sus || !cfg.isOn) { l.screenOff() }
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
            let sus = suspended
            queue.async {
                guard let l else { return }
                if on { if !sus { l.screenOn(); l.forgetFrame() } } else { l.screenOff() }
            }
        }
    }

    // MARK: apagar con el Mac

    /// Apaga o enciende la pantalla porque el Mac se bloquea, se suspende o apaga sus pantallas.
    func setSuspended(_ s: Bool) {
        guard s != suspended else { return }
        suspended = s
        let l = link, on = config.isOn, b = config.brightness, o = config.orientation
        queue.async {
            guard let l else { return }
            if s { l.screenOff() } else if on { l.screenOn(); l.setOrientation(o); l.setBrightness(b); l.forgetFrame() }
        }
        if !s { tick() }
    }

    /// Para una pantalla que aparece cuando el Mac ya está bloqueado o dormido.
    func startSuspended() { suspended = true }

    /// Tras despertar el USB puede haberse reiniciado: se abre la conexión de nuevo.
    func reconnect() {
        let old = link
        link = nil; linkReady = false
        queue.async { _ = old }
        connect()
    }

    // MARK: render + envío

    /// Cuánto dura un widget en la rotación: lo suyo o el valor general.
    func duration(of item: WidgetItem) -> Int { max(2, item.seconds ?? config.rotationSeconds) }

    struct Slot {
        var index: Int          // posición del widget en la lista
        var elapsed: Int        // segundos que lleva en pantalla
        var duration: Int       // segundos que dura
        var remaining: Int { duration - elapsed }
    }

    /// Qué widget toca en `date`. Depende solo de la hora, así que no hay que guardar ningún estado.
    func slot(at date: Date = Date()) -> Slot? {
        let items = config.items
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return Slot(index: 0, elapsed: 0, duration: duration(of: items[0])) }
        let durations = items.map(duration(of:))
        var r = Int(date.timeIntervalSince1970) % durations.reduce(0, +)
        for (i, d) in durations.enumerated() {
            if r < d { return Slot(index: i, elapsed: r, duration: d) }
            r -= d
        }
        return nil
    }

    func currentItem(at date: Date = Date()) -> WidgetItem? { slot(at: date).map { config.items[$0.index] } }

    // MARK: identificar

    private var identifyUntil: Date?
    var isIdentifying: Bool { (identifyUntil ?? .distantPast) > Date() }

    /// Muestra el nombre y el ID en la pantalla física durante unos segundos, para saber cuál es cuál.
    func identify(seconds: TimeInterval = 8) {
        identifyUntil = Date().addingTimeInterval(seconds)
        tick()
    }

    func stopIdentifying() { identifyUntil = nil; tick() }

    func tick() {
        let now = Date()
        let (w, h) = config.orientation.pixelSize
        guard let item = currentItem(at: now) else { preview = nil; currentKind = nil; return }
        currentKind = item.kind
        let image: CGImage?
        if isIdentifying {
            image = Renderer.image(view: IdentifyCard(name: config.name, key: key), size: CGSize(width: w, height: h))
        } else {
            image = Renderer.image(item, snap: SystemStats.shared.snapshot, date: now, size: CGSize(width: w, height: h))
        }
        guard let cg = image else { return }
        preview = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        guard config.isOn, !suspended, linkReady, !busy, let link else { return }
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
            config.items.append(WidgetItem(kind: kind))     // al final: el usuario decide el orden
        }
    }

    // MARK: orden y duración de la rotación

    func moveItem(_ kind: WidgetKind, onto target: WidgetKind) {
        guard kind != target, let from = config.items.firstIndex(where: { $0.kind == kind }),
              let to = config.items.firstIndex(where: { $0.kind == target }) else { return }
        var items = config.items
        let it = items.remove(at: from)
        items.insert(it, at: to)
        config.items = items
    }

    func moveItemBy(_ kind: WidgetKind, _ delta: Int) {
        guard let i = config.items.firstIndex(where: { $0.kind == kind }), config.items.indices.contains(i + delta) else { return }
        var items = config.items
        items.swapAt(i, i + delta)
        config.items = items
    }

    func setSeconds(_ kind: WidgetKind, _ seconds: Int?) { update(kind) { $0.seconds = seconds } }

    func useOnly(_ kind: WidgetKind) {
        let existing = config.items.first { $0.kind == kind } ?? WidgetItem(kind: kind)
        config.items = [existing]
    }


    func update(_ kind: WidgetKind, _ change: (inout WidgetItem) -> Void) {
        guard let i = config.items.firstIndex(where: { $0.kind == kind }) else { return }
        var it = config.items[i]
        change(&it)
        config.items[i] = it
    }
}

// MARK: - Todas las pantallas

/// Una fila de la barra lateral: una pantalla conectada o una guardada sin conectar.
enum ScreenEntry: Identifiable {
    case online(ScreenController)
    case offline(OfflineScreen)
    var id: String {
        switch self {
        case .online(let c): return c.key
        case .offline(let o): return o.key
        }
    }
}

/// Aviso al usuario sobre una pantalla cuya identidad conviene comprobar.
struct IdentityNotice: Identifiable {
    enum Kind { case inferred, new }
    let key: String
    let name: String
    let kind: Kind
    var id: String { key }
}

struct RenameRequest {
    var key: String
    var draft: String
}

/// Una pantalla de la que hay configuración guardada pero que ahora no está conectada.
struct OfflineScreen: Identifiable {
    let key: String
    let config: ScreenConfig
    var id: String { key }
}

@MainActor
final class ScreenManager: ObservableObject {
    static let shared = ScreenManager()
    @Published private(set) var screens: [ScreenController] = []
    @Published private(set) var offline: [OfflineScreen] = []
    /// Orden elegido por el usuario. Incluye también las pantallas sin conectar, que conservan su sitio.
    @Published private(set) var order: [String] = Store.loadOrder()
    @Published private(set) var scanning = true
    @Published var selection: String?
    /// Cuadro «Renombrar pantalla» abierto desde el menú de la barra lateral.
    @Published var renaming: RenameRequest?

    private var saved = Store.load()
    private var timer: Timer?
    private var suspendReasons: Set<String> = []
    private var observing = false
    /// Claves de pantallas que se desconectaron en esta sesión, y cuándo (para reconocerlas al volver en otro puerto).
    private var goneAt: [String: Date] = [:]
    @Published private(set) var notices: [IdentityNotice] = []
    /// De dónde viene la identidad que se ha asignado «por posición» a una pantalla (clave nueva → clave antigua).
    private var matchedFrom: [String: String] = [:]

    /// Apagar las pantallas cuando el Mac se bloquea o se suspende, y encenderlas al volver.
    @Published var sleepWithMac: Bool = (UserDefaults.standard.object(forKey: "sleepWithMac") as? Bool) ?? true {
        didSet {
            if !Store.disabled { UserDefaults.standard.set(sleepWithMac, forKey: "sleepWithMac") }
            applySuspension()
        }
    }

    func start() {
        guard timer == nil else { return }
        SystemStats.shared.start()
        observeSystem()
        scan()
        refreshOffline()
        syncOrder()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Primer «Pantalla N» que no esté en uso (así no se repiten nombres tras olvidar alguna).
    private func nextName() -> String {
        let used = Set(saved.values.map(\.name))
        var n = 1
        while used.contains("Pantalla \(n)") { n += 1 }
        return "Pantalla \(n)"
    }

    private func persist() { Store.save(saved) }

    private func refreshOffline() {
        let connected = Set(screens.map(\.key))
        offline = saved.filter { !connected.contains($0.key) }
            .map { OfflineScreen(key: $0.key, config: $0.value) }
            .sorted { $0.config.name.localizedStandardCompare($1.config.name) == .orderedAscending }
    }

    /// Solo para pruebas: sustituye la lista de pantallas que se ven por USB.
    var keysOverride: (() -> [String])?

    func stopTestControllers() { screens.forEach { $0.stop() } }

    /// Solo para pruebas: olvida todo lo que haya en memoria.
    func resetForTest() {
        screens.forEach { $0.stop() }
        screens = []; saved = [:]; goneAt = [:]; notices = []
        setOrder([])
        refreshOffline()
    }

    func scan() {
        let keys = keysOverride?() ?? USBBus.shared.connectedKeys()
        var changed = false
        // Desconectadas
        for s in screens where !keys.contains(s.key) {
            s.stop(); changed = true
            goneAt[s.key] = Date()
            saved[s.key]?.lastSeen = Date().timeIntervalSince1970
        }
        screens.removeAll { !keys.contains($0.key) }
        // Nuevas: se intenta reconocer cuáles son pantallas ya conocidas que han cambiado de puerto
        let fresh = keys.filter { k in !screens.contains(where: { $0.key == k }) }
        // Las pantallas «de fábrica» que creó una versión antigua al cambiar de puerto cuentan como desconocidas
        let legacy = Set(fresh.filter { saved[$0].map(isLegacyDefault) ?? false })
        let unknown = fresh.filter { saved[$0] == nil || legacy.contains($0) }
        var identified = ScreenIdentity.Result()
        if !unknown.isEmpty {
            let candidates = saved.filter { !keys.contains($0.key) && !isLegacyDefault($0.value) }.map { key, cfg in
                ScreenIdentity.Candidate(key: key, aliases: cfg.aliases ?? [key], lastSeen: cfg.lastSeen.map { Date(timeIntervalSince1970: $0) }, goneAt: goneAt[key])
            }
            identified = ScreenIdentity.resolve(unknown: unknown, candidates: candidates)
        }
        for k in fresh {
            var cfg: ScreenConfig
            var needsIdentify = false
            if let old = identified.matches[k] {
                if legacy.contains(k) { saved.removeValue(forKey: k) }      // la de fábrica no tenía nada que conservar
                cfg = rebind(from: old, to: k)
                if identified.inferred.contains(k) {
                    notices.append(IdentityNotice(key: k, name: cfg.name, kind: .inferred)); needsIdentify = true
                    matchedFrom[k] = old
                }
            } else if let s = saved[k] {
                cfg = s
            } else {
                cfg = ScreenConfig(name: nextName())
                if saved.keys.contains(where: { !keys.contains($0) }) {      // hay guardadas sin conectar: podría ser una de ellas
                    notices.append(IdentityNotice(key: k, name: cfg.name, kind: .new)); needsIdentify = true
                }
            }
            cfg.aliases = ([k] + (cfg.aliases ?? []).filter { $0 != k }).prefix(8).map { $0 }
            cfg.lastSeen = Date().timeIntervalSince1970
            saved[k] = cfg
            goneAt[k] = nil
            persist()
            let c = ScreenController(key: k, config: cfg)
            if needsIdentify { c.identify(seconds: 10) }
            if sleepWithMac && !suspendReasons.isEmpty { c.startSuspended() }
            c.onChange = { [weak self] key, cfg in self?.saved[key] = cfg; self?.persist() }
            screens.append(c)
            c.start()
            changed = true
        }
        if changed { refreshOffline() }
        syncOrder()
        // Si la pantalla seleccionada ya no existe ni está guardada, se pasa a la primera conectada
        if selection == nil || (!screens.contains(where: { $0.key == selection }) && saved[selection ?? ""] == nil) {
            selection = screens.first?.key
        }
        scanning = screens.isEmpty
    }

    func copySettings(from source: ScreenController) {
        for s in screens where s.key != source.key {
            s.config.items = source.config.items
            s.config.rotationSeconds = source.config.rotationSeconds
            s.config.brightness = source.config.brightness
        }
    }

    // MARK: bloqueo y suspensión

    var isSuspended: Bool { sleepWithMac && !suspendReasons.isEmpty }

    func setReason(_ reason: String, _ active: Bool) {
        if active { suspendReasons.insert(reason) } else { suspendReasons.remove(reason) }
        applySuspension()
    }

    private func applySuspension() {
        let s = isSuspended
        screens.forEach { $0.setSuspended(s) }
    }

    /// Escucha cuándo el Mac se duerme, apaga las pantallas, se bloquea o cambia de usuario.
    private func observeSystem() {
        guard !observing else { return }
        observing = true
        let ws = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, center: NotificationCenter, reason: String, active: Bool, wake: Bool = false) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setReason(reason, active)
                    if wake { self?.afterWake() }
                }
            }
        }
        watch(NSWorkspace.willSleepNotification, center: ws, reason: "sleep", active: true)
        watch(NSWorkspace.didWakeNotification, center: ws, reason: "sleep", active: false, wake: true)
        watch(NSWorkspace.screensDidSleepNotification, center: ws, reason: "displays", active: true)
        watch(NSWorkspace.screensDidWakeNotification, center: ws, reason: "displays", active: false)
        watch(NSWorkspace.sessionDidResignActiveNotification, center: ws, reason: "session", active: true)
        watch(NSWorkspace.sessionDidBecomeActiveNotification, center: ws, reason: "session", active: false)
        let dn = DistributedNotificationCenter.default()
        watch(Notification.Name("com.apple.screenIsLocked"), center: dn, reason: "lock", active: true)
        watch(Notification.Name("com.apple.screenIsUnlocked"), center: dn, reason: "lock", active: false)
    }

    /// Al despertar, el USB tarda en volver: se reconectan las pantallas pasados unos segundos.
    private func afterWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.scan()
            self.screens.forEach { $0.reconnect() }
        }
    }

    func setAll(on: Bool) { screens.forEach { $0.config.isOn = on } }

    // MARK: orden de la lista

    /// Todas las pantallas conocidas, en el orden elegido por el usuario.
    var entries: [ScreenEntry] {
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }.compactMap { k in
            if let c = screens.first(where: { $0.key == k }) { return .online(c) }
            if let o = offline.first(where: { $0.key == k }) { return .offline(o) }
            return nil
        }
    }

    private func setOrder(_ o: [String]) {
        guard o != order else { return }
        order = o
        Store.saveOrder(o)
    }

    /// Mantiene `order` al día: las pantallas nuevas van al final y las olvidadas desaparecen.
    private func syncOrder() {
        let known = Set(saved.keys).union(screens.map(\.key))
        var o = order.filter { known.contains($0) }
        var seen = Set(o)
        for k in screens.map(\.key) + saved.keys.sorted() where seen.insert(k).inserted { o.append(k) }
        setOrder(o)
    }

    /// Arrastrar `key` sobre `target`: ocupa su posición.
    func move(_ key: String, onto target: String) {
        guard key != target, let from = order.firstIndex(of: key), let to = order.firstIndex(of: target) else { return }
        var o = order
        o.remove(at: from)
        o.insert(key, at: to)
        setOrder(o)
    }

    func moveBy(_ key: String, _ delta: Int) {
        guard let i = order.firstIndex(of: key), order.indices.contains(i + delta) else { return }
        var o = order
        o.swapAt(i, i + delta)
        setOrder(o)
    }

    func canMove(_ key: String, _ delta: Int) -> Bool {
        guard let i = order.firstIndex(of: key) else { return false }
        return order.indices.contains(i + delta)
    }

    /// Solo para las capturas de pruebas: añade pantallas guardadas inventadas (no se guardan).
    func addDemoOffline(_ list: [(key: String, name: String)]) {
        for (k, n) in list where saved[k] == nil { saved[k] = ScreenConfig(name: n) }
        refreshOffline()
        syncOrder()
    }

    func beginRename(_ key: String, name: String) { renaming = RenameRequest(key: key, draft: name) }

    /// Cambia el nombre de una pantalla, esté conectada o no. Se guarda en la configuración de esa pantalla.
    func rename(_ key: String, to raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return }
        if let c = screens.first(where: { $0.key == key }) {
            c.config.name = name                      // dispara el guardado
        } else if saved[key] != nil {
            saved[key]?.name = name
            persist()
            refreshOffline()
        }
    }

    // MARK: identidad

    /// Traslada la identidad guardada de un puerto a otro: la pantalla ha cambiado de sitio.
    private func rebind(from old: String, to new: String) -> ScreenConfig {
        let cfg = saved.removeValue(forKey: old) ?? ScreenConfig(name: nextName())
        // La identidad conserva su sitio; si la clave nueva ya estaba en la lista (una pantalla de fábrica), se quita de ahí
        setOrder(order.filter { $0 != new }.map { $0 == old ? new : $0 })
        if selection == old { selection = new }
        return cfg
    }

    /// Una configuración «de fábrica» creada por una versión antigua (sin historial de puertos): no contiene nada del usuario.
    private func isLegacyDefault(_ c: ScreenConfig) -> Bool {
        c.aliases == nil && c.lastSeen == nil
            && c.name.hasPrefix("Pantalla ") && Int(c.name.dropFirst("Pantalla ".count)) != nil
            && c.items.count == 1 && c.items[0].kind == .system && c.items[0].accent == WidgetKind.system.defaultAccent
            && c.brightness == 60 && c.orientation == .portrait && c.rotationSeconds == 8 && c.isOn
    }

    /// «No es esta»: la identidad que se había asignado por posición vuelve a su sitio y esta pantalla pasa a ser nueva.
    func rejectMatch(_ key: String) {
        defer { dismissNotice(key) }
        guard let c = screens.first(where: { $0.key == key }), let old = matchedFrom.removeValue(forKey: key) else { return }
        var identity = c.config
        identity.aliases = (identity.aliases ?? []).filter { $0 != key }
        saved[old] = identity
        var fresh = ScreenConfig(name: nextName())
        fresh.aliases = [key]
        fresh.lastSeen = Date().timeIntervalSince1970
        c.config = fresh
        persist()
        refreshOffline()
        syncOrder()
    }

    private func touchAlias(_ c: ScreenController) {
        var cfg = c.config
        cfg.aliases = ([c.key] + (cfg.aliases ?? []).filter { $0 != c.key }).prefix(8).map { $0 }
        if cfg.aliases != c.config.aliases { c.config = cfg }
    }

    func dismissNotice(_ key: String) {
        notices.removeAll { $0.key == key }
        matchedFrom[key] = nil
        screens.first { $0.key == key }?.stopIdentifying()
    }

    /// Intercambia la identidad (nombre, widgets, brillo…) de dos pantallas conectadas: estaban al revés.
    func swap(_ a: ScreenController, _ b: ScreenController) {
        let ca = a.config, cb = b.config
        a.config = cb
        b.config = ca
        touchAlias(a); touchAlias(b)
        var o = order
        if let i = o.firstIndex(of: a.key), let j = o.firstIndex(of: b.key) { o.swapAt(i, j) }
        setOrder(o)
        notices.removeAll { $0.key == a.key || $0.key == b.key }
    }

    /// Traslada la configuración guardada de una pantalla sin conectar a una pantalla conectada (nombre, brillo,
    /// orientación y widgets). La entrada guardada se elimina: pasa a vivir en la pantalla de destino.
    func adopt(_ o: OfflineScreen, into c: ScreenController) {
        saved.removeValue(forKey: o.key)
        c.config = o.config          // dispara el guardado y aplica brillo y orientación
        touchAlias(c)
        notices.removeAll { $0.key == c.key }
        persist()
        // La pantalla de destino ocupa el sitio de la guardada
        var ord: [String] = []
        for k in order {
            if k == o.key { ord.append(c.key) } else if k != c.key { ord.append(k) }
        }
        if !ord.contains(c.key) { ord.append(c.key) }
        setOrder(ord)
        refreshOffline()
        selection = c.key
    }

    /// Borra la configuración guardada de una pantalla que no está conectada.
    func forget(_ o: OfflineScreen) {
        guard !screens.contains(where: { $0.key == o.key }) else { return }
        saved.removeValue(forKey: o.key)
        persist()
        refreshOffline()
        setOrder(order.filter { $0 != o.key })
        if selection == o.key { selection = screens.first?.key }
    }
}
