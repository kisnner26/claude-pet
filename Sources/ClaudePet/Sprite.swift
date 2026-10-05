import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Pal {
    static let charcoal = Color(hex: 0x1C1B1A)
    static let body = Color(hex: 0xE0824F)
    static let light = Color(hex: 0xEC9A6E)
    static let dark = Color(hex: 0xB9603A)
    static let cream = Color(hex: 0xEDE3DA)
}

/// Lo que la mascota sabe de su par (otra mascota en el pet bus).
struct PeerCue { var state: PetState; var greet: Bool; var cheer: Bool; var concern: Bool; var game: GameFrame? = nil }

struct Px { let x: Int; let y: Int; let c: Color }

/// Mascota original: bloque naranja ancho con orejas laterales, cuatro patas y ojos en chevron.
/// Rejilla 16x16: cuerpo y4..12, patas y13..15.
enum Skin: String, CaseIterable {
    case block, classic
    var title: String { self == .block ? "Bloque" : "Clasico" }
}

enum Sprite {
    nonisolated(unsafe) static var skin: Skin = .block

    static func pixels(_ s: PetState, tick t: Int, cue: PeerCue? = nil) -> [Px] {
        skin == .block ? block(s, tick: t, cue: cue) : classic(s, tick: t, cue: cue)
    }

    /// Companero en miniatura (esquina superior izquierda) que refleja el estado del par,
    /// mas destellos de celebracion o preocupacion.
    static func peerOverlay(_ cue: PeerCue?, tick t: Int) -> [Px] {
        guard let c = cue, c.game == nil else { return [] }   // durante el partido el avatar de Codex esta en el escenario
        var o: [Px] = []
        let m = Pal.cream.opacity(0.85)
        for x in 0...3 { o.append(Px(x: x, y: 1, c: m)); o.append(Px(x: x, y: 2, c: m)) }
        o.append(Px(x: 0, y: 3, c: m)); o.append(Px(x: 3, y: 3, c: m))
        switch c.state {
        case .thinking, .starting: o.append(Px(x: (t / 3) % 4, y: 0, c: Pal.cream))
        case .tool: o.append(Px(x: t % 2 == 0 ? 0 : 3, y: 0, c: Pal.cream))
        case .waiting: if t % 6 < 4 { o.append(Px(x: 1, y: 0, c: Pal.body)); o.append(Px(x: 2, y: 0, c: Pal.body)) }
        case .done: o.append(Px(x: 1, y: 0, c: Pal.light)); o.append(Px(x: 2, y: 0, c: Pal.light))
        case .error: if t % 2 == 0 { o.append(Px(x: 1, y: 0, c: Pal.dark)); o.append(Px(x: 2, y: 0, c: Pal.dark)) }
        case .idle: break
        }
        if c.cheer {
            let on = t % 2 == 0
            for (x, y) in on ? [(4, 0), (0, 4)] : [(5, 1), (4, 3)] { o.append(Px(x: x, y: y, c: Pal.cream)) }
        }
        if c.concern, t % 2 == 0 { o.append(Px(x: 4, y: 2, c: Pal.dark)) }
        return o
    }

    /// Aspecto clasico: cuerpo 8x6, brazos largos y cuatro patas, ojos de un pixel.
    /// Origen en (2, 5) de la rejilla 16x16.
    static func classic(_ s: PetState, tick t: Int, cue: PeerCue? = nil) -> [Px] {
        var out: [Px] = []
        var dx = 0, dy = 0
        switch s {
        case .done: dy = (t % 8 < 2) ? -1 : 0
        case .error: dx = (t % 2 == 0) ? 1 : -1
        case .waiting: dy = (t % 6 < 3) ? 0 : -1
        default: break
        }
        let ox = 2, oy = 5
        if cue?.game?.claudeHop == true { dy = -1 }
        if cue?.game?.celebrateMoving == true { dy = (t % 2 == 0) ? -1 : 0 }
        func put(_ x: Int, _ y: Int, _ c: Color, shift: Bool = true) {
            out.append(Px(x: x + ox + (shift ? dx : 0), y: y + oy + (shift ? dy : 0), c: c))
        }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Color) {
            for y in y0...y1 { for x in x0...x1 { put(x, y, c) } }
        }
        let b = Pal.body, ink = Pal.charcoal
        // brazos
        var armL = 0, armR = 0
        switch s {
        case .tool: armL = (t % 2 == 0) ? 0 : 1; armR = 1 - armL
        case .waiting: armL = -3; armR = -3
        case .done: armL = -2; armR = -2
        case .error: armL = 2; armR = 2
        default: break
        }
        let cheerArm = cue?.game?.celebrateMoving == true ? ((t % 2 == 0) ? -2 : -1) : 0
        let armLg = cheerArm != 0 ? cheerArm : ((cue?.greet == true && armL == 0) ? ((t % 4 < 2) ? -3 : -2) : armL)
        if cheerArm != 0 { armR = cheerArm }
        rect(0, 2 + armLg, 1, 3 + armLg, b)
        rect(10, 2 + armR, 11, 3 + armR, b)
        // patas y cuerpo
        for x in [2, 4, 7, 9] { rect(x, 6, x, 7, b) }
        rect(2, 0, 9, 5, b)

        let blink = (t % 30) >= 28
        switch s {
        case .idle:
            if !blink { put(3, 1, ink); put(8, 1, ink) }
        case .starting:
            break
        case .thinking:
            let sh = [(-1, -1), (0, -1), (1, -1), (0, -1)][(t / 4) % 4]
            put(3 + sh.0, 1 + sh.1 + 1, ink); put(8 + sh.0, 1 + sh.1 + 1, ink)
        case .tool:
            put(3, 1, ink); put(8, 1, ink)
            let cx = 3 + t % 4
            for x in cx...(cx + 1) { put(x, 4, ink) }
        case .waiting:
            put(3, 0, ink); put(3, 1, ink); put(8, 0, ink); put(8, 1, ink)
        case .done:
            put(2, 2, ink); put(3, 1, ink); put(4, 2, ink); put(7, 2, ink); put(8, 1, ink); put(9, 2, ink)
        case .error:
            for (x, y) in [(2, 0), (4, 0), (3, 1), (2, 2), (4, 2), (7, 0), (9, 0), (8, 1), (7, 2), (9, 2)] { put(x, y, ink) }
        }

        func top(_ x: Int, _ y: Int, _ c: Color) { out.append(Px(x: x, y: y, c: c)) }
        let acc = Pal.cream
        switch s {
        case .starting:
            let n = (t / 2) % 9
            for i in 0..<8 { top(4 + i, 1, i < n ? Pal.body : Pal.dark) }
        case .thinking:
            let n = (t / 3) % 4
            for i in 0..<3 where i < n { top(5 + i * 3, 1, acc) }
        case .tool:
            if t % 2 == 0 { top(13, 3, Pal.light); top(14, 2, Pal.light) }
            else { top(14, 3, Pal.light); top(13, 2, Pal.light) }
        case .waiting:
            if t % 6 < 4 { for x in 7...8 { top(x, 0, acc); top(x, 1, acc); top(x, 3, acc) } }
        case .done:
            for (x, y) in [(6, 2), (7, 3), (8, 2), (9, 1), (10, 0)] { top(x, y, acc) }
        case .error:
            let f = t % 4
            for (x, y) in [(7, 1 + f % 2), (8, 2 - f % 2), (7, 3)] { top(x, y, Pal.dark) }
        default: break
        }
        return out + peerOverlay(cue, tick: t)
    }

    static func block(_ s: PetState, tick t: Int, cue: PeerCue? = nil) -> [Px] {
        var out: [Px] = []
        var dx = 0, dy = 0
        switch s {
        case .done: dy = (t % 8 < 2) ? -1 : 0
        case .error: dx = (t % 2 == 0) ? 1 : -1
        case .waiting: dy = (t % 6 < 3) ? 0 : -1
        default: break
        }
        if cue?.game?.claudeHop == true { dy = -1 }
        if cue?.game?.celebrateMoving == true { dy = (t % 2 == 0) ? -1 : 0 }
        func put(_ x: Int, _ y: Int, _ c: Color, shift: Bool = true) {
            out.append(Px(x: x + (shift ? dx : 0), y: y + (shift ? dy : 0), c: c))
        }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Color, shift: Bool = true) {
            for y in y0...y1 { for x in x0...x1 { put(x, y, c, shift: shift) } }
        }

        // orejas laterales: suben o bajan segun el estado
        var ear = 0
        switch s {
        case .tool: ear = (t % 2 == 0) ? 0 : 1
        case .waiting: ear = -3
        case .done: ear = -2
        case .error: ear = 2
        default: break
        }
        let cheerEar = cue?.game?.celebrateMoving == true ? ((t % 2 == 0) ? -3 : -1) : 0
        let earL = cheerEar != 0 ? cheerEar : ((cue?.greet == true && ear == 0) ? ((t % 4 < 2) ? -3 : -2) : ear)
        rect(0, 7 + earL, 1, 10 + earL, Pal.body)
        rect(0, 7 + earL, 0, 10 + earL, Pal.dark)
        let ear2 = cheerEar != 0 ? cheerEar : ((s == .tool) ? 1 - ear : ear)
        rect(14, 7 + ear2, 15, 10 + ear2, Pal.body)
        rect(15, 7 + ear2, 15, 10 + ear2, Pal.dark)

        // patas (dos pares)
        for x in [3, 6, 9, 12] { rect(x, 13, x + 1, 15, Pal.body); put(x, 15, Pal.dark); put(x + 1, 15, Pal.dark) }

        // cuerpo: tapa clara arriba, borde oscuro a la derecha
        rect(2, 4, 13, 12, Pal.body)
        rect(2, 4, 13, 4, Pal.light)
        rect(13, 5, 13, 12, Pal.dark)
        rect(2, 12, 13, 12, Pal.dark)

        let ink = Pal.charcoal
        func line(_ pts: [(Int, Int)]) { for (x, y) in pts { put(x, y, ink) } }
        let chevL = [(4, 6), (5, 7), (6, 8), (5, 9), (4, 10)]
        let chevR = [(11, 6), (10, 7), (9, 8), (10, 9), (11, 10)]
        let blink = (t % 30) >= 28

        switch s {
        case .idle:
            if blink { line([(4, 8), (5, 8), (6, 8), (9, 8), (10, 8), (11, 8)]) }
            else { line(chevL); line(chevR) }
        case .starting:
            line([(4, 8), (5, 8), (6, 8), (9, 8), (10, 8), (11, 8)])
        case .thinking:
            let sh = [(-1, -1), (0, -1), (1, -1), (0, -1)][(t / 4) % 4]
            line(chevL.map { ($0.0 + sh.0, $0.1 + sh.1) }); line(chevR.map { ($0.0 + sh.0, $0.1 + sh.1) })
        case .tool:
            // ojos entrecerrados, cursor de escritura bajo ellos
            line([(4, 7), (5, 8), (6, 7), (9, 7), (10, 8), (11, 7)])
            let cx = 5 + (t % 4) * 1
            for x in cx...(cx + 2) { put(x, 11, ink) }
        case .waiting:
            rect(4, 6, 5, 10, ink); rect(10, 6, 11, 10, ink)
        case .done:
            line([(4, 9), (5, 8), (6, 7), (7, 8), (8, 9)].filter { _ in false })
            line([(4, 9), (5, 8), (6, 9), (9, 9), (10, 8), (11, 9)])
        case .error:
            line([(4, 6), (6, 6), (5, 7), (4, 8), (6, 8), (9, 6), (11, 6), (10, 7), (9, 8), (11, 8)])
        }

        // accesorios sobre la cabeza
        let acc = Pal.cream
        switch s {
        case .starting:
            let n = (t / 2) % 9
            for i in 0..<8 { put(4 + i, 1, i < n ? Pal.body : Pal.dark, shift: false) }
        case .thinking:
            let n = (t / 3) % 4
            for i in 0..<3 where i < n { put(5 + i * 3, 1, acc, shift: false) }
        case .tool:
            if t % 2 == 0 { put(13, 2, Pal.light, shift: false); put(14, 1, Pal.light, shift: false) }
            else { put(14, 2, Pal.light, shift: false); put(13, 1, Pal.light, shift: false) }
        case .waiting:
            if t % 6 < 4 {
                for x in 7...8 { put(x, 0, acc, shift: false); put(x, 1, acc, shift: false); put(x, 3, acc, shift: false) }
            }
        case .done:
            for (x, y) in [(6, 2), (7, 3), (8, 2), (9, 1), (10, 0)] { put(x, y, acc, shift: false) }
        case .error:
            let f = t % 4
            for (x, y) in [(7, 1 + f % 2), (8, 2 - f % 2), (7, 3)] { put(x, y, Pal.dark, shift: false) }
        default: break
        }
        return out + peerOverlay(cue, tick: t)
    }
}
