import Foundation
import SwiftUI

// Reconocer qué pantalla es cuál.
//
// Estas pantallas no tienen número de serie propio: todas dicen «Turing / UsbMonitor / USB35INCHIPSV2» y el protocolo no
// devuelve ningún dato. Lo único que las distingue es el puerto USB en el que están (bus + ruta de hubs, por ejemplo
// «2-1.4.1.3»), y ese puerto cambia si mueves el cable o si el dock o el hub se vuelven a numerar.
//
// Para que una pantalla conserve su configuración aunque cambie de puerto se usan estas capas, de más a menos seguras:
//   A. Historial: la pantalla ya estuvo antes en ese puerto.
//   B. Misma ruta en otro bus (por ejemplo, el dock enchufado a otro puerto del Mac).
//   C. Continuidad: se desconectaron hace poco y reaparecen, en el mismo orden relativo, en puertos nuevos.
//   D. Cuenta: hay tantas pantallas guardadas recientes sin conectar como pantallas nuevas conectadas.
// C y D son una suposición razonable, no una certeza: la app avisa para que se compruebe con «Identificar».
enum ScreenIdentity {
    struct Candidate {
        var key: String
        var aliases: [String]
        var lastSeen: Date?
        var goneAt: Date?        // cuándo se desconectó en esta sesión (nil si no se ha visto desconectarse)
    }

    struct Result {
        var matches: [String: String] = [:]     // clave nueva → clave guardada a la que corresponde
        var inferred: Set<String> = []          // claves nuevas relacionadas por C o D (no son seguras)
    }

    /// (bus, ruta) de una clave «bus-p.p.p».
    static func parts(_ key: String) -> [Int] {
        let bits = key.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let bus = Int(bits.first ?? "") ?? 0
        let path = bits.count > 1 ? bits[1].split(separator: ".").compactMap { Int($0) } : []
        return [bus] + path
    }

    static func path(_ key: String) -> String { parts(key).dropFirst().map(String.init).joined(separator: ".") }

    /// Orden físico aproximado: por bus y por puertos.
    static func ordered(_ keys: [String]) -> [String] {
        keys.sorted { parts($0).lexicographicallyPrecedes(parts($1)) }
    }

    static func resolve(unknown: [String], candidates: [Candidate], now: Date = Date(),
                        recentWindow: TimeInterval = 180, staleAfter: TimeInterval = 30 * 86_400) -> Result {
        var result = Result()
        var pending = ordered(unknown)
        var pool = candidates

        func take(_ new: String, _ old: String, inferred: Bool) {
            result.matches[new] = old
            if inferred { result.inferred.insert(new) }
            pending.removeAll { $0 == new }
            pool.removeAll { $0.key == old }
        }

        // A. Historial de puertos
        for k in pending {
            let m = pool.filter { $0.aliases.contains(k) }
            if m.count == 1 { take(k, m[0].key, inferred: false) }
        }
        // B. Misma ruta de hubs en otro bus
        for k in pending where pending.contains(k) {
            let m = pool.filter { path($0.key) == path(k) && !path(k).isEmpty }
            if m.count == 1 { take(k, m[0].key, inferred: false) }
        }
        guard !pending.isEmpty, !pool.isEmpty else { return result }

        // C. Continuidad: las que se desconectaron hace poco y vuelven en el mismo orden
        let recent = ordered(pool.filter { c in c.goneAt.map { now.timeIntervalSince($0) < recentWindow } ?? false }.map(\.key))
        if recent.count == pending.count {
            for (new, old) in zip(pending, recent) { take(new, old, inferred: true) }
            return result
        }
        // D. Cuenta: tantas guardadas (no antiguas) como pantallas nuevas
        let alive = ordered(pool.filter { c in c.lastSeen.map { now.timeIntervalSince($0) < staleAfter } ?? true }.map(\.key))
        if alive.count == pending.count {
            for (new, old) in zip(pending, alive) { take(new, old, inferred: true) }
        }
        return result
    }
}


/// Lo que se dibuja en la pantalla física al pulsar «Identificar»: su nombre y su ID en grande.
struct IdentifyCard: View {
    let name: String
    let key: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1B5BFF"), Color(hex: "#7C5CFF")], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 14) {
                Image(systemName: "eye.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.85))
                Text(name).font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.3)
                Text("ID \(key)").font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
                Text("Esta es la pantalla que estás identificando").font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }
}
