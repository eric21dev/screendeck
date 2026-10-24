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
private func fmt(_ date: Date, _ pattern: String) -> String {
    let f = formatters[pattern] ?? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = pattern
        formatters[pattern] = f
        return f
    }()
    return f.string(from: date)
}

private func num(_ v: Double, _ decimals: Int = 0) -> String {
    String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
}

private func speed(_ bytesPerSecond: Double) -> (String, String) {
    let kb = bytesPerSecond / 1000
    if kb < 1000 { return (num(kb, kb < 10 ? 1 : 0), "KB/s") }
    let mb = kb / 1000
    return (num(mb, mb < 100 ? 1 : 0), "MB/s")
}

private func uptimeText(_ t: TimeInterval) -> String {
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

private struct Header: View {
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
        case .battery: BatteryWidget(item: item, snap: snap, date: date)
        case .calendar: CalendarWidget(item: item, date: date, size: size)
        case .text: TextWidget(item: item)
        case .photo: PhotoWidget(item: item, size: size)
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
    var body: some View {
        let acc = Color(hex: item.accent)
        VStack(spacing: 0) {
            Header(symbol: "bolt.fill", title: "ENERGÍA", color: acc, date: date)
            Spacer()
            if let p = snap.batteryPercent {
                let level = Double(p) / 100
                let color: Color = p <= 20 && !snap.batteryCharging ? Color(hex: "#FF4D4D") : acc
                HStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 5)
                        RoundedRectangle(cornerRadius: 15, style: .continuous).fill(color)
                            .frame(width: max(14, 214 * level), height: 78).padding(.leading, 7)
                    }
                    .frame(width: 228, height: 92)
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: 7, height: 34)
                }
                Text("\(p)%").font(.system(size: 70, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).padding(.top, 14)
                Text(snap.batteryCharging ? "Cargando" : (snap.onACPower ? "Cargada" : "Con batería"))
                    .font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(color)
            } else {
                Image(systemName: "powerplug.fill").font(.system(size: 84)).foregroundStyle(acc)
                Text("Conectado a la corriente").font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).padding(.top, 16)
            }
            Spacer()
            Text("Encendido hace \(uptimeText(snap.uptime))")
                .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(22)
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
    let size: CGSize
    var body: some View {
        if let path = item.photoPath, let img = PhotoCache.image(path) {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        } else {
            ZStack {
                Color(hex: "#0E1424")
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 56)).foregroundStyle(Color(hex: item.accent))
                    Text("Elige una foto").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

enum PhotoCache {
    private static var cache: [String: NSImage] = [:]
    static func image(_ path: String) -> NSImage? {
        if let i = cache[path] { return i }
        guard let i = NSImage(contentsOfFile: path) else { return nil }
        cache[path] = i
        return i
    }
}
