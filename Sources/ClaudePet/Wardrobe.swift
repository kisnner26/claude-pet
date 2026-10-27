import SwiftUI
import AppKit

/// Atuendos pixel-art propios para la mascota de claude. Son capas sobre la rejilla 16x16 del bloque:
/// se dibujan encima del cuerpo, siguen sus saltos y nunca usan el color de los ojos.
enum Outfit: String, CaseIterable, Identifiable {
    case beanie = "gorro", crown = "corona", glasses = "gafas", scarf = "bufanda", headphones = "audifonos", bow = "lazo"
    var id: String { rawValue }
    var title: String { rawValue }

    private static let red = Color(hex: 0xC84B4B), gold = Color(hex: 0xE7B45B), ruby = Color(hex: 0xB3304A)
    private static let teal = Color(hex: 0x3E8E8A), tealDark = Color(hex: 0x2C6B68), navy = Color(hex: 0x3A4A66)
    private static let grey = Color(hex: 0x555B69), pink = Color(hex: 0xE58BB0), pinkDark = Color(hex: 0xC4668E)

    /// Pixeles del atuendo con el cuerpo en reposo.
    var pixels: [Px] {
        var out: [Px] = []
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Color) { for y in y0...y1 { for x in x0...x1 { out.append(Px(x: x, y: y, c: c)) } } }
        func put(_ x: Int, _ y: Int, _ c: Color) { out.append(Px(x: x, y: y, c: c)) }
        switch self {
        case .beanie:
            rect(5, 1, 10, 2, Self.red); rect(4, 2, 11, 2, Self.red); rect(3, 3, 12, 3, Pal.cream)
            rect(7, 0, 8, 0, Pal.cream)
        case .crown:
            rect(4, 3, 11, 3, Self.gold)
            for x in [4, 6, 9, 11] { put(x, 2, Self.gold) }
            put(7, 3, Self.ruby); put(8, 3, Self.ruby)
        case .glasses:
            // dos lentes con borde y puente; los ojos se ven dentro
            for x in 3...7 { put(x, 5, Self.navy); put(x, 10, Self.navy) }
            for x in 8...12 { put(x, 5, Self.navy); put(x, 10, Self.navy) }
            for y in 6...9 { put(3, y, Self.navy); put(7, y, Self.navy); put(8, y, Self.navy); put(12, y, Self.navy) }
        case .scarf:
            rect(3, 11, 12, 11, Self.teal); rect(3, 12, 12, 12, Self.tealDark)
            put(11, 13, Self.teal); put(11, 14, Self.tealDark)
        case .headphones:
            rect(4, 3, 11, 3, Self.grey); put(3, 4, Self.grey); put(12, 4, Self.grey)
            rect(1, 6, 2, 9, Self.grey); rect(13, 6, 14, 9, Self.grey)
        case .bow:
            rect(10, 2, 12, 3, Self.pink); put(11, 2, Self.pinkDark); put(11, 3, Self.pinkDark)
        }
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
        let eye = NSColor(Pal.charcoal).usingColorSpace(.sRGB)
        let firstEye = out.firstIndex { NSColor($0.c).usingColorSpace(.sRGB) == eye } ?? out.count
        out.insert(contentsOf: under, at: firstEye)
        return out + over
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
