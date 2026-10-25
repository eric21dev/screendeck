import SwiftUI
import AppKit

// Widgets de datos del sistema y de internet: Tiempo, Discos, Procesos, GPU y temperatura, Noticias.

private func bytesDecimal(_ b: Double) -> String {            // discos: como el Finder (1 GB = 10⁹ bytes)
    if b >= 1e12 { return "\(num(b / 1e12, 1)) TB" }
    return "\(Int((b / 1e9).rounded())) GB"
}

private func bytesBinary(_ b: Double) -> String {             // memoria de procesos
    let gb = b / 1_073_741_824
    return gb >= 1 ? "\(num(gb, 1)) GB" : "\(Int((b / 1_048_576).rounded())) MB"
}

private func usageColor(_ used: Double) -> Color {
    used < 0.75 ? Color(hex: "#2ED573") : (used < 0.9 ? Color(hex: "#FF9F43") : Color(hex: "#FF4D4D"))
}

private struct Placeholder: View {
    let symbol: String
    let text: String
    let color: Color
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(color)
            Text(text).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

// MARK: - Tiempo

struct WeatherWidget: View {
    let item: WidgetItem
    let date: Date
    let size: CGSize
    let demo: Bool

    // demo = tarjeta de la galería sin usar: datos de ejemplo y sin tocar internet
    private var place: WeatherPlace? {
        demo ? WeatherPlace(name: "Madrid", region: "España", latitude: 40.4, longitude: -3.7) : item.weatherPlace
    }
    private var data: WeatherData? {
        if demo { return WeatherData.demo }
        return item.weatherPlace.flatMap { DataHub.shared.weather(for: $0) }
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        if let place, let w = data {
            if size.height >= size.width { portrait(place, w, acc) } else { landscape(place, w, acc) }
        } else if place != nil {
            Placeholder(symbol: "arrow.triangle.2.circlepath", text: "Cargando el tiempo…", color: acc)
        } else {
            Placeholder(symbol: "mappin.and.ellipse", text: "Elige una ciudad en los ajustes", color: acc)
        }
    }

    private func deg(_ t: Double) -> String { "\(Int(t.rounded()))°" }

    private func icon(_ code: Int, day: Bool, _ s: CGFloat) -> some View {
        Image(systemName: WeatherCode.symbol(code, day: day)).symbolRenderingMode(.multicolor).font(.system(size: s))
    }

    private func cityBlock(_ place: WeatherPlace) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(place.name).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            if !place.region.isEmpty {
                Text(place.region).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ w: WeatherData) -> some View {
        HStack(spacing: 12) {
            Label(deg(w.feelsLike), systemImage: "thermometer.medium")
            Label("\(w.humidity)%", systemImage: "drop.fill")
            Label("\(Int(w.windKmh.rounded())) km/h", systemImage: "wind")
        }
        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6)).labelStyle(CompactLabel())
    }

    private func hourly(_ w: WeatherData) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(w.hours.prefix(6).enumerated()), id: \.offset) { _, h in
                VStack(spacing: 5) {
                    Text(h.label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    icon(h.code, day: h.isDay, 19)
                    Text(deg(h.temp)).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func daily(_ w: WeatherData) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(w.days.dropFirst().prefix(3).enumerated()), id: \.offset) { _, d in
                HStack(spacing: 8) {
                    Text(d.label).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).frame(width: 44, alignment: .leading)
                    icon(d.code, day: true, 20).frame(width: 30)
                    Text(d.rain >= 20 ? "\(d.rain)%" : "").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: "#5AB8FF")).frame(width: 36, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(deg(d.min)).font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                    Text(deg(d.max)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(width: 40, alignment: .trailing)
                }
                .frame(height: 36)
            }
        }
    }

    private func portrait(_ place: WeatherPlace, _ w: WeatherData, _ acc: Color) -> some View {
        VStack(spacing: 0) {
            Header(symbol: "cloud.sun.fill", title: "TIEMPO", color: acc, date: date)
            cityBlock(place).padding(.top, 10)
            HStack(spacing: 6) {
                icon(w.code, day: w.isDay, 66)
                Text(deg(w.temperature)).font(.system(size: 84, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            HStack {
                Text(WeatherCode.text(w.code)).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(acc)
                Spacer()
                if let t = w.days.first {
                    Text("↑ \(deg(t.max))  ↓ \(deg(t.min))").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                }
            }
            details(w).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            Spacer(minLength: 8)
            hourly(w)
            daily(w).padding(.top, 6)
        }
        .padding(22)
    }

    private func landscape(_ place: WeatherPlace, _ w: WeatherData, _ acc: Color) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Header(symbol: "cloud.sun.fill", title: "TIEMPO", color: acc, date: date)
                cityBlock(place)
                HStack(spacing: 6) {
                    icon(w.code, day: w.isDay, 54)
                    Text(deg(w.temperature)).font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                Text(WeatherCode.text(w.code)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(acc)
                details(w)
                Spacer(minLength: 0)
            }
            .frame(width: 235)
            VStack(spacing: 8) {
                Spacer(minLength: 28)
                hourly(w)
                daily(w)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 12)); configuration.title }
    }
}

// MARK: - Discos

struct DisksWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    var body: some View {
        let acc = Color(hex: item.accent)
        let portrait = size.height >= size.width
        let maxRows = portrait ? 4 : 3
        let vols = snap.volumes
        VStack(spacing: 10) {
            Header(symbol: "internaldrive.fill", title: "DISCOS", color: acc, date: date)
            if vols.isEmpty {
                Spacer()
                Placeholder(symbol: "internaldrive", text: "Leyendo discos…", color: acc)
                Spacer()
            } else {
                ForEach(Array(vols.prefix(maxRows).enumerated()), id: \.offset) { _, v in row(v, acc, portrait) }
                if vols.count > maxRows {
                    Text("+ \(vols.count - maxRows) más").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(portrait ? 22 : 20)
    }

    private func row(_ v: VolumeInfo, _ acc: Color, _ portrait: Bool) -> some View {
        let c = usageColor(v.used)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: v.path == "/" ? "internaldrive.fill" : (v.isExternal ? "externaldrive.fill" : "internaldrive"))
                    .font(.system(size: 18)).foregroundStyle(acc).frame(width: 26)
                Text(v.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(Int((v.used * 100).rounded()))%").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(c).frame(width: max(8, g.size.width * v.used))
                }
            }
            .frame(height: 8)
            Text("\(bytesDecimal(v.free)) libres de \(bytesDecimal(v.total))")
                .font(.system(size: 12.5, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14).padding(.vertical, portrait ? 10 : 7)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
    }
}

// MARK: - Procesos

struct ProcessesWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    var body: some View {
        let acc = Color(hex: item.accent)
        let portrait = size.height >= size.width
        let cpu = section("CPU", snap.topCPU, valueText: { "\(Int($0.cpu.rounded()))%" }, amount: { $0.cpu }, color: acc)
        let mem = section("MEMORIA", snap.topMem, valueText: { bytesBinary($0.memBytes) }, amount: { $0.memBytes }, color: Color(hex: "#FF9F43"))
        VStack(spacing: 6) {
            Header(symbol: "chart.bar.fill", title: "PROCESOS", color: acc, date: date)
            if snap.topCPU.isEmpty {
                Spacer()
                Placeholder(symbol: "chart.bar", text: "Leyendo procesos…", color: acc)
                Spacer()
            } else if portrait {
                cpu
                mem
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 16) { cpu; mem }
                Spacer(minLength: 0)
            }
        }
        .padding(portrait ? 18 : 18)
    }

    private func section(_ title: String, _ list: [ProcessUsage], valueText: @escaping (ProcessUsage) -> String,
                         amount: @escaping (ProcessUsage) -> Double, color: Color) -> some View {
        let top = max(list.map(amount).max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(color).padding(.leading, 4)
            ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 10) {
                    if let img = AppIcons.icon(p.appPath) {
                        Image(nsImage: img).resizable().frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "gearshape.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45)).frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1))
                                Capsule().fill(color).frame(width: max(4, g.size.width * min(1, amount(p) / top)))
                            }
                        }
                        .frame(height: 4)
                    }
                    Text(valueText(p)).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .frame(width: 62, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 10).frame(height: 31)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - GPU y temperatura

struct ThermalWidget: View {
    let item: WidgetItem
    let snap: StatsSnapshot
    let date: Date
    let size: CGSize

    private func tempColor(_ c: Double) -> Color {
        c < 60 ? Color(hex: "#2ED573") : (c < 80 ? Color(hex: "#FF9F43") : Color(hex: "#FF4D4D"))
    }

    private var stateColor: Color {
        switch snap.thermalState {
        case "Normal": return Color(hex: "#2ED573")
        case "Algo alto": return Color(hex: "#FFD93D")
        case "Alto": return Color(hex: "#FF9F43")
        default: return Color(hex: "#FF4D4D")
        }
    }

    var body: some View {
        let acc = Color(hex: item.accent)
        let portrait = size.height >= size.width
        VStack(spacing: 12) {
            Header(symbol: "thermometer.medium", title: "GPU Y TEMPERATURA", color: acc, date: date)
            if portrait {
                gpuBlock(acc, ring: 118)
                temps(acc)
                Spacer(minLength: 0)
                stateBar(short: false)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    gpuBlock(acc, ring: 112)
                    VStack(spacing: 10) { temps(acc); Spacer(minLength: 0); stateBar(short: true) }
                }
            }
        }
        .padding(size.height >= size.width ? 22 : 20)
    }

    private func gpuBlock(_ acc: Color, ring: CGFloat) -> some View {
        let g = snap.gpu
        return HStack(spacing: 14) {
            ZStack {
                Ring(progress: g ?? 0, color: acc, line: 11).frame(width: ring, height: ring)
                Text(g.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("GPU").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                Text(g == nil ? "Sin datos" : "en uso").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                Sparkline(values: snap.gpuHistory, color: acc).frame(width: 110, height: 40)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func temps(_ acc: Color) -> some View {
        VStack(spacing: 8) {
            if snap.temps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "thermometer.slash").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5))
                    Text("Este Mac no da lecturas de temperatura").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Text("Se muestra el estado térmico del sistema").font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity).padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
            } else {
                ForEach(Array(snap.temps.enumerated()), id: \.offset) { _, t in
                    let c = tempColor(t.celsius)
                    VStack(spacing: 6) {
                        HStack {
                            Text(t.name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            Spacer()
                            Text("\(Int(t.celsius.rounded()))°C").font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1))
                                Capsule().fill(c).frame(width: max(6, g.size.width * min(1, max(0, (t.celsius - 20) / 80))))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
                }
            }
        }
    }

    private func stateBar(short: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(stateColor).frame(width: 9, height: 9)
            Text(short ? "Estado térmico" : "Estado térmico del Mac").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(snap.thermalState).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(stateColor)
        }
    }
}

// MARK: - Noticias

private func relativeTime(_ d: Date?, now: Date) -> String {
    guard let d else { return "" }
    let s = max(0, now.timeIntervalSince(d))
    if s < 3600 { return "hace \(max(1, Int(s / 60))) min" }
    if s < 86400 { return "hace \(Int(s / 3600)) h" }
    return "hace \(Int(s / 86400)) d"
}

struct NewsWidget: View {
    let item: WidgetItem
    let date: Date
    let size: CGSize
    let demo: Bool

    var body: some View {
        let acc = Color(hex: item.accent)
        let portrait = size.height >= size.width
        let result = demo ? NewsResult.demo : DataHub.shared.news(for: item)
        let list = result.items
        VStack(alignment: .leading, spacing: 0) {
            Header(symbol: "newspaper.fill", title: "NOTICIAS", color: acc, date: date)
            if list.isEmpty {
                Spacer()
                HStack { Spacer(); placeholder(result, acc); Spacer() }
                Spacer()
            } else {
                let secs = item.newsSlideSeconds
                let t = Int(date.timeIntervalSince1970)
                let idx = (t / secs) % list.count
                let n = list[idx]
                Text(n.source).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(acc)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(acc.opacity(0.18))).lineLimit(1)
                    .padding(.top, portrait ? 16 : 10)
                Text(n.title).font(.system(size: portrait ? 25 : 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(portrait ? 6 : 3).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, portrait ? 14 : 8)
                if !n.summary.isEmpty {
                    Text(n.summary).font(.system(size: portrait ? 16 : 14.5, weight: .regular)).foregroundStyle(.white.opacity(0.68))
                        .lineLimit(portrait ? 10 : 4).lineSpacing(2).padding(.top, portrait ? 12 : 8)
                }
                Spacer(minLength: 8)
                HStack {
                    Text(relativeTime(n.date, now: date)).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("\(idx + 1) / \(list.count)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(acc).frame(width: max(4, g.size.width * Double(t % secs + 1) / Double(secs)))
                    }
                }
                .frame(height: 4).padding(.top, 6)
            }
        }
        .padding(portrait ? 22 : 20)
    }

    @ViewBuilder private func placeholder(_ r: NewsResult, _ acc: Color) -> some View {
        if r.noSources { Placeholder(symbol: "checklist", text: "Elige alguna categoría en los ajustes", color: acc) }
        else if r.failed { Placeholder(symbol: "wifi.slash", text: "No se pudieron cargar las noticias", color: acc) }
        else { Placeholder(symbol: "arrow.triangle.2.circlepath", text: "Cargando noticias…", color: acc) }
    }
}
