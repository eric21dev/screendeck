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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(into: args[i + 1])
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            Store.disabled = true          // no se toca la configuración guardada
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

    /// Modo de pruebas: guarda en PNG cada widget (vertical y horizontal) con datos de ejemplo.
    private func snapshot(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for kind in WidgetKind.allCases {
            for o in [ScreenOrientation.portrait, .landscape] {
                var item = WidgetItem(kind: kind)
                if kind == .text { item.text = "Buenos días ☀️" }
                if kind == .photo { item.photoPath = ProcessInfo.processInfo.environment["SCREENDECK_DEMO_PHOTO"] }
                let (w, h) = o.pixelSize
                guard let cg = Renderer.image(item, snap: .demo, date: Date(), size: CGSize(width: w, height: h)) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/\(kind.rawValue)-\(o.isPortrait ? "v" : "h").png"))
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
            } else {
                c.config.orientation = .landscape
                var t = WidgetItem(kind: .text); t.text = "¡Buenos días!"
                c.config.items = [WidgetItem(kind: .calendar), t]
                c.editingKind = .text
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            configure(1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                save("ventana-vertical", height: 1500)
                configure(2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    save("ventana-horizontal", height: 1400)
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
