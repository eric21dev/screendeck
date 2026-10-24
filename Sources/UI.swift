import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Raíz

struct RootView: View {
    @EnvironmentObject var manager: ScreenManager

    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: 236)
            Divider()
            Group {
                if let c = manager.screens.first(where: { $0.key == manager.selection }) {
                    ScreenDetail(c: c).id(c.key)
                } else {
                    EmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            Text(BuildInfo.current.label)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1).fixedSize()
                .foregroundStyle(.secondary.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Barra lateral

struct Sidebar: View {
    @EnvironmentObject var manager: ScreenManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display.2").font(.system(size: 18, weight: .semibold)).foregroundStyle(.tint)
                Text("ScreenDeck").font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .padding(.top, 46).padding(.horizontal, 20).padding(.bottom, 22)

            Text("PANTALLAS").font(.system(size: 11, weight: .semibold)).tracking(1.2)
                .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(manager.screens) { c in
                        SidebarRow(c: c, selected: manager.selection == c.key)
                            .onTapGesture { manager.selection = c.key }
                    }
                    if manager.screens.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Buscando pantallas…").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                if manager.screens.count > 1 {
                    HStack {
                        Button("Apagar todas") { manager.setAll(on: false) }
                        Button("Encender todas") { manager.setAll(on: true) }
                    }.controlSize(.small)
                }
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(.secondary)
                    .onChange(of: launchAtLogin) { on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

struct SidebarRow: View {
    @ObservedObject var c: ScreenController
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Thumb(c: c).frame(width: 34, height: c.config.orientation.isPortrait ? 50 : 24)
                .frame(width: 34, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.config.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch c.status {
        case .ready: return c.config.isOn ? .green : .gray
        case .connecting: return .orange
        case .error: return .red
        }
    }
    private var statusText: String {
        switch c.status {
        case .ready: return c.config.isOn ? (c.currentKind?.title ?? "Sin widgets") : "Apagada"
        case .connecting: return "Conectando…"
        case .error: return "Sin respuesta"
        }
    }
}

struct Thumb: View {
    @ObservedObject var c: ScreenController
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black)
            if let p = c.preview, c.config.isOn {
                Image(nsImage: p).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(1.5)
            }
        }
    }
}

// MARK: - Sin pantallas

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "display").font(.system(size: 54, weight: .light)).foregroundStyle(.secondary)
            Text("Conecta una pantalla").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("ScreenDeck reconoce solo las pantallas Turing de 3,5\" conectadas por USB. Puedes usar una o varias a la vez.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Buscando…").foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
        .padding(40)
    }
}

// MARK: - Detalle de una pantalla

struct ScreenDetail: View {
    @ObservedObject var c: ScreenController
    @EnvironmentObject var manager: ScreenManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                HStack(alignment: .top, spacing: 28) {
                    DevicePreview(c: c)
                    controls
                }
                gallery
                if let k = c.editingKind, let item = c.config.items.first(where: { $0.kind == k }) {
                    WidgetSettings(c: c, item: item)
                }
            }
            .padding(.top, 40).padding(.horizontal, 32).padding(.bottom, 40)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            TextField("Nombre", text: $c.config.name)
                .textFieldStyle(.plain).font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer()
            StatusPill(status: c.status)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlRow(title: "Pantalla") {
                Toggle("", isOn: $c.config.isOn).toggleStyle(.switch).labelsHidden()
            }
            Divider()
            ControlRow(title: "Brillo") {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(c.config.brightness) }, set: { c.config.brightness = Int($0) }), in: 5...100)
                        .frame(width: 170)
                    Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                }
            }
            Divider()
            ControlRow(title: "Orientación") {
                Picker("", selection: $c.config.orientation) {
                    ForEach(ScreenOrientation.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 170)
            }
            if c.config.items.count > 1 {
                Divider()
                ControlRow(title: "Cambiar cada") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { Double(c.config.rotationSeconds) }, set: { c.config.rotationSeconds = Int($0) }), in: 3...60, step: 1)
                            .frame(width: 130)
                        Text("\(c.config.rotationSeconds) s").monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                if manager.screens.count > 1 {
                    Button { manager.copySettings(from: c) } label: { Label("Copiar a las demás", systemImage: "square.on.square") }
                }
                Button { c.restart() } label: { Label("Reiniciar pantalla", systemImage: "arrow.clockwise") }
            }
            .controlSize(.small).padding(.top, 14)
            if case .error(let m) = c.status {
                Text(m).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 10).frame(maxWidth: 360, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Qué mostrar").font(.system(size: 20, weight: .bold, design: .rounded))
                Text(c.config.items.count > 1
                     ? "Se van alternando las \(c.config.items.count) pantallas marcadas."
                     : "Marca más de una y se irán alternando.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)], alignment: .leading, spacing: 18) {
                ForEach(WidgetKind.allCases) { k in
                    WidgetCard(c: c, kind: k, editing: c.editingKind == k)
                        .onTapGesture {
                            if !c.isUsing(k) { c.toggle(k) }
                            c.editingKind = (c.editingKind == k && c.isUsing(k)) ? nil : k
                        }
                }
            }
        }
    }
}

struct ControlRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 16)
            content
        }
        .frame(height: 46)
    }
}

struct StatusPill: View {
    let status: ScreenController.Status
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
    }
    private var color: Color {
        switch status { case .ready: return .green; case .connecting: return .orange; case .error: return .red }
    }
    private var text: String {
        switch status { case .ready: return "Conectada"; case .connecting: return "Conectando…"; case .error: return "Sin respuesta" }
    }
}

// MARK: - Vista previa del aparato

struct DevicePreview: View {
    @ObservedObject var c: ScreenController
    var body: some View {
        let portrait = c.config.orientation.isPortrait
        let w: CGFloat = portrait ? 196 : 318
        let h: CGFloat = portrait ? 294 : 212
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1)
            ZStack {
                if let p = c.preview {
                    Image(nsImage: p).resizable().aspectRatio(contentMode: .fit)
                }
                if !c.config.isOn {
                    ZStack {
                        Color.black
                        Image(systemName: "moon.zzz.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .padding(10)
        }
        .frame(width: w + 20, height: h + 20)
        .animation(.easeInOut(duration: 0.25), value: portrait)
    }
}

// MARK: - Galería

struct WidgetThumb: View {
    @ObservedObject private var stats = SystemStats.shared
    let item: WidgetItem
    let size: CGSize
    let width: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = width / size.width
            WidgetCanvas(item: item, snap: stats.snapshot, date: ctx.date, size: size)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: size.width * s, height: size.height * s, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct WidgetCard: View {
    @ObservedObject var c: ScreenController
    let kind: WidgetKind
    let editing: Bool

    var body: some View {
        let used = c.isUsing(kind)
        let item = c.config.items.first { $0.kind == kind } ?? WidgetItem(kind: kind)
        let size = c.config.orientation.isPortrait ? CGSize(width: 320, height: 480) : CGSize(width: 480, height: 320)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                WidgetThumb(item: item, size: size, width: 150)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(used ? 1 : 0.55)
                Button { c.toggle(kind) } label: {
                    Image(systemName: used ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22)).symbolRenderingMode(.palette)
                        .foregroundStyle(used ? Color.white : Color.white.opacity(0.9), used ? Color.accentColor : Color.black.opacity(0.55))
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain).padding(6)
                .help(used ? "Quitar de esta pantalla" : "Mostrar en esta pantalla")
            }
            HStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Text(kind.title).font(.system(size: 14, weight: .semibold))
            }
            Text(kind.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 30, alignment: .topLeading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(editing ? Color.accentColor : (used ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.07)),
                    lineWidth: editing ? 2.5 : 1.5))
        .contentShape(Rectangle())
    }
}

// MARK: - Ajustes del widget elegido

struct WidgetSettings: View {
    @ObservedObject var c: ScreenController
    let item: WidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: item.kind.symbol).foregroundStyle(.tint)
                Text("Ajustes de \(item.kind.title)").font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                if c.config.items.count > 1 {
                    Button("Mostrar solo este") { c.useOnly(item.kind) }.controlSize(.small)
                }
            }
            if item.kind == .text {
                TextField("Escribe tu mensaje", text: Binding(get: { item.text }, set: { v in c.update(.text) { $0.text = v } }), axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
            }
            if item.kind == .photo {
                HStack(spacing: 12) {
                    Button { pickPhoto() } label: { Label(item.photoPath == nil ? "Elegir foto…" : "Cambiar foto…", systemImage: "photo") }
                    if let p = item.photoPath {
                        Text(URL(fileURLWithPath: p).lastPathComponent).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if item.kind != .photo {
                HStack(spacing: 10) {
                    Text("Color").font(.system(size: 13, weight: .medium))
                    ForEach(accentChoices, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 3).padding(-4).opacity(item.accent == hex ? 1 : 0))
                            .onTapGesture { c.update(item.kind) { $0.accent = hex } }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }

    private func pickPhoto() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { c.update(.photo) { $0.photoPath = url.path } }
    }
}

// MARK: - Barra de menús

struct MenuContent: View {
    @EnvironmentObject var manager: ScreenManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if manager.screens.isEmpty {
            Text("Sin pantallas conectadas")
        } else {
            ForEach(manager.screens) { c in
                MenuScreenToggle(c: c)
            }
        }
        Divider()
        Button("Abrir ScreenDeck") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Salir") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct MenuScreenToggle: View {
    @ObservedObject var c: ScreenController
    var body: some View {
        Toggle(c.config.name, isOn: $c.config.isOn)
    }
}
