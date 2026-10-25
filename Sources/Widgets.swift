import SwiftUI
import AppKit

// Cada widget es una vista pura de (datos, fecha, tamaño): sirve igual para la pantalla, la vista previa y la galería.

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
}

let accentChoices = ["#34C8FF", "#7C5CFF", "#FF5C8A", "#FF9F43", "#2ED573", "#FFD93D", "#FFFFFF", "#FF4D4D"]

private var formatters: [String: DateFormatter] = [:]
func fmt(_ date: Date, _ pattern: String) -> String {
    let f = formatters[pattern] ?? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = pattern
        formatters[pattern] = f
        return f
    }()
    return f.string(from: date)
}

func num(_ v: Double, _ decimals: Int = 0) -> String {
    String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
}

func speed(_ bytesPerSecond: Double) -> (String, String) {
    let kb = bytesPerSecond / 1000
    if kb < 1000 { return (num(kb, kb < 10 ? 1 : 0), "KB/s") }
    let mb = kb / 1000
    return (num(mb, mb < 100 ? 1 : 0), "MB/s")
}

func uptimeText(_ t: TimeInterval) -> String {
    let d = Int(t) / 86400, h = (Int(t) % 86400) / 3600, m = (Int(t) % 3600) / 60
    if d > 0 { return "\(d) d \(h) h" }
    if h > 0 { return "\(h) h \(m) min" }
    return "\(m) min"
}

// MARK: - Piezas

struct Ring: View {
    var progress: Double
    var color: Color
    var line: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: max(0.003, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    var body: some View {
        GeometryReader { g in
            let maxV = max(values.max() ?? 1, 0.0001)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: g.size.height * (1 - CGFloat(v / maxV) * 0.92) - 1)
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                    p.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct Header: View {
    var symbol: String
    var title: String
    var color: Color
    var date: Date
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).tracking(2)
            Spacer()
            Text(fmt(date, "HH:mm")).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
        }
        .foregroundStyle(color)
    }
}

// MARK: - Contenedor

struct WidgetCanvas: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize
    /// Datos de ejemplo cuando el widget todavía no está configurado (galería y capturas).
    var demo = false

    var body: some View {
        ZStack {
            if item.kind != .photo { background }
            content
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var background: some View {
        let acc = Color(hex: item.accent)
        return ZStack {
            LinearGradient(colors: [Color(hex: "#0E1424"), Color(hex: "#05070D")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [acc.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .clock: ClockWidget(item: item, date: date)
        case .system: SystemWidget(item: item, snap: snap, date: date, size: size)
        case .network: NetworkWidget(item: item, snap: snap, date: date, size: size)
        case .battery: BatteryWidget(item: item, snap: snap, date: date, size: size)
        case .calendar: CalendarWidget(item: item, date: date, size: size)
        case .text: TextWidget(item: item)
        case .photo: PhotoWidget(item: item, date: date, size: size)
        case .weather: WeatherWidget(item: item, date: date, size: size, demo: demo)
        case .disks: DisksWidget(item: item, snap: snap, date: date, size: size)
        case .processes: ProcessesWidget(item: item, snap: snap, date: date, size: size)
        case .thermal: ThermalWidget(item: item, snap: snap, date: date, size: size)
        case .news: NewsWidget(item: item, date: date, size: size, demo: demo)
        }
    }
}

// MARK: - Reloj

struct ClockWidget: View {
    let item: WidgetItem
    let date: Date
    var body: some View {
        let acc = Color(hex: item.accent)
        let sec = Double(Calendar.current.component(.second, from: date))
        ZStack {
            Ring(progress: sec / 60, color: acc, line: 9).frame(width: 282, height: 282)
            VStack(spacing: 4) {
                Text(fmt(date, "HH:mm"))
                    .font(.system(size: 76, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Text(fmt(date, "EEEE").capitalized)
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(acc)
                Text(fmt(date, "d 'de' MMMM"))
                    .font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Sistema

struct SystemWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    private struct Metric { var title, big, sub, ring: String; var value: Double; var color: Color; var history: [Double]? }

    private var metrics: [Metric] {
        [
            Metric(title: "Procesador", big: "\(Int(snap.cpu * 100))%", sub: "en uso", ring: "CPU", value: snap.cpu,
                   color: Color(hex: item.accent), history: nil),
            Metric(title: "Memoria", big: "\(num(snap.memUsedGB, 1)) GB", sub: "de \(Int(snap.memTotalGB.rounded())) GB", ring: "RAM",
                   value: snap.memUsed, color: Color(hex: "#FF9F43"), history: nil),
            Metric(title: "Disco", big: "\(Int(snap.diskFreeGB)) GB", sub: "libres de \(Int(snap.diskTotalGB)) GB", ring: "SSD",
                   value: snap.diskUsed, color: Color(hex: "#2ED573"), history: nil),
        ]
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        if size.height >= size.width {
            VStack(spacing: 0) {
                Header(symbol: "cpu", title: "SISTEMA", color: acc, date: date)
                Spacer(minLength: 8)
                VStack(spacing: 14) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 16) {
                            ZStack {
                                Ring(progress: m.value, color: m.color, line: 10).frame(width: 96, height: 96)
                                Text(m.ring).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                                Text(m.big).font(.system(size: 31, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text(m.sub).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                            if let h = m.history { Sparkline(values: h, color: m.color).frame(width: 64, height: 44) }
                        }
                        .padding(.horizontal, 14).frame(height: 116)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(22)
        } else {
            VStack(spacing: 0) {
                Header(symbol: "cpu", title: "SISTEMA", color: acc, date: date)
                Spacer(minLength: 6)
                HStack(spacing: 14) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                        VStack(spacing: 8) {
                            ZStack {
                                Ring(progress: m.value, color: m.color, line: 11).frame(width: 118, height: 118)
                                Text("\(Int(m.value * 100))%").font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            }
                            Text(m.title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                            Text(m.big).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.06)))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

// MARK: - Red

struct NetworkWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    private func panel(_ title: String, symbol: String, value: Double, history: [Double], color: Color) -> some View {
        let (v, unit) = speed(value)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(v).font(.system(size: 50, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Text(unit).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
            .minimumScaleFactor(0.6).lineLimit(1)
            Sparkline(values: history, color: color).frame(maxWidth: .infinity, minHeight: 62, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        let down = panel("Bajada", symbol: "arrow.down.circle.fill", value: snap.netDown, history: snap.netDownHistory, color: acc)
        let up = panel("Subida", symbol: "arrow.up.circle.fill", value: snap.netUp, history: snap.netUpHistory, color: Color(hex: "#FF9F43"))
        VStack(spacing: 14) {
            Header(symbol: "network", title: "RED", color: acc, date: date)
            if size.height >= size.width {
                down; up
            } else {
                HStack(spacing: 14) { down; up }
            }
        }
        .padding(22)
    }
}

// MARK: - Energía

struct BatteryWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    private func levelColor(_ d: BatteryDevice, _ acc: Color) -> Color {
        if d.charging { return Color(hex: "#2ED573") }
        return d.percent <= 20 ? Color(hex: "#FF4D4D") : (d.percent <= 40 ? Color(hex: "#FF9F43") : acc)
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        let devices = snap.batteries
        let portrait = size.height >= size.width
        VStack(spacing: 0) {
            Header(symbol: "bolt.fill", title: devices.count > 1 ? "BATERÍAS" : "ENERGÍA", color: acc, date: date)
            if devices.isEmpty {
                Spacer()
                Image(systemName: "powerplug.fill").font(.system(size: 84)).foregroundStyle(acc)
                Text("Conectado a la corriente").font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).padding(.top, 16)
                Spacer()
            } else if devices.count == 1 {
                single(devices[0], acc)
            } else {
                list(devices, acc, portrait: portrait)
            }
            Text("Encendido hace \(uptimeText(snap.uptime))")
                .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8)
        }
        .padding(portrait ? 22 : 18)
    }

    /// Un solo dispositivo: la vista grande de siempre.
    @ViewBuilder private func single(_ d: BatteryDevice, _ acc: Color) -> some View {
        let color = levelColor(d, acc)
        let level = Double(d.percent) / 100
        Spacer()
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 5)
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(color)
                    .frame(width: max(14, 214 * level), height: 78).padding(.leading, 7)
            }
            .frame(width: 228, height: 92)
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: 7, height: 34)
        }
        Text("\(d.percent)%").font(.system(size: 70, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).padding(.top, 14)
        Text(d.charging ? "Cargando" : d.name).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(color)
        Spacer()
    }

    @ViewBuilder private func list(_ all: [BatteryDevice], _ acc: Color, portrait: Bool) -> some View {
        let maxRows = portrait ? 6 : 6
        let shown = Array(all.prefix(maxRows))
        VStack(spacing: 8) {
            if portrait {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, d in row(d, acc, compact: false) }
            } else {
                let half = (shown.count + 1) / 2
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 8) { ForEach(Array(shown.prefix(half).enumerated()), id: \.offset) { _, d in row(d, acc, compact: true) } }
                    VStack(spacing: 8) { ForEach(Array(shown.dropFirst(half).enumerated()), id: \.offset) { _, d in row(d, acc, compact: true) } }
                }
            }
            if all.count > maxRows {
                Text("+ \(all.count - maxRows) más").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.top, 10)
        Spacer(minLength: 0)
    }

    private func row(_ d: BatteryDevice, _ acc: Color, compact: Bool) -> some View {
        let c = levelColor(d, acc)
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: d.symbol).font(.system(size: compact ? 15 : 18)).foregroundStyle(acc).frame(width: compact ? 20 : 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).font(.system(size: compact ? 13.5 : 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    if d.charging || d.detail != nil || d.percent <= 20 {
                        Text(d.charging ? "Cargando" : (d.detail ?? "Batería baja"))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(d.charging ? c : .white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 4)
                if d.charging { Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(c) }
                Text("\(d.percent)%").font(.system(size: compact ? 16 : 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(c).frame(width: max(5, g.size.width * Double(d.percent) / 100))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }
}

// MARK: - Calendario

struct CalendarWidget: View {
    let item: WidgetItem
    let date: Date
    let size: CGSize

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_ES")
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        let cal = calendar
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let days = cal.range(of: .day, in: .month, for: monthStart)!.count
        let offset = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let today = cal.component(.day, from: date)
        let cell = min((size.width - 44) / 7, (size.height - 112) / 6.4)
        VStack(spacing: 8) {
            HStack {
                Text(fmt(date, "LLLL yyyy").capitalized).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 0) {
                ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { i, d in
                    Text(d).font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(i >= 5 ? acc : .white.opacity(0.45)).frame(width: cell)
                }
            }
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let n = row * 7 + col - offset + 1
                            ZStack {
                                if n == today { Circle().fill(acc).frame(width: cell - 4, height: cell - 4) }
                                if n >= 1 && n <= days {
                                    Text("\(n)").font(.system(size: 17, weight: n == today ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(n == today ? Color.black : .white.opacity(col >= 5 ? 0.95 : 0.8))
                                }
                            }.frame(width: cell, height: cell)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }
}

// MARK: - Mensaje

struct TextWidget: View {
    let item: WidgetItem
    var body: some View {
        let acc = Color(hex: item.accent)
        Text(item.text.isEmpty ? "Escribe un mensaje" : item.text)
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.25)
            .lineLimit(6)
            .foregroundStyle(LinearGradient(colors: [acc, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
            .padding(28)
    }
}

// MARK: - Foto

struct PhotoWidget: View {
    let item: WidgetItem
    let date: Date
    let size: CGSize

    private var emptyMessage: (symbol: String, text: String) {
        if !item.usesFolder { return ("photo.on.rectangle.angled", "Elige una foto") }
        guard let f = item.photoFolder else { return ("folder", "Elige una carpeta") }
        return PhotoCache.files(in: f).isEmpty ? ("photo.badge.exclamationmark", "No hay imágenes en la carpeta") : ("photo.badge.exclamationmark", "No se pueden leer las imágenes")
    }

    var body: some View {
        if let img = PhotoCache.current(for: item, date: date) {
            if item.fitInside {
                ZStack {
                    Color.black
                    Image(nsImage: img).resizable().scaledToFit()
                }
                .frame(width: size.width, height: size.height).clipped()
            } else {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            }
        } else {
            let m = emptyMessage
            ZStack {
                Color(hex: "#0E1424")
                VStack(spacing: 12) {
                    Image(systemName: m.symbol).font(.system(size: 56)).foregroundStyle(Color(hex: item.accent))
                    Text(m.text).font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
        }
    }
}

/// Carga de fotos y recorrido de carpetas. Las imágenes se reducen al abrirlas (basta 960 px para una pantalla de 480)
/// y solo se guardan unas pocas en memoria, así que una carpeta de fotos de 12 megapíxeles no pesa.
enum PhotoCache {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
    private static var images: [String: NSImage] = [:]
    private static var recent: [String] = []
    private static var broken: Set<String> = []
    private static var listings: [String: (at: Date, files: [String])] = [:]

    /// Imágenes de la carpeta, ordenadas por nombre. Se vuelve a leer cada 30 s, así que las nuevas aparecen solas.
    static func files(in folder: String) -> [String] {
        if let l = listings[folder], Date().timeIntervalSince(l.at) < 30 { return l.files.filter { !broken.contains($0) } }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let files = names
            .filter { !$0.hasPrefix(".") && extensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { (folder as NSString).appendingPathComponent($0) }
        listings[folder] = (Date(), files)
        return files.filter { !broken.contains($0) }
    }

    static func image(_ path: String) -> NSImage? {
        if let i = images[path] { return i }
        if broken.contains(path) { return nil }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { broken.insert(path); return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,      // respeta la orientación de la foto
            kCGImageSourceThumbnailMaxPixelSize: 960,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { broken.insert(path); return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images[path] = img
        recent.append(path)
        if recent.count > 8 { images[recent.removeFirst()] = nil }
        return img
    }

    /// Ruta de la imagen que toca en `date`. Depende solo de la hora, así que todas las pantallas con la misma carpeta
    /// y el mismo intervalo van a la par, y no hace falta guardar ningún estado.
    static func path(for item: WidgetItem, date: Date, skipping extra: Int = 0) -> String? {
        guard item.usesFolder else { return item.photoPath }
        guard let folder = item.photoFolder else { return nil }
        let files = files(in: folder)
        guard !files.isEmpty else { return nil }
        let step = Int(date.timeIntervalSince1970) / item.slideSeconds + extra
        let n = files.count
        if !item.shuffle { return files[step % n] }
        // Orden aleatorio: una mezcla distinta en cada vuelta completa, estable durante la vuelta
        return files[permutation(n, seed: stableHash(folder) &+ UInt64(step / n))[step % n]]
    }

    /// La imagen que toca; si una está dañada, pasa a la siguiente.
    static func current(for item: WidgetItem, date: Date) -> NSImage? {
        let tries = item.usesFolder ? min(8, max(1, item.photoFolder.map { files(in: $0).count } ?? 1)) : 1
        for extra in 0..<tries {
            if let p = path(for: item, date: date, skipping: extra), let i = image(p) { return i }
        }
        return nil
    }

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    private static func permutation(_ n: Int, seed: UInt64) -> [Int] {
        var state = seed
        func next() -> UInt64 {                       // SplitMix64
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var a = Array(0..<n)
        if n > 1 { for i in stride(from: n - 1, to: 0, by: -1) { a.swapAt(i, Int(next() % UInt64(i + 1))) } }
        return a
    }
}
