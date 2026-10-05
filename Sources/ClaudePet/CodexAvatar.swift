import SwiftUI

/// Avatar de Codex: robot-nube azul con visor oscuro que muestra `>_` en cian y un `>-` en el pecho.
/// Pixel art propio (rejilla de 18 x 21), dibujado por el escenario del partido y reutilizable.
/// Leyenda: O contorno, B azul, D sombra, L luz, W parche del pecho, s borde del visor, S visor, C glifo cian.
enum CodexAvatar {
    static let width = 18
    static let height = 21
    private static let bodyOffset = 11      // fila de la cabeza donde empieza el cuerpo

    enum Legs: Equatable { case stand, step, kick }
    enum Arms: Equatable { case rest, wave(Bool), salute, celebrate }
    /// Lo que muestra el visor. `dots(n)`: n puntos (pensando); `typing(k)`: `>_` con el cursor en movimiento;
    /// `alert`: `!` naranja (espera tu aprobacion); `cross`: `x x` (error).
    enum Face: Equatable { case prompt(cursor: Bool), happy, dots(Int), typing(Int), alert(on: Bool), cross }
    /// Globo de atencion sobre la cabeza: lo que Codex piensa de lo que hace Claude.
    enum Emote: Equatable { case dots(Int), bang, question, check }

    static let head: [String] = [
        ".....OOOOOOOO.....",
        "..OLOOBBBBBBOOOO..",
        ".OLLBBBBBBBBBBBBO.",
        ".OLBBssssssssBBBO.",
        "OLBBsSSSSSSSSsBBBO",
        "OLBBsSSSSSSSSsBBBO",
        "OBBBsSSSSSSSSsBBBO",
        "OBBBsSSSSSSSSsBBBO",
        "OBBBsSSSSSSSSsBBBO",
        ".OBBBssssssssBBBO.",
        "..ODDDDDDDDDDDDO..",
        "...OOOOOOOOOOOO...",
    ]

    static let bodyStand: [String] = [
        ".....OOOOOOOO.....",
        "..OOOBBBBBBBBOOO..",
        "..OBBBBCWWWBBBBO..",
        "..ODDBBWCWWBBDDO..",
        "..OOODBCWCCBDOOO..",
        ".....OBDOODBO.....",
        ".....OBO..OBO.....",
        ".....ODO..ODO.....",
        ".....OOO..OOO.....",
        "..................",
    ]

    static let bodyStep: [String] = [
        ".....OOOOOOOO.....",
        "..OOOBBBBBBBBOOO..",
        "..OBBBBCWWWBBBBO..",
        "..ODDBBWCWWBBDDO..",
        "..OOODBCWCCBDOOO..",
        ".....OBDOODBO.....",
        ".....ODO..OBO.....",
        ".....OOO..ODO.....",
        "..........OOO.....",
        "..................",
    ]

    static let bodyKick: [String] = [
        ".....OOOOOOOO.....",
        "..OOOBBBBBBBBOOO..",
        "..OBBBBCWWWBBBBO..",
        "..ODDBBWCWWBBDDO..",
        "..OOODBCWCCBDOOO..",
        ".....OBDOODBO.....",
        ".....OBO..ODDOOO..",
        ".....ODO..OOOOOO..",
        ".....OOO..........",
        "..................",
    ]

    static func color(_ c: Character, skin: CodexSkin = .cloud) -> Color? {
        let palette: (outline: UInt32, body: UInt32, shade: UInt32, light: UInt32, patch: UInt32) = switch skin {
        case .cloud: (0x223496, 0x5270E8, 0x3E5ACE, 0x7E98FF, 0x6E8CF5)
        case .mint: (0x17645F, 0x35B7A1, 0x238F82, 0x7FE5CF, 0x55CDB8)
        case .violet: (0x482476, 0x8A57D8, 0x673BB2, 0xC49BFF, 0xA979F2)
        }
        switch c {
        case "O": return Color(hex: palette.outline)
        case "B": return Color(hex: palette.body)
        case "D": return Color(hex: palette.shade)
        case "L": return Color(hex: palette.light)
        case "W": return Color(hex: palette.patch)
        case "s": return Color(hex: 0x2C346E)
        case "S": return Color(hex: 0x161B40)
        case "C": return Color(hex: 0x96EBFF)
        default: return nil
        }
    }

    /// Celdas a pintar, de atras hacia delante: cuerpo, cabeza y glifo del visor.
    static func cells(legs: Legs, face: Face, skin: CodexSkin = .cloud) -> [(x: Int, y: Int, c: Color)] {
        var out: [(x: Int, y: Int, c: Color)] = []
        let body: [String]
        switch legs { case .stand: body = bodyStand; case .step: body = bodyStep; case .kick: body = bodyKick }
        for (y, row) in body.enumerated() { for (x, ch) in row.enumerated() { if let c = color(ch, skin: skin) { out.append((x, y + bodyOffset, c)) } } }
        for (y, row) in head.enumerated() { for (x, ch) in row.enumerated() { if let c = color(ch, skin: skin) { out.append((x, y, c)) } } }
        let cyan = color("C", skin: skin)!, orange = Color(hex: 0xE0824F), coral = Color(hex: 0xFF8A7A)
        var glyph: [(Int, Int)] = []
        var tint = cyan
        switch face {
        case .prompt(let cursor): glyph = [(6, 5), (7, 6), (6, 7)] + (cursor ? [(9, 7), (10, 7), (11, 7)] : [])
        case .happy: glyph = [(6, 6), (7, 5), (8, 6), (10, 6), (11, 5), (12, 6)]
        case .dots(let n): glyph = [(6, 6), (8, 6), (10, 6)].prefix(max(0, min(3, n))).map { $0 }
        case .typing(let k): glyph = [(6, 5), (7, 6), (6, 7)] + [(9 + k % 3, 7), (10 + k % 3, 7)]
        case .alert(let on): if on { glyph = [(8, 4), (9, 4), (8, 5), (9, 5), (8, 6), (9, 6), (8, 8), (9, 8)]; tint = orange }
        case .cross: glyph = [(6, 5), (8, 5), (7, 6), (6, 7), (8, 7), (10, 5), (12, 5), (11, 6), (10, 7), (12, 7)]; tint = coral
        }
        for (x, y) in glyph { out.append((x, y, tint)) }
        return out
    }

    static func armCells(_ arms: Arms, skin: CodexSkin) -> [(x: Int, y: Int, c: Color)] {
        let body = color("B", skin: skin)!
        let light = color("L", skin: skin)!
        func pixels(_ points: [(Int, Int)]) -> [(Int, Int, Color)] { points.map { ($0.0, $0.1, body) } }
        switch arms {
        case .rest:
            return []
        case .wave(let high):
            return pixels(high ? [(15, 14), (16, 13), (16, 12), (16, 11), (17, 10)] : [(15, 14), (16, 14), (16, 13), (17, 12)])
        case .salute:
            return pixels([(4, 14), (5, 13), (6, 12), (7, 11), (8, 10), (9, 10)]) + [(10, 10, light)]
        case .celebrate:
            return pixels([(3, 14), (2, 13), (2, 12), (2, 11), (2, 10), (15, 14), (16, 13), (16, 12), (16, 11), (16, 10)])
        }
    }

    /// Celdas del globo (y negativa = por encima de la cabeza).
    static func emote(_ e: Emote) -> [(x: Int, y: Int, c: Color)] {
        let cream = Color(hex: 0xEDE3DA), orange = Color(hex: 0xE0824F)
        switch e {
        case .dots(let n): return [(6, -3), (8, -3), (10, -3)].prefix(max(0, min(3, n))).map { ($0.0, $0.1, cream) }
        case .bang: return [(8, -6), (9, -6), (8, -5), (9, -5), (8, -4), (9, -4), (8, -2), (9, -2)].map { ($0.0, $0.1, orange) }
        case .question: return [(7, -5), (8, -6), (9, -6), (10, -5), (9, -4), (8, -3), (8, -1)].map { ($0.0, $0.1, cream) }
        case .check: return [(6, -3), (7, -2), (8, -3), (9, -4), (10, -5)].map { ($0.0, $0.1, cream) }
        }
    }
}
