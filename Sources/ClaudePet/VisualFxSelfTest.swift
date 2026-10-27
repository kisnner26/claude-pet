import Foundation
import CoreGraphics

/// `ClaudePet --selftest-fx`: el nucleo puro de los efectos visuales (pulso, reloj, liquido, escenarios, lluvia, evolucion, trailer, duo).
enum VisualFxSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        func unit(_ p: [FxPixel]) -> Bool { p.allSatisfy { (-0.05...1.05).contains($0.x) && (-0.05...1.05).contains($0.y) && $0.alpha >= 0 && $0.alpha <= 1 } }

        // pulso de alerta
        let rings = AlertPulse.rings(at: 3.3)
        check("hay tres ondas desfasadas y dentro de 0...1", rings.count == 3 && Set(rings.map { Int($0.progress * 100) }).count == 3 && rings.allSatisfy { (0...1).contains($0.progress) && (0...0.56).contains($0.alpha) })
        check("una onda se apaga al alejarse", AlertPulse.rings(at: 0.0).max { $0.progress < $1.progress }!.alpha < AlertPulse.rings(at: 0.0).min { $0.progress < $1.progress }!.alpha)
        let asked = Date(timeIntervalSince1970: 1000)
        check("la cuenta atras del permiso baja de 1 a 0 en 110 s", AlertPulse.remaining(since: asked, now: asked) == 1 && abs(AlertPulse.remaining(since: asked, now: asked.addingTimeInterval(55)) - 0.5) < 0.001 && AlertPulse.remaining(since: asked, now: asked.addingTimeInterval(500)) == 0)
        check("el color sigue al riesgo", AlertPulse.riskColor(.low) != AlertPulse.riskColor(.medium) && AlertPulse.riskColor(.high) == 0xD85C5C)

        // reloj de arena
        func sand(_ top: Double) -> [FxPixel] { Hourglass.pixels(top: top).filter { $0.color == 0xE7B45B } }
        check("el reloj cabe en su rejilla", Hourglass.pixels(top: 0.5).allSatisfy { $0.x >= 0 && $0.x < 9 && $0.y >= 0 && $0.y < 13 })
        check("recien girado la arena esta arriba y vacio abajo", sand(1).filter { $0.y <= 5 }.count > sand(1).filter { $0.y >= 8 }.count && sand(0).filter { $0.y <= 5 }.isEmpty)
        check("la arena de arriba baja y la de abajo sube con el tiempo", sand(0.2).filter { $0.y <= 5 }.count < sand(0.8).filter { $0.y <= 5 }.count && sand(0.2).filter { $0.y >= 8 }.count > sand(0.8).filter { $0.y >= 8 }.count)
        check("el hilo de arena solo cae mientras corre", sand(0.5).contains { $0.x == 4 && $0.y == 6 } && !sand(0).contains { $0.y == 6 } && !sand(1).contains { $0.y == 6 })

        // liquido
        check("el nivel es la fraccion usada, acotada", LiquidModel.level(used: 80, compactAt: 160) == 0.5 && LiquidModel.level(used: 500, compactAt: 160) == 1 && LiquidModel.level(used: 5, compactAt: 0) == 0)
        check("el color sigue la presion del contexto", LiquidModel.colorHex(.normal) == 0x2966ED && LiquidModel.colorHex(.critical) == 0xD85C5C)
        check("trabajando hay mas olas que en reposo", LiquidModel.amplitude(.tool) > LiquidModel.amplitude(.idle))
        let low = LiquidModel.surface(at: 3, level: 0.2, amplitude: 4, width: 600, height: 200), high = LiquidModel.surface(at: 3, level: 0.8, amplitude: 4, width: 600, height: 200)
        let lowMean: Double = low.map { Double($0.y) }.reduce(0, +) / Double(low.count), highMean: Double = high.map { Double($0.y) }.reduce(0, +) / Double(high.count)
        let inCanvas = (low + high).allSatisfy { $0.y >= 0 && $0.y <= 200 && $0.x >= 0 && $0.x <= 600 }
        check("la superficie sube con el nivel y nunca sale del lienzo", highMean < lowMean && inCanvas)
        check("las olas se mueven con el tiempo", LiquidModel.surface(at: 1, level: 0.5, amplitude: 4, width: 600, height: 200) != LiquidModel.surface(at: 1.7, level: 0.5, amplitude: 4, width: 600, height: 200))
        check("a nivel 1 con amplitud no se sale por arriba", LiquidModel.surface(at: 2, level: 1, amplitude: 6, width: 600, height: 200).allSatisfy { $0.y >= 0 })

        // escenarios
        for st in PetState.allCases {
            let a = StageScene.particles(at: 4.2, state: st, hour: 23), b = StageScene.particles(at: 4.2, state: st, hour: 23)
            check("el escenario de \(st.rawValue) es determinista y cabe en la caja", a == b && unit(a))
        }
        check("el error trae lluvia y nube", StageScene.particles(at: 2, state: .error, hour: 12).count > 8)
        check("terminar trae sol con rayos", StageScene.particles(at: 2, state: .done, hour: 12).contains { $0.color == 0xFFD166 })
        check("ejecutar suelta chispas que se apagan", StageScene.particles(at: 2, state: .tool, hour: 12).allSatisfy { $0.color == 0xFF9F43 } && StageScene.particles(at: 2, state: .tool, hour: 12).count == 8)
        check("de noche en reposo hay estrellas y de dia no", !StageScene.particles(at: 1, state: .idle, hour: 23).isEmpty && !StageScene.particles(at: 1, state: .idle, hour: 3).isEmpty && StageScene.particles(at: 1, state: .idle, hour: 14).isEmpty)
        check("las estrellas titilan", StageScene.particles(at: 1, state: .idle, hour: 23) != StageScene.particles(at: 1.9, state: .idle, hour: 23))

        // lluvia de lineas
        check("sin cambios o fuera de ventana no cae nada", LineRain.drops(at: 5, since: 0, added: 10, deleted: 2).isEmpty && LineRain.drops(at: 1, since: 0, added: 0, deleted: 0).isEmpty && LineRain.drops(at: 0.5, since: 1, added: 5, deleted: 5).isEmpty)
        let rain = LineRain.drops(at: 1.2, since: 0, added: 30, deleted: 10)
        let greenDrops = rain.filter { $0.color == 0x6CCB8A }.count, redDrops = rain.filter { $0.color == 0xD85C5C }.count
        check("cae verde y rojo en proporcion a lo añadido y quitado", !rain.isEmpty && greenDrops > redDrops && unit(rain))
        let fewDrops = LineRain.drops(at: 1.8, since: 0, added: 2, deleted: 0).count, manyDrops = LineRain.drops(at: 1.8, since: 0, added: 80, deleted: 40).count, hugeDrops = LineRain.drops(at: 1.8, since: 0, added: 5000, deleted: 5000).count
        check("a mas lineas, mas gotas, con un tope", fewDrops <= manyDrops && hugeDrops <= 24)
        let c0 = LineRain.counters(age: 0, added: 40, deleted: 8), c1 = LineRain.counters(age: 0.6, added: 40, deleted: 8), c2 = LineRain.counters(age: 2, added: 40, deleted: 8)
        check("los contadores suben y llegan al total", c0.added == 0 && c0.deleted == 0 && c1.added > 20 && c2.added == 40 && c2.deleted == 8)

        // evolucion
        let tiers = [1, 3, 5, 8, 99].map { Evolution.tier(level: $0) }
        check("los niveles pasan a etapas", tiers == [0, 1, 2, 3, 3])
        let orbitCounts: [Int] = (0...3).map { Evolution.orbit(at: 2, tier: $0).count }
        check("cada etapa suma una estrella en orbita y mas aura", orbitCounts == [0, 1, 2, 3] && Evolution.auraAlpha(tier: 3) > Evolution.auraAlpha(tier: 1) && Evolution.auraAlpha(tier: 0) == 0)
        check("la orbita se mueve y cabe", Evolution.orbit(at: 1, tier: 3) != Evolution.orbit(at: 2, tier: 3) && unit(Evolution.orbit(at: 1, tier: 3)))
        let allUnlocked = Outfit.allCases.allSatisfy { Evolution.isUnlocked($0, level: 99) }
        let startOutfits = Outfit.allCases.filter { Evolution.isUnlocked($0, level: 1) }.count
        check("los atuendos se desbloquean por nivel", allUnlocked && startOutfits == 2 && !Evolution.isUnlocked(.crown, level: 5) && Evolution.isUnlocked(.crown, level: 6))

        // trailer
        let files = [Trailer.File(name: "a.swift", added: 10, deleted: 2), Trailer.File(name: "b.swift", added: 80, deleted: 5), Trailer.File(name: "c.md", added: 3, deleted: 0)]
        check("el trailer elige primero los archivos con mas cambios y como mucho cinco", Trailer.pick(files).first?.name == "b.swift" && Trailer.pick((0..<12).map { Trailer.File(name: "f\($0)", added: $0, deleted: 0) }).count == 5)
        check("empieza con una presentacion y termina en cuanto acaba", Trailer.frame(at: 0.1, files: files).phase == .intro && Trailer.frame(at: 3.5, files: files).phase == .finished)
        let fa = Trailer.frame(at: 0.5, files: files), fb = Trailer.frame(at: 1.6, files: files)
        var bothFiles = false
        if case .files = fa.phase, case .files = fb.phase { bothFiles = true }
        check("pasa por cada archivo con un zoom que crece", bothFiles && fa.zoom >= 1 && fa.zoom <= 1.08 && fb.caption != fa.caption)
        var monotonic = true, lastAdded = 0, lastDeleted = 0
        for k in 0..<300 { let f = Trailer.frame(at: Double(k) / 100, files: files); if f.added < lastAdded || f.deleted < lastDeleted { monotonic = false }; lastAdded = f.added; lastDeleted = f.deleted }
        check("los contadores nunca bajan durante el trailer", monotonic)
        check("el total final suma todos los archivos", Trailer.frame(at: 2.99, files: files).added > 85 && Trailer.frame(at: 3.2, files: files).added == 93 && Trailer.frame(at: 3.2, files: files).deleted == 7)
        check("sin archivos no hay trailer", Trailer.frame(at: 0.5, files: []).phase == .finished)

        // duo
        check("si ambos terminan casi juntos hay choque de manos", DuoScene.highFive(claudeDoneAt: 10, codexDoneAt: 13, now: 13.4) != nil && (DuoScene.highFive(claudeDoneAt: 10, codexDoneAt: 13, now: 13.7) ?? 0) > 0.1)
        check("el choque dura 1,4 s y no se repite", DuoScene.highFive(claudeDoneAt: 10, codexDoneAt: 13, now: 15) == nil && DuoScene.highFive(claudeDoneAt: 10, codexDoneAt: 13, now: 12) == nil)
        check("si uno termina mucho despues no hay choque", DuoScene.highFive(claudeDoneAt: 10, codexDoneAt: 30, now: 30.5) == nil && DuoScene.highFive(claudeDoneAt: nil, codexDoneAt: 30, now: 30.5) == nil)

        // isla liquida
        check("antes de empezar y despues de acabar no hay gotas", Gooey.blobs(age: 0).isEmpty && Gooey.blobs(age: Gooey.duration).isEmpty && Gooey.blobs(age: 5).isEmpty)
        let mid = Gooey.blobs(age: (Gooey.delay + Gooey.duration) / 2), early = Gooey.blobs(age: Gooey.delay + 0.02)
        check("a mitad de camino las gotas cuelgan mas que al principio", mid.count == 4 && (mid.map(\.drop).max() ?? 0) > (early.map(\.drop).max() ?? 0) && mid.allSatisfy { $0.drop >= 0 && $0.drop <= 26 && $0.radius > 2 && $0.radius < 10 && (0...1).contains($0.x) })
        check("las gotas son deterministas y se reparten a lo ancho", Gooey.blobs(age: 0.5) == Gooey.blobs(age: 0.5) && Set(mid.map { Int($0.x * 10) }).count >= 3)

        print(failures == 0 ? "EFECTOS OK" : "EFECTOS FALLOS: \(failures)")
        return failures == 0
    }
}
