import SwiftUI
import AppKit

/// Atuendos pixel-art propios para la mascota de claude. Son capas sobre la rejilla 16x16 del bloque:
/// se dibujan encima del cuerpo, siguen sus saltos y nunca usan el color de los ojos.
/// A cual de las dos mascotas se refiere una eleccion (atuendos, ajustes).
enum PetAgent: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
}

enum Outfit: String, CaseIterable, Identifiable {
    case beanie = "gorro", crown = "corona", glasses = "gafas", scarf = "bufanda", headphones = "audifonos", bow = "lazo"
    // los que pide el tiempo: se ponen solos, pero tambien se pueden elegir
    case sunglasses = "gafas de sol", sunhat = "sombrero", umbrella = "paraguas", earmuffs = "orejeras"
    var id: String { rawValue }
    var title: String { rawValue }

    /// Pixel-art dibujado en ASCII sobre la rejilla 16x16 del bloque. Una letra = un color de la paleta del atuendo; `.` = nada.
    /// Las celdas de los ojos (filas 6 a 10, columnas 4 a 6 y 9 a 11) se dejan vacias para que la mirada siga viendose.
    struct Art {
        let y0: Int
        let rows: [String]
        let palette: [Character: UInt32]
        func cells() -> [(x: Int, y: Int, c: Color)] {
            var out: [(Int, Int, Color)] = []
            for (r, row) in rows.enumerated() { for (x, ch) in row.enumerated() { if let hex = palette[ch] { out.append((x, y0 + r, Color(hex: hex))) } } }
            return out
        }
    }

    var claudeArt: Art {
        switch self {
        case .beanie:
            // gorro de punto con pompon, vuelta a rayas y luz en un lado
            return Art(y0: 0, rows: [".......WW.......", "......wWWw......", "....rHHRRRRRr...", "...rHRRRRRRRRr..", "..WwWwWwWwWwWw.."],
                       palette: ["W": 0xF4EFE6, "w": 0xD2C8B4, "R": 0xC84B4B, "r": 0x9A3030, "H": 0xE86C6C])
        case .crown:
            return Art(y0: 0, rows: [".......YY.......", "....Y..GG..Y....", "....GG.GG.GG....", "...YGGGGGGGGg...", "...gRGGBBGGRg..."],
                       palette: ["Y": 0xFFE08A, "G": 0xE7B45B, "g": 0xB8862F, "R": 0xB3304A, "B": 0x4A7BD0])
        case .glasses:
            // dos lentes de cristal claro con destello, puente y patillas hasta las orejas
            return Art(y0: 5, rows: ["....NNN..NNN....", "...N.LLNNLL.N...", ".ttNL.LNNL.LNtt.", "...NLL.NN.LLN...", "...NL.L..L.LN...", "...N.LL..LL.N...", "....NNN..NNN...."],
                       palette: ["N": 0x1F2740, "t": 0x1F2740, "W": 0xFFFFFF, "L": 0xF0BC98])
        case .scarf:
            // bufanda de rayas con nudo y un cabo colgando con flecos
            return Art(y0: 11, rows: ["..TTTTSTTTTSTT..", "..tttttSttttSt..", "...........Tt...", "...........Tt...", "...........SS..."],
                       palette: ["T": 0x3E8E8A, "t": 0x2C6B68, "S": 0xEDE3DA])
        case .headphones:
            return Art(y0: 2, rows: [".....DMMMMD.....", "....DH....HD....", "...DH......HD...", "..DM........MD..", "DMH..........HMD", "DMM..........MMD", "DAM..........MAD", "DMM..........MMD", ".DD..........DD."],
                       palette: ["D": 0x2E323D, "M": 0x565D6E, "H": 0x8A93A8, "A": 0xE86A6A])
        case .bow:
            return Art(y0: 2, rows: ["........PP..PP..", ".......PHPppPHP.", "........PP..PP.."],
                       palette: ["P": 0xE58BB0, "p": 0xC4668E, "H": 0xFFC2DA])
        case .sunglasses:
            return Art(y0: 6, rows: ["..KKKKKKKKKKKK..", "..KLKKK..KLKKK..", "..KKKKK..KKKKK..", "...KKK....KKK..."],
                       palette: ["K": 0x1B1F2E, "L": 0x7C8BB8])
        case .sunhat:
            return Art(y0: 0, rows: ["......hhhh......", "....hhYYYYhh....", "...hYYYYYYYYh...", "..hhRRRRRRRRhh..", "hhhhhhhhhhhhhhhh"],
                       palette: ["h": 0xD9B26A, "Y": 0xF0D58C, "R": 0xC84B4B])
        case .umbrella:
            return Art(y0: 0, rows: ["......bbbb......", "...bbBBBBBBbb...", "..bBBwBBBBwBBb..", ".bBBBBBBBBBBBBb.", "......bbbb......"],
                       palette: ["b": 0x2F5FA8, "B": 0x4F86D9, "w": 0xCFE3FF])
        case .earmuffs:
            return Art(y0: 2, rows: ["....GGGGGGGG....", "...G........G...", "..G..........G..", "PPG..........GPP", "PPP..........PPP", "PPP..........PPP", "PP............PP"],
                       palette: ["G": 0x8A93A8, "P": 0xF2C6D8])
        }
    }

    /// Pixeles del atuendo con el cuerpo en reposo.
    var pixels: [Px] {
        let out = claudeArt.cells().map { Px(x: $0.x, y: $0.y, c: $0.c) }
        // si una forma pisa a otra en la misma celda, gana la ultima; asi no quedan pixeles dobles
        var seen: [String: Int] = [:], unique: [Px] = []
        for p in out {
            let key = "\(p.x),\(p.y)"
            if let i = seen[key] { unique[i] = p } else { seen[key] = unique.count; unique.append(p) }
        }
        return unique
    }

    /// Va debajo de los ojos: se dibuja antes que ellos para que la mirada siga viendose.
    var underEyes: Bool { self == .glasses }
}

extension Outfit {
    /// El mismo atuendo sobre el avatar de codex (rejilla 18x21, cabeza en las filas 0 a 11, visor en 3 a 9).
    /// Se pinta encima de la cabeza y debajo del glifo del visor, asi el `>_` sigue viendose.
    var codexArt: Art {
        switch self {
        case .beanie:
            return Art(y0: 0, rows: [".....rHRRRRRr.....", "...rHHRRRRRRRRr...", "..rHRRRRRRRRRRRr..", ".WwWwWwWwWwWwWwWw."],
                       palette: ["W": 0xF4EFE6, "w": 0xD2C8B4, "R": 0xC84B4B, "r": 0x9A3030, "H": 0xE86C6C])
        case .crown:
            return Art(y0: 0, rows: [".....Y..YY..Y.....", "....YGG.GG.GGY....", "...gGGGGGGGGGGg...", "..gRGGBGGGGBGGRg.."],
                       palette: ["Y": 0xFFE08A, "G": 0xE7B45B, "g": 0xB8862F, "R": 0xB3304A, "B": 0x4A7BD0])
        case .glasses:
            // montura clara alrededor del visor, con puente en el centro, destellos y patillas
            return Art(y0: 3, rows: [".....FFFFFFFF.....", "....F...F....F....", "....F...F....F....", "..FFF...F....FFF..", "....F...F....F....", "....F...F....F....", ".....FFFFFFFF....."],
                       palette: ["F": 0xF2D8B0, "W": 0xFFFFFF])
        case .scarf:
            return Art(y0: 12, rows: ["...TTTTSTTTTSTT...", "...tttttSttttSt...", "............Tt....", "............Tt....", "............SS...."],
                       palette: ["T": 0x3E8E8A, "t": 0x2C6B68, "S": 0xEDE3DA])
        case .headphones:
            return Art(y0: 0, rows: [".....DMMMMMMD.....", "....DH......HD....", "...DH........HD...", "..DM..........MD..", "DMH............HMD", "DMM............MMD", "DAM............MAD", "DMM............MMD", ".DD............DD."],
                       palette: ["D": 0x2E323D, "M": 0x565D6E, "H": 0x8A93A8, "A": 0xE86A6A])
        case .bow:
            return Art(y0: 0, rows: ["........PP....PP..", "........PHPppPHP..", "........PP....PP.."],
                       palette: ["P": 0xE58BB0, "p": 0xC4668E, "H": 0xFFC2DA])
        case .sunglasses:
            // montura oscura y gruesa alrededor del visor, con destellos
            return Art(y0: 3, rows: ["....KKKKKKKKKK....", "...KK........KK...", "..KKW........WKK..", "...K..........K...", "...K..........K...", "...KK........KK...", "....KKKKKKKKKK...."],
                       palette: ["K": 0x1B1F2E, "W": 0x9DB0E0])
        case .sunhat:
            return Art(y0: 0, rows: [".......hhhh.......", "....hhhYYYYhhh....", "...hYYYYYYYYYYh...", "..hhRRRRRRRRRRhh..", "hhhhhhhhhhhhhhhhhh"],
                       palette: ["h": 0xD9B26A, "Y": 0xF0D58C, "R": 0xC84B4B])
        case .umbrella:
            return Art(y0: 0, rows: [".......bbbb.......", "....bbBBBBBBbb....", "..bBBBwBBBBwBBBb..", ".bBBBBBBBBBBBBBBb.", ".......bbbb......."],
                       palette: ["b": 0x2F5FA8, "B": 0x4F86D9, "w": 0xCFE3FF])
        case .earmuffs:
            return Art(y0: 0, rows: [".....GGGGGGGG.....", "....G........G....", "...G..........G...", "..G............G..", "PPG............GPP", "PPP............PPP", "PPP............PPP", "PPP............PPP", ".PP............PP."],
                       palette: ["G": 0x8A93A8, "P": 0xF2C6D8])
        }
    }

    var codexCells: [(x: Int, y: Int, c: Color)] { codexArt.cells() }
}

enum Wardrobe {
    /// Desplazamiento del cuerpo del bloque segun estado y cuadro (el mismo que usa `Sprite.block`).
    static func bodyShift(_ state: PetState, tick t: Int) -> (dx: Int, dy: Int) {
        switch state {
        case .done: return (0, t % 8 < 2 ? -1 : 0)
        case .error: return (t % 2 == 0 ? 1 : -1, 0)
        case .waiting: return (0, t % 6 < 3 ? 0 : -1)
        default: return (0, 0)
        }
    }

    static func pixels(_ outfits: Set<Outfit>, state: PetState, tick: Int) -> [Px] {
        let s = bodyShift(state, tick: tick)
        // orden fijo: lo de abajo primero, para que el resultado no dependa del orden del conjunto
        return Outfit.allCases.filter(outfits.contains).flatMap { $0.pixels }.map { Px(x: $0.x + s.dx, y: $0.y + s.dy, c: $0.c) }
    }

    /// Mezcla el sprite con los atuendos: los de "debajo de los ojos" se insertan antes del primer pixel de ojo.
    static func compose(_ base: [Px], outfits: Set<Outfit>, state: PetState, tick: Int) -> [Px] {
        guard !outfits.isEmpty else { return base }
        let under = pixels(outfits.filter(\.underEyes), state: state, tick: tick)
        let over = pixels(outfits.filter { !$0.underEyes }, state: state, tick: tick)
        var out = base
        let firstEye = out.firstIndex { $0.c == Pal.charcoal } ?? out.count
        out.insert(contentsOf: under, at: firstEye)
        return out + over
    }

    /// Celdas de los atuendos para el avatar de codex, en un orden fijo.
    static func codexCells(_ outfits: Set<Outfit>) -> [(x: Int, y: Int, c: Color)] {
        Outfit.allCases.filter(outfits.contains).flatMap(\.codexCells)
    }

    /// Atuendos de temporada: gorro de fin de año y bufanda en invierno. nil fuera de temporada.
    static func seasonal(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Set<Outfit> {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return [] }
        if (m == 12 && d >= 20) || (m == 1 && d <= 6) { return [.beanie, .scarf] }
        if m == 12 || m == 1 || m == 2 { return [.scarf] }
        return []
    }

    /// Persistencia como texto separado por comas, validando cada nombre.
    static func encode(_ outfits: Set<Outfit>) -> String { Outfit.allCases.filter(outfits.contains).map(\.rawValue).joined(separator: ",") }
    static func decode(_ text: String) -> Set<Outfit> { Set(text.split(separator: ",").compactMap { Outfit(rawValue: String($0)) }) }
}
