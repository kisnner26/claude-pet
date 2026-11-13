import Foundation

/// `ClaudePet --selftest-cinema`: curvas, temporizacion y seleccion de efectos de la isla viva.
enum IslandCinemaSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let c = IslandCinema.self

        check("las curvas van de 0 a 1 sin salirse", c.easeOutCubic(0) == 0 && c.easeOutCubic(1) == 1 && c.easeInOutCubic(0) == 0 && c.easeInOutCubic(1) == 1 && c.easeOutCubic(2) == 1 && c.easeInOutCubic(-1) == 0)
        check("las curvas son monotonas", stride(from: 0.0, to: 1.0, by: 0.05).allSatisfy { c.easeOutCubic($0 + 0.05) >= c.easeOutCubic($0) && c.easeInOutCubic($0 + 0.05) >= c.easeInOutCubic($0) })
        check("la pasada de luz dura 0,6 s y es una sola", c.sweepDuration == 0.6 && c.sweepHead(age: -0.01) == nil && c.sweepHead(age: 0.61) == nil && c.sweepHead(age: 0) == 0 && c.sweepHead(age: 0.6) == 1)
        check("la luz avanza siempre y nunca vuelve atras", stride(from: 0.0, to: 0.6, by: 0.02).allSatisfy { (c.sweepHead(age: $0 + 0.02) ?? 1) >= (c.sweepHead(age: $0) ?? 0) })
        check("la luz entra y sale con opacidad 0 en los extremos", c.sweepAlpha(age: 0) == 0 && c.sweepAlpha(age: 0.6) == 0 && c.sweepAlpha(age: 0.3) == 1 && c.sweepAlpha(age: 0.7) == 0)

        let first = c.reveal(age: 0, index: 0, motion: true), last = c.reveal(age: 2, index: 5, motion: true)
        check("la tarjeta empieza invisible, desenfocada y desplazada, y termina nitida y en su sitio", first.opacity == 0 && first.blur == c.cardBlur && first.offsetY == c.cardRise && last == IslandCinema.Reveal(opacity: 1, offsetY: 0, blur: 0))
        check("cada bloque entra despues del anterior", c.reveal(age: 0.2, index: 0, motion: true).opacity > c.reveal(age: 0.2, index: 3, motion: true).opacity)
        check("el desenfoque se afila de forma monotona", stride(from: 0.0, to: 0.5, by: 0.02).allSatisfy { c.reveal(age: $0 + 0.02, index: 0, motion: true).blur <= c.reveal(age: $0, index: 0, motion: true).blur })
        check("sin movimiento solo cambia la opacidad", stride(from: 0.0, to: 0.6, by: 0.05).allSatisfy { let r = c.reveal(age: $0, index: 2, motion: false); return r.offsetY == 0 && r.blur == 0 })
        check("la aparicion total cabe en medio segundo con seis bloques", c.revealTotal(blocks: 6) < 0.72 && c.revealTotal(blocks: 1) == c.cardRevealLength)

        check("riesgo bajo no tiñe el acento", c.accent(agent: 0xE0824F, risk: .low) == 0xE0824F)
        check("riesgo medio tiñe poco y alto tiñe más, hacia el rojo apagado", {
            func r(_ x: UInt32) -> Int { Int((x >> 16) & 0xFF) }
            func g(_ x: UInt32) -> Int { Int((x >> 8) & 0xFF) }
            let m = c.accent(agent: 0xE0824F, risk: .medium), h = c.accent(agent: 0xE0824F, risk: .high)
            return m != 0xE0824F && h != m && g(h) < g(m) && g(m) <= 0xE7 && r(h) < 0xE0
        }())
        check("el acento azul de codex tambien se mezcla sin salirse de rango", [PermissionRisk.low, .medium, .high].allSatisfy { c.accent(agent: 0x5270E8, risk: $0) <= 0xFFFFFF })

        check("la respiracion del borde es lenta y acotada", stride(from: 0.0, to: 7.0, by: 0.05).allSatisfy { (0.249...0.701).contains(c.breath(at: $0)) } && c.breathPeriod >= 3)
        check("la respiracion se detiene tras unos ciclos", c.breathLength == c.breathPeriod * 6 && c.breathLength < 25)

        check("con efectos, el riesgo alto respira y el resto solo barre", c.plan(effectsOn: true, risk: .high) == .init(sweep: true, staggered: true, breathing: true, staticRiskEdge: false) && !c.plan(effectsOn: true, risk: .medium).breathing && !c.plan(effectsOn: true, risk: .low).breathing)
        check("sin efectos no hay barrido ni respiracion y el riesgo alto queda con un borde fijo", c.plan(effectsOn: false, risk: .high) == .init(sweep: false, staggered: false, breathing: false, staticRiskEdge: true) && !c.plan(effectsOn: false, risk: .low).staticRiskEdge)

        print(failures == 0 ? "todo bien" : "\(failures) fallo(s)")
        return failures == 0
    }
}
