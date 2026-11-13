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
        check("la respiracion se detiene tras unos ciclos", c.breathLength == c.breathPeriod * 4 && c.breathLength < 15)

        check("con efectos, el riesgo alto respira y el resto solo barre", c.plan(effectsOn: true, risk: .high) == .init(sweep: true, staggered: true, breathing: true, staticRiskEdge: false) && !c.plan(effectsOn: true, risk: .medium).breathing && !c.plan(effectsOn: true, risk: .low).breathing)
        check("sin efectos no hay barrido ni respiracion y el riesgo alto queda con un borde fijo", c.plan(effectsOn: false, risk: .high) == .init(sweep: false, staggered: false, breathing: false, staticRiskEdge: true) && !c.plan(effectsOn: false, risk: .low).staticRiskEdge)

        // animo de la mascota
        check("ensayo destructivo: inquieta, aunque el comando parezca de riesgo bajo", c.mood(risk: .low, severity: .destructive) == .uneasy && c.mood(risk: .high, severity: .destructive) == .uneasy)
        check("ensayo limpio: aliviada, salvo que el comando sea de riesgo alto", c.mood(risk: .low, severity: .calm) == .relieved && c.mood(risk: .medium, severity: .calm) == .relieved && c.mood(risk: .high, severity: .calm) == .neutral)
        check("sin ensayo: preocupada solo con riesgo alto", c.mood(risk: .high, severity: nil) == .wary && c.mood(risk: .medium, severity: nil) == .neutral && c.mood(risk: .low, severity: nil) == .neutral && c.mood(risk: nil, severity: nil) == .neutral)
        check("ensayo con cambios o dudoso no cambia el animo salvo riesgo alto", c.mood(risk: .medium, severity: .changes) == .neutral && c.mood(risk: .high, severity: .changes) == .wary && c.mood(risk: .low, severity: .unknown) == .neutral)
        let rm = PermissionAsk(id: "m", session: "s", tool: "Bash", project: "p", detail: "rm -rf build", canAlways: false, at: Date())
        let ls = PermissionAsk(id: "l", session: "s", tool: "Read", project: "p", detail: "README.md", canAlways: false, at: Date())
        check("un comando de borrado sin ensayo deja a la mascota preocupada y uno de lectura tranquila", c.mood(ask: rm, phase: nil) == .wary && c.mood(ask: ls, phase: nil) == .neutral && c.mood(ask: nil, phase: nil) == .neutral)
        check("un ensayo en marcha o fallido no mueve el animo", c.mood(ask: ls, phase: .running(since: Date())) == .neutral && c.mood(ask: ls, phase: .failed(.tooBig)) == .neutral)

        func pose(_ m: PetMood, t: TimeInterval = 10.3, since: TimeInterval? = 10, motion: Bool = true) -> PetPose { var p = PetPose(); c.applyMood(&p, mood: m, t: t, since: since, motion: motion); return p }
        check("inquieta: cejas y temblor; preocupada: cejas sin temblor", pose(.uneasy).worried && pose(.uneasy).dx != 0 && pose(.wary).worried && pose(.wary).dx == 0)
        check("aliviada: ojos contentos y un suspiro que se agacha al principio y termina en su sitio", pose(.relieved).happy && pose(.relieved, t: 10.45).scaleY < 1 && pose(.relieved, t: 11).scaleY == 1 && pose(.relieved, t: 11).dy == 0)
        check("neutral no toca la pose", pose(.neutral) == PetPose())
        check("con reducir movimiento se ven las expresiones pero no hay temblor ni suspiro", pose(.uneasy, motion: false).worried && pose(.uneasy, motion: false).dx == 0 && pose(.relieved, t: 10.45, motion: false).happy && pose(.relieved, t: 10.45, motion: false).scaleY == 1)
        let scene = { () -> PetPose in var sc = PetScene(); sc.state = .waiting; sc.mood = .uneasy; sc.moodAt = 10; return PetAnimator.pose(at: 10.3, gaze: .zero, pokes: [], hopStart: nil, motion: false, scene: sc) }()
        check("el animador respeta el animo tambien sin movimiento", scene.worried)

        // cierre de terminado
        let b0 = c.burst(age: 0, color: 0xE0824F), b1 = c.burst(age: 0.3, color: 0xE0824F), b2 = c.burst(age: 0.8, color: 0xE0824F)
        check("el cierre empieza con rafaga y anillo, y termina sin nada vivo", !b0.isEmpty && !b1.isEmpty && c.burst(age: c.burstLength, color: 0xE0824F).isEmpty && c.burst(age: -0.1, color: 0xE0824F).isEmpty && c.burst(age: 5, color: 0xE0824F).isEmpty)
        check("todos los puntos caen dentro de la caja y alineados a la rejilla", stride(from: 0.0, to: 1.2, by: 0.05).allSatisfy { age in
            c.burst(age: age, color: 0x5270E8).allSatisfy { p in (0...1).contains(p.x) && (0...1).contains(p.y) && abs(p.x * c.burstGrid - (p.x * c.burstGrid).rounded()) < 1e-9 && p.alpha >= 0 && p.alpha <= 1 }
        })
        check("el anillo se abre: el radio medio crece mientras se disuelve", {
            func meanRadius(_ age: Double) -> Double {
                let ring = c.burst(age: age, color: 0xE0824F).filter { $0.color == 0xE0824F && $0.size == 1 }
                return ring.map { hypot($0.x - 0.5, $0.y - 0.5) }.reduce(0, +) / Double(max(1, ring.count))
            }
            return meanRadius(0.5) > meanRadius(0.1) && b2.count < b0.count
        }())
        check("es determinista: misma edad, mismos puntos", c.burst(age: 0.4, color: 0xE0824F) == c.burst(age: 0.4, color: 0xE0824F))
        check("el cierre espera al avance de cambios solo si lo hay", c.burstDelay(hasTrailer: false) == 0 && c.burstDelay(hasTrailer: true) == Trailer.duration && c.burstDelay(hasTrailer: true) + c.burstLength < IslandMachine.finishedHold)

        // muelle de la isla
        check("el muelle crece sin rebote apreciable (menos del 1 %) y asienta antes de la duracion maxima", IslandMotion.overshoot(damping: IslandMotion.springDamping) < 0.01 && IslandMotion.settleTime(response: IslandMotion.springResponse, damping: IslandMotion.springDamping) < IslandMotion.maximumDuration)
        check("la formula del rebase es coherente: mas amortiguacion, menos rebote, y critica sin rebote", IslandMotion.overshoot(damping: 0.5) > IslandMotion.overshoot(damping: 0.8) && IslandMotion.overshoot(damping: 1) == 0 && abs(IslandMotion.overshoot(damping: 0.5) - 0.163) < 0.002)
        check("la respuesta no es perezosa ni brusca", (0.35...0.6).contains(IslandMotion.springResponse))

        print(failures == 0 ? "todo bien" : "\(failures) fallo(s)")
        return failures == 0
    }
}
