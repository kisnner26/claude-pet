import SwiftUI

/// Avatar de Codex: robot-nube azul con visor oscuro que muestra `>_` en cian y un `>-` en el pecho.
/// Pixel art propio (rejilla de 18 x 21), dibujado por el escenario del partido y reutilizable.
/// Leyenda: O contorno, B azul, D sombra, L luz, W parche del pecho, s borde del visor, S visor, C glifo cian.
enum CodexAvatar {
    static let width = 18
    static let height = 21
    private static let bodyOffset = 11      // fila de la cabeza donde empieza el cuerpo

    enum Legs { case stand, step, kick }
    enum Face { case prompt(cursor: Bool), happy }

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

    static func color(_ c: Character) -> Color? {
        switch c {
        case "O": return Color(hex: 0x223496)
        case "B": return Color(hex: 0x5270E8)
        case "D": return Color(hex: 0x3E5ACE)
        case "L": return Color(hex: 0x7E98FF)
        case "W": return Color(hex: 0x6E8CF5)
        case "s": return Color(hex: 0x2C346E)
        case "S": return Color(hex: 0x161B40)
        case "C": return Color(hex: 0x96EBFF)
        default: return nil
        }
    }

    /// Celdas a pintar, de atras hacia delante: cuerpo, cabeza y glifo del visor.
    static func cells(legs: Legs, face: Face) -> [(x: Int, y: Int, c: Color)] {
        var out: [(x: Int, y: Int, c: Color)] = []
        let body: [String]
        switch legs { case .stand: body = bodyStand; case .step: body = bodyStep; case .kick: body = bodyKick }
        for (y, row) in body.enumerated() { for (x, ch) in row.enumerated() { if let c = color(ch) { out.append((x, y + bodyOffset, c)) } } }
        for (y, row) in head.enumerated() { for (x, ch) in row.enumerated() { if let c = color(ch) { out.append((x, y, c)) } } }
        let cyan = color("C")!
        let glyph: [(Int, Int)]
        switch face {
        case .prompt(let cursor): glyph = [(6, 5), (7, 6), (6, 7)] + (cursor ? [(9, 7), (10, 7), (11, 7)] : [])
        case .happy: glyph = [(6, 6), (7, 5), (8, 6), (10, 6), (11, 5), (12, 6)]
        }
        for (x, y) in glyph { out.append((x, y, cyan)) }
        return out
    }
}
