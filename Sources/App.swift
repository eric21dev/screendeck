import SwiftUI
import AppKit

@main
struct ScreenDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var manager = ScreenManager.shared

    var body: some Scene {
        WindowGroup("ScreenDeck", id: "main") {
            RootView()
                .environmentObject(manager)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuContent().environmentObject(manager)
        } label: {
            Image(systemName: "display.2")
        }
    }
}

/// Impresión para el modo de pruebas (se usa también desde tareas en segundo plano).
func line(_ s: String) { print(s) }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(into: args[i + 1])
            NSApp.terminate(nil)
            return
        }
        if args.contains("--selftest-rotation") {
            Store.disabled = true
            selfTestRotation()
            NSApp.terminate(nil)
            return
        }
        if args.contains("--selftest-sleep") {
            Store.disabled = true
            ScreenManager.shared.start()
            selfTestSleep()
            return
        }
        if args.contains("--selftest") {
            selfTest()
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            Store.disabled = true          // no se toca la configuración guardada
            SystemStats.shared.demoMode = true   // datos de ejemplo: las capturas no llevan nada personal
            DataHub.shared.demoMode = true
            ScreenManager.shared.start()
            captureWindows(into: args[i + 1])
            return
        }
        ScreenManager.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenManager.shared.screens.forEach { $0.stop() }
    }

    /// Prueba la rotación con duraciones propias y el cambio de orden (sin pantallas).
    private func selfTestRotation() {
        let c = ScreenController(key: "prueba", config: ScreenConfig(name: "prueba"))
        var cfg = c.config
        cfg.rotationSeconds = 8
        var sys = WidgetItem(kind: .system); sys.seconds = 3
        var net = WidgetItem(kind: .network); net.seconds = 5
        cfg.items = [WidgetItem(kind: .clock), sys, net]
        c.config = cfg
        func letter(_ k: WidgetKind) -> String { String(k.rawValue.prefix(1)).uppercased() }
        func sequence(_ n: Int) -> String {
            let base = 1_800_000_000        // múltiplo de 16 = 8 + 3 + 5
            return (0..<n).map { i -> String in
                guard let it = c.currentItem(at: Date(timeIntervalSince1970: Double(base + i))) else { return "-" }
                return letter(it.kind)
            }.joined().replacingOccurrences(of: "(?<=(.))(?!\\1)", with: "|", options: .regularExpression)
        }
        func order() -> String { c.config.items.map { "\($0.kind.rawValue)(\($0.seconds.map { "\($0)s" } ?? "gen"))" }.joined(separator: " → ") }
        line("orden:  " + order())
        line("32 s:   " + sequence(32) + "    (reloj 8 · sistema 3 · red 5, y se repite)")
        let s0 = c.slot(at: Date(timeIntervalSince1970: 1_800_000_009))
        line("a los 9 s: widget \(s0.map { c.config.items[$0.index].kind.rawValue } ?? "-"), lleva \(s0?.elapsed ?? -1) s de \(s0?.duration ?? -1), faltan \(s0?.remaining ?? -1)")
        c.moveItem(.network, onto: .clock)
        line("mover red sobre reloj:     " + order())
        c.moveItemBy(.system, -1)
        line("subir sistema:             " + order())
        c.setSeconds(.system, nil)
        line("sistema → duración general: " + order())
        c.toggle(.battery)
        line("añadir energía:            " + order() + "   (al final, sin reordenar)")
        c.toggle(.clock)
        line("quitar reloj:              " + order())
    }

    /// Prueba el apagado con el Mac: simula bloquear y desbloquear la sesión y comprueba el estado de cada pantalla.
    /// Las pantallas se apagan unos segundos de verdad.
    private func selfTestSleep() {
        let m = ScreenManager.shared
        func state() -> String { m.screens.map { "\($0.config.name)=\($0.suspended ? "apagada por el Mac" : "normal")" }.joined(separator: ", ") }
        let dn = DistributedNotificationCenter.default()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            line("1. antes de bloquear:   " + state() + "  | apagar con el Mac: \(m.sleepWithMac)")
            dn.postNotificationName(Notification.Name("com.apple.screenIsLocked"), object: nil, userInfo: nil, deliverImmediately: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                line("2. bloqueado:           " + state())
                m.sleepWithMac = false
                line("3. opción desactivada:  " + state())
                m.sleepWithMac = true
                line("4. opción activada:     " + state())
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    dn.postNotificationName(Notification.Name("com.apple.screenIsUnlocked"), object: nil, userInfo: nil, deliverImmediately: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        line("5. desbloqueado:        " + state())
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    /// Modo de pruebas: lee los sensores de este Mac y descarga tiempo y noticias de verdad, e imprime lo que obtiene.
    private func selfTest() {
        line("— Discos")
        for v in VolumeReader.read() {
            line("  \(v.name) [\(v.path)] total \(Int(v.total / 1e9)) GB, libres \(Int(v.free / 1e9)) GB, externo=\(v.isExternal), usado \(Int(v.used * 100))%")
        }
        line("— Procesos (2 muestras, 2 s)")
        _ = ProcessReader.read(); Thread.sleep(forTimeInterval: 2)
        let p = ProcessReader.read()
        line("  CPU: " + p.cpu.map { "\($0.name) \(Int($0.cpu))%" }.joined(separator: ", "))
        line("  Mem: " + p.mem.map { "\($0.name) \(String(format: "%.1f", $0.memBytes / 1_073_741_824)) GB" }.joined(separator: ", "))
        line("— Baterías (macOS): " + BatteryReader.read(extras: BatteryReader.accessories()).map { "\($0.name) \($0.percent)%\($0.charging ? " ⚡" : "")" }.joined(separator: ", "))
        let bt = BatteryReader.bluetoothExtras()
        line("— Baterías (Bluetooth conectados con batería): " + (bt.isEmpty ? "ninguno" : bt.map { "\($0.name) \($0.percent)% \($0.detail ?? "")" }.joined(separator: ", ")))
        line("— GPU: \(GPUReader.utilization().map { "\(Int($0 * 100))%" } ?? "sin datos")")
        let temps = TemperatureReader.read()
        line("— Temperaturas: " + (temps.isEmpty ? "sin sensores" : temps.map { "\($0.name) \(Int($0.celsius))°C" }.joined(separator: ", ")) + " · estado térmico \(TemperatureReader.thermalState)")
        // Red
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            let places = await DataHub.searchPlaces("Sevilla")
            line("— Búsqueda «Sevilla»: " + places.prefix(3).map { "\($0.name) (\($0.region))" }.joined(separator: " | "))
            if let pl = places.first {
                _ = DataHub.shared.weather(for: pl)
                for _ in 0..<20 { if DataHub.shared.weather(for: pl) != nil { break }; try? await Task.sleep(nanoseconds: 500_000_000) }
                if let w = DataHub.shared.weather(for: pl) {
                    line("— Tiempo en \(pl.name): \(Int(w.temperature))° \(WeatherCode.text(w.code)), sensación \(Int(w.feelsLike))°, humedad \(w.humidity)%, viento \(Int(w.windKmh)) km/h")
                    line("  horas: " + w.hours.map { "\($0.label) \(Int($0.temp))°" }.joined(separator: ", "))
                    line("  días: " + w.days.map { "\($0.label) \(Int($0.min))/\(Int($0.max))° \($0.rain)%" }.joined(separator: ", "))
                } else { line("— Tiempo: NO se pudo descargar") }
            }
            var item = WidgetItem(kind: .news)
            item.newsCategories = ["tecnologia", "ciencia", "mundo-bbc", "xataka"]
            _ = DataHub.shared.news(for: item)
            var r = NewsResult()
            for _ in 0..<30 { r = DataHub.shared.news(for: item); if r.items.count > 10 { break }; try? await Task.sleep(nanoseconds: 500_000_000) }
            line("— Noticias: \(r.items.count) titulares")
            for n in r.items.prefix(6) { line("  [\(n.source)] \(n.title)\n     \(n.summary.prefix(110))") }
            sem.signal()
        }
        sem.wait()
    }

    /// Modo de pruebas: guarda en PNG cada widget (vertical y horizontal) con datos de ejemplo.
    private func snapshot(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        DataHub.shared.demoMode = true            // tiempo y noticias de ejemplo, sin red
        for kind in WidgetKind.allCases {
            for o in [ScreenOrientation.portrait, .landscape] {
                var item = WidgetItem(kind: kind)
                if kind == .weather || kind == .panel { item.weatherPlace = WeatherPlace(name: "Madrid", region: "Comunidad de Madrid · España", latitude: 40.4, longitude: -3.7) }
                if kind == .text { item.text = "Buenos días ☀️" }
                if kind == .photo { item.photoPath = ProcessInfo.processInfo.environment["SCREENDECK_DEMO_PHOTO"] }
                let (w, h) = o.pixelSize
                guard let cg = Renderer.image(item, snap: .demo, date: Date(), size: CGSize(width: w, height: h)) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/\(kind.rawValue)-\(o.isPortrait ? "v" : "h").png"))
            }
        }
        // Las tres distribuciones del Panel
        for layout in PanelLayout.allCases {
            for o in [ScreenOrientation.portrait, .landscape] {
                var item = WidgetItem(kind: .panel)
                item.weatherPlace = WeatherPlace(name: "Madrid", region: "", latitude: 40.4, longitude: -3.7)
                item.panelLayout = layout.rawValue
                if layout == .grid { item.panelTiles = ["clock", "weather", "cpu", "network"] }
                if layout == .rows { item.panelTiles = ["clock", "cpu", "network"] }
                if layout == .hero { item.panelTiles = ["clock", "memory", "battery"] }
                let (w, h) = o.pixelSize
                guard let cg = Renderer.image(item, snap: .demo, date: Date(), size: CGSize(width: w, height: h)) else { continue }
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/panel-\(layout.rawValue)-\(o.isPortrait ? "v" : "h").png"))
            }
        }
        // Prueba del pase de fotos: SCREENDECK_DEMO_FOLDER=/carpeta [SCREENDECK_DEMO_SHUFFLE=1]
        if let folder = ProcessInfo.processInfo.environment["SCREENDECK_DEMO_FOLDER"] {
            var item = WidgetItem(kind: .photo)
            item.photoUsesFolder = true; item.photoFolder = folder; item.photoSeconds = 10
            item.photoShuffle = ProcessInfo.processInfo.environment["SCREENDECK_DEMO_SHUFFLE"] == "1"
            let base = Date(timeIntervalSince1970: 1_800_000_000)
            for i in 0..<12 {
                let d = base.addingTimeInterval(Double(i * 10))
                let name = PhotoCache.path(for: item, date: d).map { ($0 as NSString).lastPathComponent } ?? "-"
                print("paso \(i): \(name)")
                if i < 4, let cg = Renderer.image(item, snap: .demo, date: d, size: CGSize(width: 320, height: 480)) {
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "\(dir)/carpeta-\(i).png"))
                }
            }
        }
        print("Capturas guardadas en \(dir)")
    }

    /// Modo de capturas: dibuja la interfaz real en una vista fuera de pantalla (no hace falta permiso de grabación)
    /// con la primera pantalla conectada en dos configuraciones. No guarda nada en la configuración del usuario.
    private func captureWindows(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        func save(_ name: String, height: CGFloat) {
            let size = NSSize(width: 1120, height: height)
            let host = NSHostingView(rootView: RootView().environmentObject(ScreenManager.shared).frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let off = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            off.contentView = host
            off.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            off.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))   // deja que se pinten las miniaturas
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                print("Captura \(name).png")
            }
            off.orderOut(nil)
        }

        /// Solo el panel de ajustes de un widget, a su tamaño (para las imágenes del README).
        func saveSettings(_ name: String, item: WidgetItem, width: CGFloat) {
            guard let c = ScreenManager.shared.screens.first else { return }
            let host = NSHostingView(rootView: WidgetSettings(c: c, item: item).environmentObject(ScreenManager.shared)
                .frame(width: width).padding(18).background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: width + 36, height: 3000)
            let off = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            off.contentView = host
            off.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            off.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            host.frame = NSRect(origin: .zero, size: NSSize(width: width + 36, height: host.fittingSize.height))
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                print("Captura \(name).png")
            }
            off.orderOut(nil)
        }

        func configure(_ step: Int) {
            guard let c = ScreenManager.shared.screens.first else { return }
            if step == 1 {
                c.config.orientation = .portrait
                var clock = WidgetItem(kind: .clock); clock.seconds = 15
                var net = WidgetItem(kind: .network); net.seconds = 5
                c.config.items = [clock, WidgetItem(kind: .system), net]
                c.editingKind = .system
            } else if step == 2 {
                c.config.orientation = .landscape
                var t = WidgetItem(kind: .text); t.text = "¡Buenos días!"
                c.config.items = [WidgetItem(kind: .calendar), t]
                c.editingKind = .text
            } else if step == 5 {
                c.config.orientation = .portrait
                var p = WidgetItem(kind: .panel)
                p.weatherPlace = WeatherPlace(name: "Sevilla", region: "Andalucía · España", latitude: 37.38283, longitude: -5.97317)
                p.panelLayout = "grid"; p.panelTiles = ["clock", "weather", "cpu", "network"]
                c.config.items = [p, WidgetItem(kind: .system)]
                c.editingKind = .panel
            } else {
                c.config.orientation = .portrait
                var w = WidgetItem(kind: .weather)
                w.weatherPlace = WeatherPlace(name: "Sevilla", region: "Andalucía · España", latitude: 37.38283, longitude: -5.97317)
                var n = WidgetItem(kind: .news); n.newsCategories = ["tecnologia", "ciencia", "mundo-bbc"]
                c.config.items = [w, n]
                c.editingKind = step == 3 ? .news : .weather
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            configure(1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                save("ventana-vertical", height: 1900)
                configure(2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    save("ventana-horizontal", height: 1900)
                    configure(3)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        save("ventana-noticias", height: 2000)
                        configure(4)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            save("ventana-tiempo", height: 2000)
                            configure(5)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { save("ventana-panel", height: 2000)
                                if let p = ScreenManager.shared.screens.first?.config.items.first(where: { $0.kind == .panel }) {
                                    saveSettings("ajustes-panel", item: p, width: 900)
                                }
                            }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 22) {
                    // Pantallas guardadas sin conectar: captura y prueba de «trasladar» y «olvidar» (en memoria)
                    let m = ScreenManager.shared
                    print("guardadas sin conectar: \(m.offline.map { "\($0.config.name) [\($0.key)]" })")
                    if let o = m.offline.first, let c = m.screens.first {
                        m.selection = o.key
                        save("ventana-sin-conectar", height: 900)
                        let antes = (c.config.name, c.key, m.offline.count)
                        m.adopt(o, into: c)
                        print("trasladar: \(antes.0) → ahora se llama \(c.config.name) en \(c.key); sin conectar \(antes.2) → \(m.offline.count); seleccion=\(m.selection ?? "-")")
                        if let o2 = m.offline.first {
                            m.forget(o2)
                            print("olvidar \(o2.config.name): sin conectar → \(m.offline.count)")
                        }
                    }
                    if let c = m.screens.first {
                        let orig = c.config.name
                        m.rename(c.key, to: "  Escritorio de Eric  ")
                        let r1 = c.config.name
                        m.rename(c.key, to: "   ")
                        let r2 = c.config.name
                        m.rename(c.key, to: String(repeating: "X", count: 60))
                        let r3 = c.config.name.count
                        m.rename("no-existe", to: "Nada")
                        m.rename(c.key, to: orig)
                        print("renombrar: «\(orig)» → «\(r1)» (recorta espacios) · vacío ignorado: \(r2 == r1) · 60 letras → \(r3) · clave inexistente: sin efecto")
                    }
                    // Orden de la lista: conectadas y sin conectar mezcladas
                    m.addDemoOffline([("2-9.9.9.1", "Salón"), ("2-9.9.9.2", "Cocina")])
                    @MainActor func names() -> String { m.entries.map { e -> String in
                        switch e { case .online(let c): return "●\(c.config.name)"; case .offline(let o): return "○\(o.config.name)" } }.joined(separator: "  ") }
                    line("orden inicial:           " + names())
                    if let first = m.entries.first?.id, let off = m.offline.first?.key {
                        m.move(off, onto: first)
                        line("sin conectar al 1.º:     " + names())
                        m.moveBy(first, 1)
                        line("mover 1.ª conectada ↓:   " + names())
                    }
                    save("ventana-orden", height: 900)
                    let ids = m.entries.map(\.id)
                    m.move(ids[ids.count - 1], onto: ids[0])
                    line("el último al primero:    " + names() + "   (límite: subir el 1.º \(m.canMove(m.entries[0].id, -1)), bajar el último \(m.canMove(m.entries.last!.id, 1)))")
                    if let o = m.offline.first(where: { $0.config.name == "Cocina" }), let c = m.screens.last {
                        m.adopt(o, into: c)
                        line("«Cocina» → \(c.config.name): " + names())
                    }
                    if let o = m.offline.first { m.forget(o); line("olvidar «\(o.config.name)»:     " + names()) }
                    line("claves en orden: \(m.order)")
                    NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
