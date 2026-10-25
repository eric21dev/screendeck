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
                if kind == .weather { item.weatherPlace = WeatherPlace(name: "Madrid", region: "Comunidad de Madrid · España", latitude: 40.4, longitude: -3.7) }
                if kind == .text { item.text = "Buenos días ☀️" }
                if kind == .photo { item.photoPath = ProcessInfo.processInfo.environment["SCREENDECK_DEMO_PHOTO"] }
                let (w, h) = o.pixelSize
                guard let cg = Renderer.image(item, snap: .demo, date: Date(), size: CGSize(width: w, height: h)) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/\(kind.rawValue)-\(o.isPortrait ? "v" : "h").png"))
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

        func configure(_ step: Int) {
            guard let c = ScreenManager.shared.screens.first else { return }
            if step == 1 {
                c.config.orientation = .portrait
                c.config.items = [WidgetItem(kind: .clock), WidgetItem(kind: .system), WidgetItem(kind: .network)]
                c.editingKind = .system
            } else if step == 2 {
                c.config.orientation = .landscape
                var t = WidgetItem(kind: .text); t.text = "¡Buenos días!"
                c.config.items = [WidgetItem(kind: .calendar), t]
                c.editingKind = .text
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { save("ventana-tiempo", height: 2000) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
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
