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
                } else if let o = manager.offline.first(where: { $0.key == manager.selection }) {
                    OfflineDetail(o: o).id(o.key)
                } else {
                    EmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Renombrar pantalla", isPresented: Binding(get: { manager.renaming != nil }, set: { if !$0 { manager.renaming = nil } })) {
            TextField("Nombre", text: Binding(get: { manager.renaming?.draft ?? "" }, set: { manager.renaming?.draft = $0 }))
            Button("Guardar") { if let r = manager.renaming { manager.rename(r.key, to: r.draft) }; manager.renaming = nil }
            Button("Cancelar", role: .cancel) { manager.renaming = nil }
        } message: {
            Text("ID \(manager.renaming?.key ?? "")")
        }
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
    @State private var dropTarget: String?
    static let dragPrefix = "screendeck-pantalla:"

    @ViewBuilder private func rowMenu(_ e: ScreenEntry) -> some View {
        Button("Renombrar…") {
            switch e {
            case .online(let c): manager.beginRename(c.key, name: c.config.name)
            case .offline(let o): manager.beginRename(o.key, name: o.config.name)
            }
        }
        Divider()
        Button("Mover arriba") { manager.moveBy(e.id, -1) }.disabled(!manager.canMove(e.id, -1))
        Button("Mover abajo") { manager.moveBy(e.id, 1) }.disabled(!manager.canMove(e.id, 1))
    }

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
                    ForEach(manager.entries) { e in
                        Group {
                            switch e {
                            case .online(let c): SidebarRow(c: c, selected: manager.selection == c.key)
                            case .offline(let o): OfflineRow(o: o, selected: manager.selection == o.key)
                            }
                        }
                        .onTapGesture { manager.selection = e.id }
                        .contextMenu { rowMenu(e) }
                        // Arrastrar una fila sobre otra para cambiar el orden; se guarda y se mantiene aunque se desconecte
                        .draggable(Sidebar.dragPrefix + e.id)
                        .dropDestination(for: String.self) { items, _ in
                            dropTarget = nil
                            guard let s = items.first, s.hasPrefix(Sidebar.dragPrefix) else { return false }
                            manager.move(String(s.dropFirst(Sidebar.dragPrefix.count)), onto: e.id)
                            return true
                        } isTargeted: { over in
                            if over { dropTarget = e.id } else if dropTarget == e.id { dropTarget = nil }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2).opacity(dropTarget == e.id ? 1 : 0).allowsHitTesting(false))
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
                Toggle("Apagar al bloquear o suspender el Mac", isOn: $manager.sleepWithMac)
                    .toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(.secondary)
                    .help("Las pantallas se apagan cuando se bloquea la sesión, se apagan las pantallas del Mac o se suspende, y se encienden al volver.")
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
                IDBadge(key: c.key)
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

/// Nombre de la pantalla editable: se ve claramente que se puede cambiar (lápiz, fondo al pasar el ratón y borde al editar).
/// Se guarda al pulsar Intro o al salir del campo; si se deja vacío, vuelve al nombre anterior.
struct RenameField: View {
    let name: String
    let onCommit: (String) -> Void
    @State private var text = ""
    @State private var hover = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // El texto invisible fija el ancho: el campo se ajusta al nombre y el lápiz queda pegado a él
            Text(text.isEmpty ? "Nombre de la pantalla" : text)
                .font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).opacity(0).padding(.trailing, 8)
                .overlay(alignment: .leading) {
                    TextField("Nombre de la pantalla", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .focused($focused)
                        .onSubmit { commit() }
                }
            Image(systemName: focused ? "checkmark.circle.fill" : "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(focused || hover ? Color.accentColor : Color.secondary)
                .onTapGesture { if focused { commit(); focused = false } else { focused = true } }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(focused ? Color.primary.opacity(0.09) : (hover ? Color.primary.opacity(0.05) : .clear)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(focused ? Color.accentColor : .clear, lineWidth: 1.5))
        .frame(maxWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hover = $0 }
        .onAppear { text = name }
        .onChange(of: name) { n in if !focused { text = n } }
        .onChange(of: focused) { f in if !f { commit() } }
        .help("Haz clic para cambiar el nombre de la pantalla")
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { text = name; return }
        let n = String(t.prefix(40))
        text = n
        if n != name { onCommit(n) }
    }
}

/// Identificador de la pantalla: el puerto USB al que está conectada (bus y ruta de puertos).
/// Las pantallas no tienen un número de serie propio, así que ScreenDeck las reconoce por el puerto.
struct IDBadge: View {
    let key: String
    var body: some View {
        Text("ID \(key)")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .help("Puerto USB al que está conectada. Las pantallas no tienen número de serie propio, así que ScreenDeck las reconoce por el puerto.")
    }
}

struct OfflineRow: View {
    let o: OfflineScreen
    var selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08))
                Image(systemName: "display").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.config.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 7, height: 7)
                    Text("Sin conectar").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                IDBadge(key: o.key)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.16) : .clear))
        .contentShape(Rectangle())
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
                if c.config.items.count > 1 { RotationList(c: c) }
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
            VStack(alignment: .leading, spacing: 2) {
                RenameField(name: c.config.name) { c.config.name = $0 }
                Text("ID \(c.key)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    .help("Puerto USB al que está conectada. Las pantallas no tienen número de serie propio, así que ScreenDeck las reconoce por el puerto.")
            }
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
                ControlRow(title: "Cada widget dura") {
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

    /// Qué está pintando ahora la pantalla y, si rota, cuánto falta para el siguiente.
    @ViewBuilder private var liveLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if c.config.isOn, c.status == .ready, let k = c.currentKind {
                let left = c.slot(at: ctx.date)?.remaining ?? 0
                HStack(spacing: 7) {
                    LiveDot()
                    (Text("En pantalla ahora: ") + Text(k.title).bold().foregroundColor(.primary)
                        + Text(c.config.items.count > 1 ? " · cambia en \(left) s" : ""))
                        .font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.top, 2)
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Qué mostrar").font(.system(size: 20, weight: .bold, design: .rounded))
                Text(c.config.items.count > 1
                     ? "Se van alternando las \(c.config.items.count) pantallas marcadas."
                     : "Marca más de una y se irán alternando.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                liveLine
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
    /// Tarjetas sin usar: datos de ejemplo, sin descargar nada de internet.
    let demo: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = width / size.width
            WidgetCanvas(item: item, snap: stats.snapshot, date: ctx.date, size: size, demo: demo)
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
        let live = c.config.isOn && c.status == .ready && c.currentKind == kind
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    if live, let frame = c.preview {
                        // El fotograma exacto que se está enviando a la pantalla
                        Image(nsImage: frame).resizable().aspectRatio(contentMode: .fit).frame(width: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        WidgetThumb(item: item, size: size, width: 150, demo: !used)
                    }
                    if live { LiveBadge().padding(6).allowsHitTesting(false) }
                }
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
                Text(kind.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(kind.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 30, alignment: .topLeading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(editing ? Color.accentColor : (live ? Color(hex: "#2ED573") : (used ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.07))),
                    lineWidth: editing || live ? 2.5 : 1.5))
        .shadow(color: live ? Color(hex: "#2ED573").opacity(0.35) : .clear, radius: 10)
        .contentShape(Rectangle())
    }
}

/// Lista de los widgets en rotación: se ordena arrastrando y cada uno puede durar lo suyo.
struct RotationList: View {
    @ObservedObject var c: ScreenController
    @State private var dropTarget: WidgetKind?
    static let prefix = "screendeck-widget:"
    private let options = [3, 5, 8, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Orden y duración").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Arrastra para cambiar el orden. Cada widget puede durar lo suyo; si no, se usa el general (\(c.config.rotationSeconds) s).")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let slot = (c.config.isOn && c.status == .ready) ? c.slot(at: ctx.date) : nil
                VStack(spacing: 6) {
                    ForEach(Array(c.config.items.enumerated()), id: \.element.id) { i, it in
                        row(i, it, live: slot?.index == i ? slot : nil)
                    }
                }
            }
            .frame(maxWidth: 560)
        }
    }

    private func row(_ i: Int, _ it: WidgetItem, live: ScreenController.Slot?) -> some View {
        let green = Color(hex: "#2ED573")
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            Image(systemName: it.kind.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 20)
            Text(it.kind.title).font(.system(size: 14, weight: .semibold))
            if live != nil {
                LiveDot()
                Text("EN PANTALLA").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6).foregroundStyle(green)
            }
            Spacer(minLength: 6)
            Menu {
                Button("General (\(c.config.rotationSeconds) s)") { c.setSeconds(it.kind, nil) }
                Divider()
                ForEach(options, id: \.self) { s in Button("\(s) s") { c.setSeconds(it.kind, s) } }
            } label: {
                Text(it.seconds.map { "\($0) s" } ?? "General (\(c.config.rotationSeconds) s)")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button { c.moveItemBy(it.kind, -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).disabled(i == 0).foregroundStyle(i == 0 ? Color.secondary.opacity(0.3) : Color.secondary)
            Button { c.moveItemBy(it.kind, 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).disabled(i == c.config.items.count - 1)
                .foregroundStyle(i == c.config.items.count - 1 ? Color.secondary.opacity(0.3) : Color.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                    if let live {
                        // Lo que lleva de su turno
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(green.opacity(0.18))
                            .frame(width: g.size.width * CGFloat(live.elapsed + 1) / CGFloat(max(live.duration, 1)))
                    }
                }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(dropTarget == it.kind ? Color.accentColor : (live != nil ? green.opacity(0.8) : Color.primary.opacity(0.07)),
                    lineWidth: dropTarget == it.kind ? 2 : 1.2))
        .contentShape(Rectangle())
        .draggable(RotationList.prefix + it.kind.rawValue)
        .dropDestination(for: String.self) { items, _ in
            dropTarget = nil
            guard let s = items.first, s.hasPrefix(RotationList.prefix),
                  let dragged = WidgetKind(rawValue: String(s.dropFirst(RotationList.prefix.count))) else { return false }
            c.moveItem(dragged, onto: it.kind)
            return true
        } isTargeted: { over in
            if over { dropTarget = it.kind } else if dropTarget == it.kind { dropTarget = nil }
        }
    }
}

/// Dibujo esquemático de una distribución del Panel.
struct LayoutGlyph: View {
    let layout: PanelLayout
    let color: Color

    private func box(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ bh: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.85)).frame(width: bw, height: bh).position(x: x + bw / 2, y: y + bh / 2)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, gap: CGFloat = 4
            ZStack {
                switch layout {
                case .rows:
                    let bh = (h - 2 * gap) / 3
                    ForEach(0..<3, id: \.self) { i in box(0, CGFloat(i) * (bh + gap), w, bh) }
                case .grid:
                    let bw = (w - gap) / 2, bh = (h - gap) / 2
                    ForEach(0..<4, id: \.self) { i in box(CGFloat(i % 2) * (bw + gap), CGFloat(i / 2) * (bh + gap), bw, bh) }
                case .hero:
                    let top = h * 0.46, bw = (w - gap) / 2, bh = h - top - gap
                    box(0, 0, w, top)
                    box(0, top + gap, bw, bh)
                    box(bw + gap, top + gap, bw, bh)
                }
            }
        }
    }
}

/// Punto parpadeante que indica «en directo».
struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color(hex: "#FF4D4D")).frame(width: 8, height: 8).opacity(on ? 1 : 0.3)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// Etiqueta sobre la miniatura del widget que la pantalla está pintando ahora mismo.
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            LiveDot()
            Text("EN PANTALLA").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6).foregroundStyle(.white)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.72)))
    }
}

// MARK: - Ajustes del widget elegido

struct WidgetSettings: View {
    @ObservedObject var c: ScreenController
    let item: WidgetItem
    @State private var placeQuery = ""
    @State private var placeResults: [WeatherPlace] = []
    @State private var searching = false
    @State private var searched = false

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
            if item.kind == .photo { photoSettings }
            if item.kind == .weather { weatherSettings }
            if item.kind == .panel { panelSettings }
            if item.kind == .news { newsSettings }
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

    // MARK: panel

    private func tileBinding(_ i: Int) -> Binding<PanelTile> {
        Binding(get: { item.panelTileList()[i] },
                set: { v in
                    var list = item.panelTileList()
                    list[i] = v
                    c.update(.panel) { $0.panelTiles = list.map(\.rawValue) }
                })
    }

    @ViewBuilder private var panelSettings: some View {
        Text("Distribución").font(.system(size: 13, weight: .medium))
        HStack(spacing: 10) {
            ForEach(PanelLayout.allCases) { l in
                let on = item.layout == l
                Button { c.update(.panel) { $0.panelLayout = l.rawValue } } label: {
                    VStack(spacing: 6) {
                        LayoutGlyph(layout: l, color: on ? Color.accentColor : Color.secondary).frame(width: 46, height: 62)
                        Text(l.title).font(.system(size: 12, weight: .medium)).foregroundStyle(on ? Color.accentColor : Color.primary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        Text("Qué va en cada bloque").font(.system(size: 13, weight: .medium)).padding(.top, 4)
        ForEach(0..<item.layout.slots, id: \.self) { i in
            HStack(spacing: 12) {
                Text(item.layout == .hero && i == 0 ? "Bloque grande" : "Bloque \(i + 1)").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Picker("", selection: tileBinding(i)) {
                    ForEach(PanelTile.allCases) { t in Label(t.title, systemImage: t.symbol).tag(t) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 220)
            }
        }
        if item.panelTileList().contains(.weather) {
            Text("Ciudad del bloque Tiempo").font(.system(size: 13, weight: .medium)).padding(.top, 4)
            weatherSettings
        }
    }

    // MARK: tiempo

    @ViewBuilder private var weatherSettings: some View {
        HStack(spacing: 8) {
            TextField("Ciudad, por ejemplo Sevilla", text: $placeQuery)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 280).onSubmit { searchPlaces() }
            Button("Buscar") { searchPlaces() }.disabled(placeQuery.trimmingCharacters(in: .whitespaces).count < 2)
            if searching { ProgressView().controlSize(.small) }
        }
        if let p = item.weatherPlace {
            Label(p.region.isEmpty ? p.name : "\(p.name) · \(p.region)", systemImage: "mappin.circle.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
        } else {
            Text("Busca tu ciudad y elígela de la lista. No hace falta dar permiso de ubicación.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        if searched && placeResults.isEmpty && !searching {
            Text("No he encontrado ninguna ciudad con ese nombre.").font(.system(size: 12)).foregroundStyle(.orange)
        }
        ForEach(placeResults, id: \.self) { r in
            Button { choosePlace(r) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.system(size: 14, weight: .semibold))
                        if !r.region.isEmpty { Text(r.region).font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("Elegir").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: 420)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func searchPlaces() {
        let q = placeQuery
        searching = true; searched = false
        Task {
            let r = await DataHub.searchPlaces(q)
            await MainActor.run { placeResults = r; searching = false; searched = true }
        }
    }

    private func choosePlace(_ r: WeatherPlace) {
        c.update(item.kind) { $0.weatherPlace = r }
        placeResults = []; placeQuery = ""; searched = false
    }

    // MARK: noticias

    @ViewBuilder private var newsSettings: some View {
        Text("Categorías").font(.system(size: 13, weight: .medium))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(NewsCategory.all) { cat in
                let on = item.newsIDs.contains(cat.id)
                Button { toggleCategory(cat.id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: on ? "checkmark.circle.fill" : cat.symbol).frame(width: 16)
                        Text(cat.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        HStack(spacing: 10) {
            Text("Cambiar de noticia cada").font(.system(size: 13, weight: .medium))
            Slider(value: Binding(get: { Double(item.newsSlideSeconds) }, set: { v in c.update(.news) { $0.newsSeconds = Int(v) } }), in: 5...60, step: 1)
                .frame(width: 200)
            Text("\(item.newsSlideSeconds) s").monospacedDigit().foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
        }
        HStack(spacing: 10) {
            Text("Fuente propia (RSS)").font(.system(size: 13, weight: .medium))
            TextField("https://…/rss.xml", text: Binding(get: { item.newsCustomURL ?? "" }, set: { v in c.update(.news) { $0.newsCustomURL = v } }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 340)
        }
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            let r = DataHub.shared.news(for: item)
            HStack(spacing: 12) {
                Text(newsStatus(r, now: ctx.date)).font(.system(size: 12)).foregroundStyle(.secondary)
                Button { DataHub.shared.refreshNews(for: item) } label: { Label("Actualizar ahora", systemImage: "arrow.clockwise") }
                    .controlSize(.small)
            }
        }
        Text("Las noticias se descargan de los feeds RSS públicos de cada medio y se renuevan cada hora.")
            .font(.system(size: 11)).foregroundStyle(.tertiary)
    }

    private func newsStatus(_ r: NewsResult, now: Date) -> String {
        if r.noSources { return "Elige alguna categoría." }
        if r.items.isEmpty { return r.failed ? "No se pudieron descargar las noticias." : "Descargando noticias…" }
        var t = "\(r.items.count) noticias"
        if let u = r.updated {
            let m = max(0, Int(now.timeIntervalSince(u) / 60))
            t += m < 1 ? " · actualizadas ahora" : (m < 60 ? " · actualizadas hace \(m) min" : " · actualizadas hace \(m / 60) h")
        }
        return t
    }

    private func toggleCategory(_ id: String) {
        var ids = item.newsIDs
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        c.update(.news) { $0.newsCategories = ids }
    }

    // MARK: foto o carpeta de fotos

    @ViewBuilder private var photoSettings: some View {
        Picker("", selection: Binding(get: { item.usesFolder }, set: { v in c.update(.photo) { $0.photoUsesFolder = v } })) {
            Text("Una foto").tag(false)
            Text("Carpeta (pase de fotos)").tag(true)
        }
        .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 360)

        if item.usesFolder {
            HStack(spacing: 12) {
                Button { pickFolder() } label: { Label(item.photoFolder == nil ? "Elegir carpeta…" : "Cambiar carpeta…", systemImage: "folder") }
                if let f = item.photoFolder {
                    let n = PhotoCache.files(in: f).count
                    Text("\(URL(fileURLWithPath: f).lastPathComponent) · \(n) \(n == 1 ? "imagen" : "imágenes")")
                        .font(.system(size: 12)).foregroundStyle(n == 0 ? Color.orange : Color.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                Text("Cambiar de foto cada").font(.system(size: 13, weight: .medium))
                Slider(value: Binding(get: { Double(item.slideSeconds) }, set: { v in c.update(.photo) { $0.photoSeconds = Int(v) } }), in: 3...120, step: 1)
                    .frame(width: 200)
                Text("\(item.slideSeconds) s").monospacedDigit().foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
            }
            Toggle("Orden aleatorio", isOn: Binding(get: { item.shuffle }, set: { v in c.update(.photo) { $0.photoShuffle = v } }))
                .toggleStyle(.switch).font(.system(size: 13))
        } else {
            HStack(spacing: 12) {
                Button { pickPhoto() } label: { Label(item.photoPath == nil ? "Elegir foto…" : "Cambiar foto…", systemImage: "photo") }
                if let p = item.photoPath {
                    Text(URL(fileURLWithPath: p).lastPathComponent).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        Toggle("Rellenar toda la pantalla (recorta los bordes)", isOn: Binding(get: { !item.fitInside }, set: { v in c.update(.photo) { $0.photoFit = !v } }))
            .toggleStyle(.switch).font(.system(size: 13))
    }

    private func pickPhoto() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { c.update(.photo) { $0.photoPath = url.path } }
    }

    private func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Elegir carpeta"
        p.message = "Elige la carpeta con las fotos que quieres ir mostrando"
        if p.runModal() == .OK, let url = p.url { c.update(.photo) { $0.photoFolder = url.path; $0.photoUsesFolder = true } }
    }
}

// MARK: - Pantalla guardada sin conectar

struct OfflineDetail: View {
    let o: OfflineScreen
    @EnvironmentObject var manager: ScreenManager
    @State private var confirmForget = false

    private var widgetsText: String { o.config.items.map { $0.kind.title }.joined(separator: ", ") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        RenameField(name: o.config.name) { manager.rename(o.key, to: $0) }
                        Text("ID \(o.key)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(Color.gray).frame(width: 8, height: 8)
                        Text("Sin conectar").font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(Color.gray.opacity(0.18)))
                }

                Text("Ahora mismo no hay ninguna pantalla en ese puerto USB, pero ScreenDeck guarda su configuración. Si has movido la pantalla a otro puerto, traslada aquí abajo su configuración a la que corresponda.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).frame(maxWidth: 620, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    ControlRow(title: "Pantalla") { Text(o.config.isOn ? "Encendida" : "Apagada").foregroundStyle(.secondary) }
                    Divider()
                    ControlRow(title: "Brillo") { Text("\(o.config.brightness) %").monospacedDigit().foregroundStyle(.secondary) }
                    Divider()
                    ControlRow(title: "Orientación") { Text(o.config.orientation.title).foregroundStyle(.secondary) }
                    Divider()
                    ControlRow(title: o.config.items.count > 1 ? "Widgets (cada \(o.config.rotationSeconds) s)" : "Widget") {
                        Text(widgetsText).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
                .padding(18).frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.07)))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Usar esta configuración en…").font(.system(size: 20, weight: .bold, design: .rounded))
                    if manager.screens.isEmpty {
                        Text("Conecta una pantalla y aparecerá aquí para poder trasladarle esta configuración.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(manager.screens) { c in AdoptRow(c: c) { manager.adopt(o, into: c) } }
                        }
                        .frame(maxWidth: 520)
                        Text("Se traslada el nombre, el brillo, la orientación y los widgets, y se sustituye lo que tuviera esa pantalla. Esta entrada guardada desaparece.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
                    }
                }

                Button(role: .destructive) { confirmForget = true } label: { Label("Olvidar esta pantalla", systemImage: "trash") }
                    .controlSize(.small)
            }
            .padding(.top, 40).padding(.horizontal, 32).padding(.bottom, 40)
        }
        .confirmationDialog("¿Olvidar \(o.config.name)?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Olvidar", role: .destructive) { manager.forget(o) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra su configuración guardada. Si vuelves a conectar una pantalla en ese puerto, empezará con la configuración por defecto.")
        }
    }
}

struct AdoptRow: View {
    @ObservedObject var c: ScreenController
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Thumb(c: c).frame(width: 30, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.config.name).font(.system(size: 14, weight: .semibold))
                    IDBadge(key: c.key)
                }
                Spacer()
                Text("Usar aquí").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        Toggle("\(c.config.name) · \(c.key)", isOn: $c.config.isOn)
    }
}
