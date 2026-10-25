import SwiftUI

// Widget Panel: varias secciones pequeñas en una sola pantalla, para ver de un vistazo hora, tiempo y estado del Mac.

enum PanelLayout: String, CaseIterable, Identifiable {
    case rows, grid, hero
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rows: return "3 bloques"
        case .grid: return "4 bloques"
        case .hero: return "1 grande + 2"
        }
    }
    var slots: Int { self == .grid ? 4 : 3 }
}

enum PanelTile: String, CaseIterable, Identifiable {
    case clock, weather, cpu, memory, disk, network, battery, gpu, temperature
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clock: return "Reloj"
        case .weather: return "Tiempo"
        case .cpu: return "CPU"
        case .memory: return "Memoria"
        case .disk: return "Disco"
        case .network: return "Red"
        case .battery: return "Batería"
        case .gpu: return "GPU"
        case .temperature: return "Temperatura"
        }
    }
    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .cpu: return "cpu.fill"
        case .memory: return "memorychip.fill"
        case .disk: return "internaldrive.fill"
        case .network: return "network"
        case .battery: return "battery.75percent"
        case .gpu: return "display"
        case .temperature: return "thermometer.medium"
        }
    }
}

extension WidgetItem {
    var layout: PanelLayout { PanelLayout(rawValue: panelLayout ?? "") ?? .hero }

    /// Contenido de cada bloque. Si falta alguno se completa con bloques distintos.
    func panelTileList() -> [PanelTile] {
        let n = layout.slots
        var out = Array((panelTiles ?? []).compactMap(PanelTile.init(rawValue:)).prefix(n))
        for d in [PanelTile.clock, .cpu, .network, .weather, .memory, .disk, .battery] where out.count < n && !out.contains(d) { out.append(d) }
        while out.count < n { out.append(.cpu) }
        return out
    }
}

struct PanelWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize
    let demo: Bool

    private func cell(_ t: PanelTile, _ s: CGSize) -> some View {
        PanelTileView(tile: t, item: item, snap: snap, date: date, size: s, demo: demo).frame(width: s.width, height: s.height)
    }

    var body: some View {
        let t = item.panelTileList()
        let portrait = size.height >= size.width
        let pad: CGFloat = 14, gap: CGFloat = 10
        let w = size.width - 2 * pad, h = size.height - 2 * pad
        Group {
            switch item.layout {
            case .rows:
                if portrait {
                    VStack(spacing: gap) { ForEach(0..<3, id: \.self) { cell(t[$0], CGSize(width: w, height: (h - 2 * gap) / 3)) } }
                } else {
                    HStack(spacing: gap) { ForEach(0..<3, id: \.self) { cell(t[$0], CGSize(width: (w - 2 * gap) / 3, height: h)) } }
                }
            case .grid:
                let s = CGSize(width: (w - gap) / 2, height: (h - gap) / 2)
                VStack(spacing: gap) {
                    HStack(spacing: gap) { cell(t[0], s); cell(t[1], s) }
                    HStack(spacing: gap) { cell(t[2], s); cell(t[3], s) }
                }
            case .hero:
                if portrait {
                    let top = h * 0.44, bottom = h - top - gap, half = (w - gap) / 2
                    VStack(spacing: gap) {
                        cell(t[0], CGSize(width: w, height: top))
                        HStack(spacing: gap) { cell(t[1], CGSize(width: half, height: bottom)); cell(t[2], CGSize(width: half, height: bottom)) }
                    }
                } else {
                    let left = w * 0.5, right = w - left - gap, half = (h - gap) / 2
                    HStack(spacing: gap) {
                        cell(t[0], CGSize(width: left, height: h))
                        VStack(spacing: gap) { cell(t[1], CGSize(width: right, height: half)); cell(t[2], CGSize(width: right, height: half)) }
                    }
                }
            }
        }
        .padding(pad)
    }
}

struct PanelTileView: View {
    let tile: PanelTile
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize
    let demo: Bool

    private var acc: Color { Color(hex: item.accent) }
    private var wide: Bool { size.width > size.height * 1.25 }
    /// Bloques muy apaisados: solo ahí el indicador va a la izquierda del texto.
    private var clockWide: Bool { size.width > size.height * 1.6 }
    private var veryWide: Bool { size.width > size.height * 1.75 }
    private var u: CGFloat { min(size.width, size.height) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.07))
            content.padding(max(8, u * 0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch tile {
        case .clock: clock
        case .weather: weather
        case .cpu: gauge("CPU", value: snap.cpu, text: "\(Int(snap.cpu * 100))%", sub: "en uso", color: acc, history: snap.cpuHistory)
        case .memory: gauge("Memoria", value: snap.memUsed, text: "\(Int(snap.memUsed * 100))%", sub: "\(num(snap.memUsedGB, 1)) de \(Int(snap.memTotalGB.rounded())) GB", color: Color(hex: "#FF9F43"))
        case .disk: gauge("Disco", value: snap.diskUsed, text: "\(Int(snap.diskUsed * 100))%", sub: "\(Int(snap.diskFreeGB)) GB libres", color: Color(hex: "#2ED573"))
        case .gpu: gauge("GPU", value: snap.gpu ?? 0, text: snap.gpu.map { "\(Int($0 * 100))%" } ?? "—", sub: snap.gpu == nil ? "sin datos" : "en uso", color: Color(hex: "#FF7A59"), history: snap.gpuHistory)
        case .network: network
        case .battery: battery
        case .temperature: temperature
        }
    }

    // MARK: bloques

    private var clock: some View {
        let avail = size.width - 2 * max(8, u * 0.08) - 150          // sitio que queda para la hora junto al día y la fecha
        let f = clockWide ? min(size.height * 0.46, max(24, avail / 2.95)) : min(size.width * 0.27, size.height * 0.3)
        return Group {
            if clockWide {
                HStack(spacing: 14) {
                    Text(fmt(date, "HH:mm")).font(.system(size: f, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fmt(date, "EEEE").capitalized).font(.system(size: max(13, f * 0.3), weight: .semibold, design: .rounded)).foregroundStyle(acc)
                        Text(fmt(date, "d 'de' MMMM")).font(.system(size: max(11, f * 0.23), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 3) {
                    Text(fmt(date, "HH:mm")).font(.system(size: f, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(fmt(date, "EEEE").capitalized).font(.system(size: max(12, f * 0.36), weight: .semibold, design: .rounded)).foregroundStyle(acc)
                    Text(fmt(date, "d MMM")).font(.system(size: max(11, f * 0.3), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var weather: some View {
        let place = demo ? WeatherPlace(name: "Madrid", region: "", latitude: 0, longitude: 0) : item.weatherPlace
        let data = demo ? WeatherData.demo : item.weatherPlace.flatMap { DataHub.shared.weather(for: $0) }
        return Group {
            if let place, let w = data {
                let icon = Image(systemName: WeatherCode.symbol(w.code, day: w.isDay)).symbolRenderingMode(.multicolor)
                if wide {
                    HStack(spacing: 10) {
                        icon.font(.system(size: u * 0.5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int(w.temperature.rounded()))°").font(.system(size: u * 0.4, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize()
                            Text(place.name).font(.system(size: max(12, u * 0.13), weight: .semibold, design: .rounded)).foregroundStyle(acc)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(WeatherCode.text(w.code)).font(.system(size: max(10, u * 0.105), weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 2) {
                        icon.font(.system(size: size.width * 0.3))
                        Text("\(Int(w.temperature.rounded()))°").font(.system(size: size.width * 0.3, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(place.name).font(.system(size: max(11, size.width * 0.1), weight: .semibold, design: .rounded)).foregroundStyle(acc).lineLimit(1).minimumScaleFactor(0.6)
                        Text(WeatherCode.text(w.code)).font(.system(size: max(10, size.width * 0.085), weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            } else {
                note(item.weatherPlace == nil ? "mappin.and.ellipse" : "arrow.triangle.2.circlepath",
                     item.weatherPlace == nil ? "Elige una ciudad" : "Cargando…")
            }
        }
    }

    private func gauge(_ title: String, value: Double, text: String, sub: String, color: Color, history: [Double]? = nil) -> some View {
        Group {
            if veryWide {
                HStack(spacing: 12) {
                    ZStack {
                        Ring(progress: value, color: color, line: max(6, u * 0.09)).frame(width: u * 0.78, height: u * 0.78)
                        Text(text).font(.system(size: u * 0.2, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: max(12, u * 0.15), weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1).fixedSize()
                        Text(sub).font(.system(size: max(11, u * 0.14), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    if let history, size.width > 300 { Sparkline(values: history, color: color).frame(width: size.width * 0.28, height: u * 0.5) }
                }
            } else {
                VStack(spacing: 4) {
                    ZStack {
                        Ring(progress: value, color: color, line: max(6, u * 0.08)).frame(width: min(size.width * 0.66, size.height * 0.56), height: min(size.width * 0.66, size.height * 0.56))
                        Text(text).font(.system(size: min(size.width * 0.19, size.height * 0.13), weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(title).font(.system(size: max(12, size.width * 0.105), weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                    Text(sub).font(.system(size: max(10, size.width * 0.085), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }

    private var network: some View {
        let down = speed(snap.netDown), up = speed(snap.netUp)
        func block(_ symbol: String, _ v: (String, String), _ color: Color, _ fs: CGFloat) -> some View {
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: fs * 0.55, weight: .bold)).foregroundStyle(color)
                    Text(v.0).font(.system(size: fs, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                }
                Text(v.1).font(.system(size: max(10, fs * 0.4), weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            }
        }
        return Group {
            if wide {
                HStack(spacing: 8) {
                    block("arrow.down.circle.fill", down, acc, u * 0.36).frame(maxWidth: .infinity)
                    block("arrow.up.circle.fill", up, Color(hex: "#FF9F43"), u * 0.36).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    block("arrow.down.circle.fill", down, acc, min(size.width * 0.22, size.height * 0.18))
                    block("arrow.up.circle.fill", up, Color(hex: "#FF9F43"), min(size.width * 0.22, size.height * 0.18))
                }
            }
        }
    }

    private var battery: some View {
        let mac = snap.batteries.first { $0.isInternal }
        let low = snap.batteries.filter { !$0.isInternal }.min { $0.percent < $1.percent }
        return Group {
            if let mac {
                let c: Color = mac.charging ? Color(hex: "#2ED573") : (mac.percent <= 20 ? Color(hex: "#FF4D4D") : acc)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: mac.charging ? "bolt.fill" : "laptopcomputer").font(.system(size: u * 0.2)).foregroundStyle(c)
                        Text("\(mac.percent)%").font(.system(size: wide ? u * 0.42 : min(size.width * 0.27, size.height * 0.24), weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(c).frame(width: max(6, g.size.width * Double(mac.percent) / 100))
                        }
                    }
                    .frame(height: 6)
                    if let low, low.percent <= 30 {
                        Text("\(low.name) \(low.percent)%").font(.system(size: max(10, u * 0.12), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: low.percent <= 20 ? "#FF4D4D" : "#FF9F43")).lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        Text(snap.batteries.count > 1 ? "+ \(snap.batteries.count - 1) dispositivos" : (mac.charging ? "Cargando" : "Batería"))
                            .font(.system(size: max(10, u * 0.12), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            } else {
                note("powerplug.fill", "Conectado a la corriente")
            }
        }
    }

    private var temperature: some View {
        let cpu = snap.temps.first { $0.name == "CPU" } ?? snap.temps.first
        let ssd = snap.temps.first { $0.name == "SSD" }
        let c: Color = (cpu?.celsius ?? 0) < 60 ? Color(hex: "#2ED573") : ((cpu?.celsius ?? 0) < 80 ? Color(hex: "#FF9F43") : Color(hex: "#FF4D4D"))
        return Group {
            if let cpu {
                VStack(spacing: 3) {
                    Image(systemName: "thermometer.medium").font(.system(size: u * 0.2)).foregroundStyle(c)
                    Text("\(Int(cpu.celsius.rounded()))°C").font(.system(size: wide ? u * 0.4 : min(size.width * 0.27, size.height * 0.22), weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Text(cpu.name + (ssd.map { " · SSD \(Int($0.celsius.rounded()))°" } ?? "")).font(.system(size: max(10, u * 0.12), weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.6)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "thermometer.medium").font(.system(size: u * 0.22)).foregroundStyle(.white.opacity(0.5))
                    Text(snap.thermalState).font(.system(size: max(13, u * 0.17), weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("estado térmico").font(.system(size: max(10, u * 0.11), weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: u * 0.28)).foregroundStyle(acc)
            Text(text).font(.system(size: max(11, u * 0.12), weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
    }
}
