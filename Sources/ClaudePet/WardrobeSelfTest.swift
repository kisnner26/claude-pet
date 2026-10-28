import SwiftUI

/// `ClaudePet --selftest-wardrobe`: los atuendos caben en la rejilla, no tapan la mirada y se guardan bien.
enum WardrobeSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        check("hay al menos seis atuendos", Outfit.allCases.count >= 6)
        let eye = NSColor(Pal.charcoal).usingColorSpace(.sRGB)
        for outfit in Outfit.allCases {
            let px = outfit.pixels
            check("\(outfit.rawValue): tiene pixeles y caben en la rejilla 16x16", !px.isEmpty && px.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) })
            check("\(outfit.rawValue): no usa el color de los ojos", px.allSatisfy { NSColor($0.c).usingColorSpace(.sRGB) != eye })
            check("\(outfit.rawValue): no tiene pixeles repetidos con colores distintos", Dictionary(grouping: px, by: { "\($0.x),\($0.y)" }).allSatisfy { $0.value.count == 1 || Set($0.value.map { "\($0.c)" }).count == 1 })
        }
        // la mirada sigue funcionando con cualquier atuendo puesto
        var allOn = Set(Outfit.allCases)
        let base = Sprite.block(.idle, tick: 3)
        let dressed = base + Wardrobe.pixels(allOn, state: .idle, tick: 3)
        var look = PetPose(); look.eyeDX = 1
        let moved = PetAnimator.apply(dressed, pose: look)
        check("con todos los atuendos los ojos siguen existiendo y se mueven", moved.filter { NSColor($0.c).usingColorSpace(.sRGB) == eye }.count == base.filter { NSColor($0.c).usingColorSpace(.sRGB) == eye }.count
              && moved.map { "\($0.x),\($0.y)" } != dressed.map { "\($0.x),\($0.y)" })
        check("las gafas se dibujan debajo de los ojos y no los tapan", {
            let composed = Wardrobe.compose(base, outfits: [.glasses, .crown], state: .idle, tick: 3)
            let isEye = { (p: Px) in NSColor(p.c).usingColorSpace(.sRGB) == eye }
            guard let firstEye = composed.firstIndex(where: isEye) else { return false }
            let glassesAfterEyes = composed[firstEye...].filter { p in Outfit.glasses.pixels.contains { $0.x == p.x && $0.y == p.y && !isEye(p) } && !Outfit.crown.pixels.contains { $0.x == p.x && $0.y == p.y } }
            return glassesAfterEyes.isEmpty && composed.count == base.count + Outfit.glasses.pixels.count + Outfit.crown.pixels.count
        }())
        // siguen al cuerpo
        let hop = Wardrobe.pixels([.crown], state: .done, tick: 0), rest = Wardrobe.pixels([.crown], state: .done, tick: 4)
        check("el atuendo sube con el cuerpo cuando salta", zip(hop, rest).allSatisfy { $0.y == $1.y - 1 })
        check("el atuendo tiembla con el cuerpo en error", Wardrobe.pixels([.bow], state: .error, tick: 0).first?.x != Wardrobe.pixels([.bow], state: .error, tick: 1).first?.x)
        allOn = []
        check("sin atuendos no se añade nada", Wardrobe.pixels(allOn, state: .idle, tick: 0).isEmpty)
        check("el orden del conjunto no cambia el dibujo", Wardrobe.pixels([.beanie, .scarf], state: .idle, tick: 0).map { "\($0.x),\($0.y)" } == Wardrobe.pixels([.scarf, .beanie], state: .idle, tick: 0).map { "\($0.x),\($0.y)" })

        // persistencia y temporada
        check("se guardan y recuperan", Wardrobe.decode(Wardrobe.encode([.crown, .glasses])) == [.crown, .glasses])
        check("un valor desconocido se ignora", Wardrobe.decode("gorro,fantasma,<script>") == [.beanie])
        check("un texto vacio es vestuario vacio", Wardrobe.decode("").isEmpty)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: m, day: d, hour: 12))! }
        check("fin de año: gorro y bufanda", Wardrobe.seasonal(on: day(12, 25), calendar: cal) == [.beanie, .scarf] && Wardrobe.seasonal(on: day(1, 3), calendar: cal) == [.beanie, .scarf])
        check("invierno: solo bufanda", Wardrobe.seasonal(on: day(2, 10), calendar: cal) == [.scarf])
        check("fuera de temporada no hay nada", Wardrobe.seasonal(on: day(10, 27), calendar: cal).isEmpty)

        // avatar de codex: rejilla 18x21, cabeza en las filas 0...11
        for outfit in Outfit.allCases {
            let cells = outfit.codexCells
            check("codex \(outfit.title): tiene celdas y caben en la rejilla 18x21", !cells.isEmpty && cells.allSatisfy { $0.x >= 0 && $0.x < CodexAvatar.width && $0.y >= 0 && $0.y < CodexAvatar.height })
        }
        let bare = CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true))
        let glasses = CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true), outfits: [.glasses])
        check("codex: sin atuendos no se añade nada", CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true), outfits: []).count == bare.count)
        check("codex: el atuendo se pinta antes del glifo, que sigue encima", glasses.count > bare.count && glasses.last.map { l in bare.last.map { $0.x == l.x && $0.y == l.y } ?? false } == true)
        check("codex: el orden del conjunto no cambia el dibujo", Wardrobe.codexCells([.bow, .crown, .scarf]).map { "\($0.x),\($0.y)" } == Wardrobe.codexCells([.scarf, .bow, .crown]).map { "\($0.x),\($0.y)" })
        print(failures == 0 ? "ATUENDOS OK" : "ATUENDOS FALLOS: \(failures)")
        return failures == 0
    }
}
