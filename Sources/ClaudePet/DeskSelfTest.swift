import Foundation
import CoreGraphics

/// `ClaudePet --selftest-desk`: como camina, donde se queda y cuando vuelve a la isla la mascota del escritorio.
enum DeskSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 860)

        var p = CGPoint(x: 200, y: 200), moving = false
        for _ in 0..<5 * 30 { let r = DeskMotion.follow(from: p, mouse: CGPoint(x: 1000, y: 600), dt: 1.0 / 30, moving: moving); p = r.point; moving = r.moving }
        check("alcanza al cursor sin taparlo", abs(hypot(1000 - p.x, 600 - p.y) - DeskMotion.stopFollowing) < 14)
        check("al llegar se detiene", !moving)
        let near = DeskMotion.follow(from: CGPoint(x: 500, y: 500), mouse: CGPoint(x: 560, y: 500), dt: 0.033, moving: false)
        check("con el cursor cerca no se mueve", near.point == CGPoint(x: 500, y: 500) && !near.moving)
        let hysteresis = DeskMotion.follow(from: CGPoint(x: 500, y: 500), mouse: CGPoint(x: 500 + 200, y: 500), dt: 0.033, moving: false)
        check("a 200 pt todavia no echa a andar (histeresis)", !hysteresis.moving)
        let keeps = DeskMotion.follow(from: CGPoint(x: 500, y: 500), mouse: CGPoint(x: 500 + 200, y: 500), dt: 0.033, moving: true)
        check("pero si ya andaba, sigue hasta la distancia de parada", keeps.moving && keeps.point.x > 500)
        var maxStep: CGFloat = 0, q = CGPoint(x: 0, y: 0), m = false
        for _ in 0..<60 { let r = DeskMotion.follow(from: q, mouse: CGPoint(x: 2000, y: 0), dt: 1.0 / 30, moving: m); maxStep = max(maxStep, hypot(r.point.x - q.x, r.point.y - q.y)); q = r.point; m = r.moving }
        check("nunca va mas rapido que su velocidad", maxStep <= DeskMotion.speed / 30 + 0.01)
        check("sin tiempo no se mueve", DeskMotion.follow(from: CGPoint(x: 0, y: 0), mouse: CGPoint(x: 900, y: 0), dt: 0, moving: true).point == CGPoint(x: 0, y: 0))

        check("dentro de la pantalla se queda donde esta", DeskMotion.clamp(CGPoint(x: 700, y: 400), in: [screen]) == CGPoint(x: 700, y: 400))
        let off = DeskMotion.clamp(CGPoint(x: 5000, y: -300), in: [screen])
        check("fuera de la pantalla vuelve al borde", off.x == screen.maxX - DeskMotion.size / 2 && off.y == screen.minY + DeskMotion.size / 2)
        let two = [screen, CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        check("con dos pantallas puede cruzar a la otra", DeskMotion.clamp(CGPoint(x: 2000, y: 500), in: two) == CGPoint(x: 2000, y: 500))
        check("sin pantallas no se toca", DeskMotion.clamp(CGPoint(x: 5, y: 5), in: []) == CGPoint(x: 5, y: 5))

        check("soltarla sobre la isla la devuelve", DeskMotion.returnsToIsland(CGPoint(x: 720, y: 840), screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))
        check("soltarla en medio de la pantalla no", !DeskMotion.returnsToIsland(CGPoint(x: 720, y: 400), screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))
        check("soltarla arriba pero lejos del centro no", !DeskMotion.returnsToIsland(CGPoint(x: 100, y: 880), screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))

        let saved = DeskMotion.encode(["claude": CGPoint(x: 300.5, y: 120), "codex": CGPoint(x: -40, y: 800)])
        let back = DeskMotion.decode(saved)
        check("guarda y recupera las posiciones", back["claude"] == CGPoint(x: 300.5, y: 120) && back["codex"] == CGPoint(x: -40, y: 800))
        check("descarta claves raras y numeros imposibles", DeskMotion.decode(#"{"otra":[1,2],"claude":[1e12,2],"codex":[1]}"#).isEmpty)
        check("descarta basura", DeskMotion.decode("no es json").isEmpty && DeskMotion.decode(String(repeating: "x", count: 1000)).isEmpty)

        print(failures == 0 ? "ESCRITORIO OK" : "ESCRITORIO \(failures) FALLOS")
        return failures == 0
    }
}
