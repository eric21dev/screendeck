import Foundation

// Datos de internet para los widgets Tiempo y Noticias. Nada de esto necesita claves ni cuentas:
// el tiempo viene de Open-Meteo (https://open-meteo.com) y las noticias de feeds RSS públicos.

// MARK: - Tiempo

struct WeatherPlace: Codable, Hashable {
    var name: String
    var region: String        // «Comunidad de Madrid · España»
    var latitude: Double
    var longitude: Double
}

struct WeatherHour { var label: String; var temp: Double; var code: Int; var isDay: Bool }
struct WeatherDay { var label: String; var max: Double; var min: Double; var code: Int; var rain: Int }

struct WeatherData {
    var temperature: Double
    var feelsLike: Double
    var humidity: Int
    var windKmh: Double
    var code: Int
    var isDay: Bool
    var hours: [WeatherHour]
    var days: [WeatherDay]      // el primero es hoy
    var updated: Date

    static let demo = WeatherData(
        temperature: 18, feelsLike: 16, humidity: 54, windKmh: 14, code: 2, isDay: true,
        hours: [WeatherHour(label: "15h", temp: 19, code: 2, isDay: true), WeatherHour(label: "16h", temp: 20, code: 1, isDay: true),
                WeatherHour(label: "17h", temp: 19, code: 3, isDay: true), WeatherHour(label: "18h", temp: 17, code: 61, isDay: true),
                WeatherHour(label: "19h", temp: 15, code: 61, isDay: false), WeatherHour(label: "20h", temp: 14, code: 3, isDay: false)],
        days: [WeatherDay(label: "Hoy", max: 20, min: 11, code: 2, rain: 20), WeatherDay(label: "Lun", max: 21, min: 12, code: 1, rain: 5),
               WeatherDay(label: "Mar", max: 17, min: 10, code: 63, rain: 80), WeatherDay(label: "Mié", max: 18, min: 9, code: 3, rain: 30)],
        updated: Date())
}

/// Códigos meteorológicos WMO → símbolo y texto.
enum WeatherCode {
    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 67: return "cloud.rain.fill"
        case 65, 81, 82: return "cloud.heavyrain.fill"
        case 80: return "cloud.sun.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Despejado"
        case 1: return "Casi despejado"
        case 2: return "Parcialmente nublado"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51, 53, 55: return "Llovizna"
        case 56, 57: return "Llovizna helada"
        case 61: return "Lluvia débil"
        case 63: return "Lluvia"
        case 65: return "Lluvia fuerte"
        case 66, 67: return "Lluvia helada"
        case 71, 73, 75, 77: return "Nieve"
        case 80, 81: return "Chubascos"
        case 82: return "Chubascos fuertes"
        case 85, 86: return "Chubascos de nieve"
        case 95: return "Tormenta"
        case 96, 99: return "Tormenta con granizo"
        default: return "—"
        }
    }
}

// MARK: - Noticias

struct NewsItem: Codable, Hashable {
    var title: String
    var summary: String
    var link: String
    var date: Date?
    var source: String
}

struct NewsCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let source: String
    let url: String

    static let all: [NewsCategory] = [
        NewsCategory(id: "portada", title: "Portada", symbol: "newspaper", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada"),
        NewsCategory(id: "internacional", title: "Internacional", symbol: "globe.europe.africa", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/internacional/portada"),
        NewsCategory(id: "espana", title: "España", symbol: "building.columns", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/espana/portada"),
        NewsCategory(id: "economia", title: "Economía", symbol: "chart.line.uptrend.xyaxis", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/economia/portada"),
        NewsCategory(id: "tecnologia", title: "Tecnología", symbol: "cpu", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/tecnologia/portada"),
        NewsCategory(id: "ciencia", title: "Ciencia", symbol: "atom", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/ciencia/portada"),
        NewsCategory(id: "deportes", title: "Deportes", symbol: "sportscourt", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/deportes/portada"),
        NewsCategory(id: "cultura", title: "Cultura", symbol: "theatermasks", source: "El País",
                     url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/cultura/portada"),
        NewsCategory(id: "mundo-bbc", title: "Mundo (BBC)", symbol: "globe", source: "BBC Mundo",
                     url: "https://feeds.bbci.co.uk/mundo/rss.xml"),
        NewsCategory(id: "xataka", title: "Tecnología (Xataka)", symbol: "desktopcomputer", source: "Xataka",
                     url: "https://www.xataka.com/feedburner.xml"),
        NewsCategory(id: "20minutos", title: "Última hora (20minutos)", symbol: "bolt.fill", source: "20minutos",
                     url: "https://www.20minutos.es/rss/"),
    ]
}

struct NewsResult {
    var items: [NewsItem] = []
    var updated: Date?
    var loading = false
    var failed = false
    var noSources = false

    static let demo = NewsResult(items: [
        NewsItem(title: "Un nuevo telescopio detecta señales de agua en un planeta a 120 años luz",
                 summary: "Los investigadores han analizado la atmósfera del exoplaneta durante más de un año y creen que podría ser un buen candidato para seguir estudiándolo con la próxima generación de instrumentos.",
                 link: "", date: Date().addingTimeInterval(-3600 * 3), source: "Ciencia · El País"),
        NewsItem(title: "La economía europea modera su ritmo de crecimiento en el último trimestre",
                 summary: "El consumo de los hogares compensa la caída de la inversión, según los datos publicados esta mañana por el organismo estadístico.",
                 link: "", date: Date().addingTimeInterval(-3600 * 5), source: "Economía · El País"),
    ], updated: Date())
}

// MARK: - Caché y descargas

final class DataHub: @unchecked Sendable {
    static let shared = DataHub()

    /// Para las capturas del README: devuelve siempre datos de ejemplo.
    var demoMode = false

    private let lock = NSLock()
    private var weather: [String: WeatherData] = [:]
    private var weatherTried: [String: Date] = [:]
    private struct FeedState: Codable { var items: [NewsItem]; var fetched: Date }
    private var feeds: [String: FeedState] = [:]
    private var feedTried: [String: Date] = [:]
    private var inflight: Set<String> = []

    private let weatherTTL: TimeInterval = 600        // el tiempo se renueva cada 10 min
    private let newsTTL: TimeInterval = 3600          // las noticias, cada hora
    private let retryDelay: TimeInterval = 60

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenDeck")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("news.json")
    }

    private init() {
        if let d = try? Data(contentsOf: cacheURL) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            feeds = (try? dec.decode([String: FeedState].self, from: d)) ?? [:]
        }
    }

    private func saveFeeds() {      // se llama con el candado cogido
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(feeds) { try? d.write(to: cacheURL) }
    }

    // MARK: tiempo

    /// Lo último que se sabe del tiempo; si está viejo o no hay nada, lanza una descarga en segundo plano.
    func weather(for p: WeatherPlace) -> WeatherData? {
        if demoMode { return .demo }
        let key = "\(p.latitude),\(p.longitude)"
        lock.lock()
        let cached = weather[key]
        let stale = cached == nil || Date().timeIntervalSince(cached!.updated) > weatherTTL
        let canTry = Date().timeIntervalSince(weatherTried[key] ?? .distantPast) > retryDelay
        let start = stale && canTry && !inflight.contains("w" + key)
        if start { weatherTried[key] = Date(); inflight.insert("w" + key) }
        lock.unlock()
        if start { Task.detached { await self.fetchWeather(p, key: key) } }
        return cached
    }

    private func fetchWeather(_ p: WeatherPlace, key: String) async {
        defer { lock.withLock { _ = inflight.remove("w" + key) } }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(p.latitude)),
            URLQueryItem(name: "longitude", value: String(p.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(for: request(url)),
              let w = DataHub.parseWeather(data) else { return }
        lock.withLock { weather[key] = w }
    }

    static func parseWeather(_ data: Data) -> WeatherData? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = j["current"] as? [String: Any], let temp = jnum(cur["temperature_2m"]) else { return nil }
        let tz = TimeZone(secondsFromGMT: (j["utc_offset_seconds"] as? Int) ?? 0) ?? .current
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let fd = DateFormatter(); fd.locale = Locale(identifier: "en_US_POSIX"); fd.timeZone = tz; fd.dateFormat = "yyyy-MM-dd"
        let hourLabel = DateFormatter(); hourLabel.locale = Locale(identifier: "es_ES"); hourLabel.timeZone = tz; hourLabel.dateFormat = "HH'h'"
        let dayLabel = DateFormatter(); dayLabel.locale = Locale(identifier: "es_ES"); dayLabel.timeZone = tz; dayLabel.dateFormat = "EEE"
        let now = (cur["time"] as? String).flatMap { f.date(from: $0) } ?? Date()

        var hours: [WeatherHour] = []
        if let h = j["hourly"] as? [String: Any], let times = h["time"] as? [String] {
            let temps = h["temperature_2m"] as? [Any] ?? [], codes = h["weather_code"] as? [Any] ?? [], days = h["is_day"] as? [Any] ?? []
            for (i, t) in times.enumerated() where i < temps.count && i < codes.count {
                guard let d = f.date(from: t), d > now, let tv = jnum(temps[i]), let cv = jnum(codes[i]) else { continue }
                hours.append(WeatherHour(label: hourLabel.string(from: d), temp: tv, code: Int(cv), isDay: (i < days.count ? jnum(days[i]) ?? 1 : 1) > 0))
                if hours.count == 6 { break }
            }
        }
        var days: [WeatherDay] = []
        if let d = j["daily"] as? [String: Any], let times = d["time"] as? [String] {
            let mx = d["temperature_2m_max"] as? [Any] ?? [], mn = d["temperature_2m_min"] as? [Any] ?? []
            let cs = d["weather_code"] as? [Any] ?? [], ps = d["precipitation_probability_max"] as? [Any] ?? []
            for (i, t) in times.enumerated() where i < mx.count && i < mn.count && i < cs.count {
                guard let date = fd.date(from: t), let a = jnum(mx[i]), let b = jnum(mn[i]), let c = jnum(cs[i]) else { continue }
                let label = i == 0 ? "Hoy" : dayLabel.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
                days.append(WeatherDay(label: label, max: a, min: b, code: Int(c), rain: i < ps.count ? Int(jnum(ps[i]) ?? 0) : 0))
            }
        }
        return WeatherData(temperature: temp, feelsLike: jnum(cur["apparent_temperature"]) ?? temp,
                           humidity: Int(jnum(cur["relative_humidity_2m"]) ?? 0), windKmh: jnum(cur["wind_speed_10m"]) ?? 0,
                           code: Int(jnum(cur["weather_code"]) ?? 0), isDay: (jnum(cur["is_day"]) ?? 1) > 0,
                           hours: hours, days: days, updated: Date())
    }

    /// Busca ciudades por nombre (para elegir la ubicación del widget).
    static func searchPlaces(_ query: String) async -> [WeatherPlace] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: q), URLQueryItem(name: "count", value: "6"),
                        URLQueryItem(name: "language", value: "es"), URLQueryItem(name: "format", value: "json")]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rs = j["results"] as? [[String: Any]] else { return [] }
        return rs.compactMap { r in
            guard let name = r["name"] as? String, let lat = jnum(r["latitude"]), let lon = jnum(r["longitude"]) else { return nil }
            let region = [r["admin1"] as? String, r["country"] as? String].compactMap { $0 }.joined(separator: " · ")
            return WeatherPlace(name: name, region: region, latitude: lat, longitude: lon)
        }
    }

    // MARK: noticias

    private func feedURLs(for item: WidgetItem) -> [(url: String, source: String)] {
        var out: [(String, String)] = NewsCategory.all.filter { item.newsIDs.contains($0.id) }.map { ($0.url, "\($0.title) · \($0.source)") }
        if let c = item.newsCustomURL?.trimmingCharacters(in: .whitespaces), let u = URL(string: c),
           let host = u.host, u.scheme == "http" || u.scheme == "https" {
            out.append((c, host.replacingOccurrences(of: "www.", with: "")))
        }
        return out
    }

    /// Titulares de las categorías elegidas, mezclados entre sí; refresca en segundo plano lo que esté viejo.
    func news(for item: WidgetItem) -> NewsResult {
        if demoMode { return .demo }
        let sources = feedURLs(for: item)
        guard !sources.isEmpty else { return NewsResult(noSources: true) }
        var toFetch: [(String, String)] = []
        var lists: [[NewsItem]] = []
        var updated: Date?
        var pending = false, missing = 0
        lock.lock()
        for (url, source) in sources {
            let st = feeds[url]
            if let st {
                lists.append(Array(st.items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(8)))
                updated = min(updated ?? st.fetched, st.fetched)
            } else { missing += 1 }
            let stale = st == nil || Date().timeIntervalSince(st!.fetched) > newsTTL
            let canTry = Date().timeIntervalSince(feedTried[url] ?? .distantPast) > retryDelay
            if stale && canTry && !inflight.contains(url) { feedTried[url] = Date(); inflight.insert(url); toFetch.append((url, source)) }
            if inflight.contains(url) { pending = true }
        }
        lock.unlock()
        for (url, source) in toFetch { Task.detached { await self.fetchFeed(url, source: source) } }

        // Mezcla por turnos entre categorías y quita repetidas
        var items: [NewsItem] = [], seen = Set<String>()
        var i = 0
        while items.count < 40, lists.contains(where: { i < $0.count }) {
            for l in lists where i < l.count {
                let k = l[i].title.lowercased()
                if seen.insert(k).inserted { items.append(l[i]) }
            }
            i += 1
        }
        return NewsResult(items: items, updated: updated, loading: pending && items.isEmpty, failed: items.isEmpty && !pending && missing > 0)
    }

    /// Fuerza una descarga nueva de las fuentes de este widget.
    func refreshNews(for item: WidgetItem) {
        lock.lock()
        for (url, _) in feedURLs(for: item) { feeds[url]?.fetched = .distantPast; feedTried[url] = nil }
        lock.unlock()
        _ = news(for: item)
    }

    private func fetchFeed(_ url: String, source: String) async {
        defer { lock.withLock { _ = inflight.remove(url) } }
        guard let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(for: request(u)) else { return }
        let items = RSSParser.parse(data, source: source)
        guard !items.isEmpty else { return }
        lock.withLock { feeds[url] = FeedState(items: items, fetched: Date()); saveFeeds() }
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.setValue("Mozilla/5.0 (Macintosh) ScreenDeck", forHTTPHeaderField: "User-Agent")
        return r
    }
}

private func jnum(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

// MARK: - Lector de RSS / Atom

final class RSSParser: NSObject, XMLParserDelegate {
    private struct Raw { var title = "", desc = "", link = "", date = "" }
    private var items: [Raw] = []
    private var cur: Raw?
    private var text = ""

    static func parse(_ data: Data, source: String) -> [NewsItem] {
        let p = RSSParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.items.compactMap { r in
            let title = cleanHTML(r.title)
            guard !title.isEmpty else { return nil }
            var summary = cleanHTML(r.desc)
            if summary.lowercased() == title.lowercased() { summary = "" }
            return NewsItem(title: title, summary: truncate(summary, 380), link: r.link.trimmingCharacters(in: .whitespacesAndNewlines),
                            date: parseDate(r.date), source: source)
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let n = name.lowercased()
        if n == "item" || n == "entry" { cur = Raw() }
        text = ""
        if cur != nil, n == "link", let href = attributes["href"], cur!.link.isEmpty { cur!.link = href }   // Atom
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard cur != nil else { return }
        switch name.lowercased() {
        case "title": if cur!.title.isEmpty { cur!.title = text }
        case "description", "summary", "content:encoded", "content": if cur!.desc.isEmpty { cur!.desc = text }
        case "link": if cur!.link.isEmpty { cur!.link = text }
        case "pubdate", "updated", "published", "dc:date": if cur!.date.isEmpty { cur!.date = text }
        case "item", "entry": items.append(cur!); cur = nil
        default: break
        }
    }

    private static let dateFormats = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z",
                                      "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"]
    private static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in dateFormats { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return nil
    }

    private static let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
                                   "&mdash;": "—", "&ndash;": "–", "&laquo;": "«", "&raquo;": "»", "&iquest;": "¿", "&iexcl;": "¡",
                                   "&lsquo;": "‘", "&rsquo;": "’", "&ldquo;": "“", "&rdquo;": "”"]

    static func cleanHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<(script|style)[^>]*>.*?</\\1>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        // Entidades numéricas: &#233; y &#xE9;
        for (pattern, radix) in [("&#([0-9]+);", 10), ("&#[xX]([0-9a-fA-F]+);", 16)] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let r = Range(m.range, in: s), let g = Range(m.range(at: 1), in: s),
                      let code = UInt32(s[g], radix: radix), let u = Unicode.Scalar(code) else { continue }
                s.replaceSubrange(r, with: String(Character(u)))
            }
        }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        guard s.count > max else { return s }
        let cut = String(s.prefix(max))
        if let sp = cut.lastIndex(of: " ") { return String(cut[..<sp]) + "…" }
        return cut + "…"
    }
}
