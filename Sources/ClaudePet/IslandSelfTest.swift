import Foundation
import SwiftUI

/// `ClaudePet --selftest-island`: reglas de la isla (oculta, asoma, compacta, abierta, alertas, terminado, ausencia).
enum IslandSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        func input(_ t: TimeInterval, notch: Bool = false, island: Bool = false, tasks: Bool = false,
                   alert: Bool = false, finished: Bool = false, idle: TimeInterval = 0, click: Bool = false) -> IslandInput {
            IslandInput(now: t, overNotch: notch, overIsland: island, tasksRunning: tasks, alertPending: alert,
                        finishedPending: finished, idleSeconds: idle, clickedPet: click)
        }

        // 1. nada corre: invisible
        var m = IslandMachine()
        check("sin tareas la isla esta oculta", m.tick(input(0)) == .hidden)

        // 2. cursor sobre el notch: asoma; 650 ms despues se abre; si se va, vuelve a ocultarse
        m = IslandMachine()
        check("el cursor sobre el notch hace asomar a la mascota", m.tick(input(0, notch: true)) == .peek)
        check("a 0,3 s sigue asomada", m.tick(input(0.3, notch: true)) == .peek)
        check("a 0,65 s se abre", m.tick(input(0.7, notch: true)) == .expanded)
        m = IslandMachine()
        _ = m.tick(input(0, notch: true))
        check("si el cursor se va, aguanta 0,6 s asomada", m.tick(input(0.3)) == .peek && m.tick(input(0.5)) == .peek)
        check("y luego se oculta", m.tick(input(1.0)) == .hidden)

        // 3. tareas con usuario activo: compacta
        m = IslandMachine()
        check("con tareas y usuario activo queda compacta", m.tick(input(0, tasks: true)) == .compact)

        // 4. hover en compacta abre a los 200 ms; el clic abre de inmediato
        check("hover en compacta abre tras 0,2 s", m.tick(input(1, island: true, tasks: true)) == .compact
              && m.tick(input(1.25, island: true, tasks: true)) == .expanded)
        m = IslandMachine(); _ = m.tick(input(0, tasks: true))
        check("clic en la mascota compacta abre ya", m.tick(input(1, tasks: true, click: true)) == .expanded)

        // 5. cierre automatico a los 60 s sin actividad, con cuenta atras los ultimos 10 s
        m = IslandMachine(); _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, click: true))
        check("a 30 s sigue abierta, sin cuenta atras", m.tick(input(31, tasks: true)) == .expanded && m.countdown == nil)
        check("a 55 s hay cuenta atras", m.tick(input(56, tasks: true)) == .expanded && (m.countdown ?? 0) > 0)
        check("a 61 s se pliega a compacta", m.tick(input(62, tasks: true)) == .compact)
        m = IslandMachine(); _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, click: true))
        _ = m.tick(input(50, island: true, tasks: true))
        check("mover el cursor por la isla reinicia el plazo", m.tick(input(100, island: true, tasks: true)) == .expanded)

        // 6. ausente 3 min: oculta aunque haya tareas; vuelve al primer movimiento
        m = IslandMachine(); _ = m.tick(input(0, tasks: true))
        check("ausente 3 min se oculta", m.tick(input(200, tasks: true, idle: 200)) == .hidden)
        check("al volver el usuario regresa a compacta", m.tick(input(201, tasks: true, idle: 0)) == .compact)

        // 7. alertas: abren solas incluso ausente y no se cierran solas
        m = IslandMachine()
        check("una alerta abre la isla estando ausente", m.tick(input(0, tasks: true, alert: true, idle: 999)) == .expanded)
        check("a los 5 min sigue abierta", m.tick(input(300, tasks: true, alert: true, idle: 999)) == .expanded && m.reason == .alert)
        check("al responder vuelve al reposo", m.tick(input(301, tasks: true, idle: 0)) == .compact)
        m = IslandMachine(); _ = m.tick(input(0, notch: true))
        check("una alerta que llega durante asoma abre de inmediato", m.tick(input(0.2, notch: true, alert: true)) == .expanded && m.reason == .alert)
        check("una alerta durante ausencia conserva la isla abierta", m.tick(input(180, tasks: true, alert: true, idle: 180)) == .expanded && m.reason == .alert)
        check("el fin de tarea no pisa una alerta activa", m.tick(input(181, tasks: true, alert: true, finished: true, idle: 180)) == .expanded && m.reason == .alert)

        // 5b. cierre rapido al salir el cursor (hover y clic); las alertas y lo terminado no se tocan
        m = IslandMachine(); m.closeDelay = 1.2
        _ = m.tick(input(0, notch: true)); _ = m.tick(input(0.7, notch: true))
        check("abierta por hover y con el cursor encima, no se cierra", m.mode == .expanded && m.reason == .hover && m.tick(input(5, island: true, tasks: true)) == .expanded)
        check("al salir el cursor empieza una cuenta corta", m.tick(input(6, tasks: true)) == .expanded && (m.countdown ?? 0) > 0.8)
        check("a 0,6 s la barra va por la mitad", abs((m.tick(input(6.6, tasks: true)) == .expanded ? m.countdown ?? 0 : 0) - 0.5) < 0.01)
        check("a 1,2 s se pliega", m.tick(input(7.3, tasks: true)) == .compact && m.countdown == nil)
        m = IslandMachine(); m.closeDelay = 1.2
        _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, click: true))
        check("un clic deja mas margen: 3 s", m.tick(input(3, tasks: true)) == .expanded && m.tick(input(5.9, tasks: true)) == .expanded && m.tick(input(8.1, tasks: true)) == .compact)
        m = IslandMachine(); m.closeDelay = 1.2
        _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, click: true)); _ = m.tick(input(2, tasks: true))
        check("volver con el cursor cancela el cierre", m.tick(input(2.5, island: true, tasks: true)) == .expanded && m.countdown == nil && m.tick(input(20, island: true, tasks: true)) == .expanded)
        m = IslandMachine(); m.closeDelay = 1.2
        _ = m.tick(input(0, tasks: true, alert: true))
        check("una alerta nunca se cierra por salir el cursor", m.tick(input(30, tasks: true, alert: true)) == .expanded && m.reason == .alert)
        m = IslandMachine(); m.closeDelay = 1.2
        _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, finished: true))
        check("la vista de terminado conserva su propio plazo", m.reason == .finished && m.tick(input(3, tasks: true)) == .expanded)
        m = IslandMachine()
        _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, click: true))
        check("sin retraso configurado queda el plazo de 60 s", m.tick(input(30, tasks: true)) == .expanded)

        // 7b. retraso de activacion: el cursor debe quedarse sobre la zona antes de asomar
        m = IslandMachine(); m.activationDelay = 0.3
        check("con retraso, un roce rapido no asoma", m.tick(input(0, notch: true)) == .hidden && m.tick(input(0.1, notch: true)) == .hidden && m.tick(input(0.15)) == .hidden)
        check("el retraso se reinicia al salir de la zona", m.tick(input(0.2, notch: true)) == .hidden && m.tick(input(0.4, notch: true)) == .hidden)
        check("tras el retraso asoma", m.tick(input(0.55, notch: true)) == .peek)
        m = IslandMachine(); m.activationDelay = 0
        check("sin retraso asoma de inmediato", m.tick(input(0, notch: true)) == .peek)

        // 8. terminado: se abre 5,2 s y se pliega
        m = IslandMachine(); _ = m.tick(input(0, tasks: true))
        check("terminar abre la vista de fin", m.tick(input(1, tasks: true, finished: true)) == .expanded && m.reason == .finished)
        check("a los 4 s sigue abierta", m.tick(input(5, tasks: true)) == .expanded)
        check("a los 5,2 s se pliega", m.tick(input(6.3, tasks: true)) == .compact)
        m = IslandMachine()
        _ = m.tick(input(0, finished: true))
        check("sin tareas, tras terminar queda oculta", m.tick(input(6)) == .hidden)

        // 9. geometria del notch
        let notchMac = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 38, auxLeft: 664, auxRight: 664)
        let plainMac = ScreenMetrics(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), safeTop: 0, auxLeft: 0, auxRight: 0)
        check("detecta el notch y mide su ancho real", NotchGeometry.hasNotch(notchMac) && NotchGeometry.notchSize(notchMac) == CGSize(width: 184, height: 38))
        check("sin notch respeta la altura de barra inyectada", !NotchGeometry.hasNotch(plainMac) && NotchGeometry.notchSize(plainMac).height == 24)
        let largeBar = ScreenMetrics(frame: plainMac.frame, safeTop: 0, auxLeft: 0, auxRight: 0, menuBarHeight: 30)
        check("barra grande conserva la altura en puntos", NotchGeometry.notchSize(largeBar) == CGSize(width: 80, height: 30))
        let fullBar = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), safeTop: 0, auxLeft: 0, auxRight: 0, centerLeftInset: 500, centerRightInset: 500)
        check("barra llena limita el ancho compacto", NotchGeometry.islandSize(.compact, metrics: fullBar, compactContentWidth: 400).width == 280)
        check("oculta mide como el notch; asoma +64; compacta +104",
              NotchGeometry.islandSize(.hidden, metrics: notchMac).width == 184 && NotchGeometry.islandSize(.peek, metrics: notchMac).width == 248
              && NotchGeometry.islandSize(.compact, metrics: notchMac).width == 288)
        check("abierta mide 640 de ancho", NotchGeometry.islandSize(.expanded, metrics: notchMac).width == 640)
        let f = NotchGeometry.islandFrame(.compact, metrics: notchMac)
        check("la isla queda pegada al borde superior y centrada", f.maxY == 982 && f.midX == 756)
        let pf = NotchGeometry.panelFrame(plainMac)
        check("la ventana queda centrada arriba de su pantalla", pf.midX == plainMac.frame.midX && pf.maxY == plainMac.frame.maxY && pf.width == 720)
        check("elige la pantalla con notch aunque no sea la primera", NotchGeometry.pick([plainMac, notchMac]) == notchMac)
        check("sin notch usa la primera pantalla", NotchGeometry.pick([plainMac]) == plainMac)
        check("dos monitores conservan geometría independiente", NotchGeometry.panelFrame(notchMac).midX == 756 && NotchGeometry.panelFrame(plainMac).midX == 2472)
        let right = ScreenMetrics(frame: CGRect(x: 3432, y: 0, width: 1512, height: 982), safeTop: 0, auxLeft: 0, auxRight: 0)
        check("seguir al ratón elige la pantalla bajo el cursor", NotchGeometry.pick([plainMac, right], preference: .mouse, mouse: CGPoint(x: 3600, y: 200)) == right)
        check("sobre el notch (con margen de 6 pt) cuenta como encima",
              NotchGeometry.overNotch(CGPoint(x: 756, y: 975), metrics: notchMac) && NotchGeometry.overNotch(CGPoint(x: 756 + 92 + 5, y: 975), metrics: notchMac)
              && !NotchGeometry.overNotch(CGPoint(x: 756 + 92 + 8, y: 975), metrics: notchMac) && !NotchGeometry.overNotch(CGPoint(x: 756, y: 900), metrics: notchMac))
        check("la zona transparente de la ventana no cuenta como isla", !NotchGeometry.contains(CGPoint(x: 756, y: 800), mode: .compact, metrics: notchMac))
        check("la isla comparte un resorte amortiguado", IslandMotion.springResponse > 0 && IslandMotion.springDamping > 0.7 && IslandMotion.maximumDuration < 1)

        // 10. animacion de personaje
        let calm = CGPoint.zero
        func pose(_ t: TimeInterval, gaze: CGPoint = calm, pokes: [TimeInterval] = [], hop: TimeInterval? = nil, motion: Bool = true, hover: Bool = false) -> PetPose {
            PetAnimator.pose(at: t, gaze: gaze, pokes: pokes, hopStart: hop, motion: motion, hover: hover)
        }
        let scales = stride(from: 0.0, to: 8.0, by: 0.05).map { pose($0).scaleY }
        check("respira entre 1,00 y 1,04 y sube y baja", scales.min()! >= 1 && scales.max()! <= 1.0401 && scales.max()! - scales.min()! > 0.03)
        check("la respiracion se repite cada 4 s", abs(pose(1).scaleY - pose(5).scaleY) < 1e-9)
        var blinkFrames = 0, blinkStarts = 0, wasBlinking = false
        for k in 0..<6000 { let b = PetAnimator.isBlinking(at: Double(k) / 100); if b { blinkFrames += 1 }; if b && !wasBlinking { blinkStarts += 1 }; wasBlinking = b }
        check("en 60 s parpadea entre 12 y 45 veces", (12...45).contains(blinkStarts))
        check("cada parpadeo dura poco: menos del 8 % del tiempo con los ojos cerrados", blinkFrames < 480)
        check("con movimiento reducido no respira ni parpadea", { let q = pose(1.2, motion: false); return q.scaleY == 1 && !q.blink && q.dy == 0 }())
        check("reduce-motion mantiene la mirada pero anula reacciones", { let q = pose(1.2, gaze: CGPoint(x: 1, y: 0), pokes: [1.2], motion: false); return q.eyeDX == 1 && q.dx == 0 && !q.dizzy }())
        check("la mirada sigue al cursor: derecha, izquierda, arriba y abajo",
              PetAnimator.eyes(gaze: CGPoint(x: 1, y: 0)) == (1, 0) && PetAnimator.eyes(gaze: CGPoint(x: -1, y: 0)) == (-1, 0)
              && PetAnimator.eyes(gaze: CGPoint(x: 0, y: 1)) == (0, -1) && PetAnimator.eyes(gaze: CGPoint(x: 0, y: -1)) == (0, 1))
        check("con el cursor cerca del centro mira al frente", PetAnimator.eyes(gaze: CGPoint(x: 0.1, y: -0.2)) == (0, 0))
        check("la mirada sigue funcionando con movimiento reducido", pose(1, gaze: CGPoint(x: 1, y: 0), motion: false).eyeDX == 1)
        check("hover agranda los ojos una celda", pose(1, hover: true).wideEyes && !pose(1).wideEyes)
        check("clic aplasta y molesta durante 0,6 s", { let q = pose(10.05, pokes: [10]); return q.annoyed && q.scaleY < 0.9 && pose(10.5, pokes: [10]).annoyed && !pose(10.7, pokes: [10]).annoyed }())
        check("un toque sacude el cuerpo", (1..<10).contains { abs(pose(10 + Double($0) * 0.03, pokes: [10]).dx) > 0.2 })
        check("la sacudida termina a los 0,35 s", pose(10.5, pokes: [10]).dx == 0)
        let three: [TimeInterval] = [10, 10.4, 10.8]
        check("tres toques seguidos marean", pose(11.2, pokes: three).dizzy && pose(11.2, pokes: three).rotation != 0)
        check("tres toques en menos de 2 s activan mareo antes del tercer segundo", pose(11.9, pokes: [10, 10.6, 11.1]).dizzy)
        check("el mareo dura 3 s y luego pasa", pose(12.5, pokes: three).dizzy && !pose(13.9, pokes: three).dizzy)
        check("dos toques espaciados no marean", !pose(11, pokes: [5, 10.5]).dizzy)
        check("el salto: se agacha, sube a media altura, cae y rebota", {
            let crouch = pose(20.1, hop: 20), top = pose(20.42, hop: 20).dy, bounce = pose(20.88, hop: 20).dy
            return crouch.scaleY < 0.95 && crouch.dy == 0 && top < -2.9 && bounce < -0.5 && pose(21.3, hop: 20).dy == 0 && pose(19.9, hop: 20).dy == 0
        }())
        check("el rebote es mas pequeno que el salto", abs(pose(20.88, hop: 20).dy) < abs(pose(20.42, hop: 20).dy))

        // emociones de fondo
        func scene(_ idle: TimeInterval = 0, _ state: PetState = .idle, dance: Bool = false, confetti: TimeInterval? = nil) -> PetScene { PetScene(idleSeconds: idle, state: state, confettiStart: confetti, dancing: dance) }
        func emote(_ t: TimeInterval, _ sc: PetScene, pokes: [TimeInterval] = [], hop: TimeInterval? = nil) -> PetPose { PetAnimator.pose(at: t, gaze: .zero, pokes: pokes, hopStart: hop, motion: true, scene: sc) }
        check("tras 5 min de reposo se duerme con los ojos cerrados", emote(50, scene(301)).sleepy && emote(50, scene(301)).blink && !emote(50, scene(299)).sleepy)
        check("dormida respira cada 6 s y despierta cada 4 s", abs(emote(1.5, scene(301)).scaleY - emote(7.5, scene(301)).scaleY) < 1e-9 && abs(emote(1.5, scene(0)).scaleY - emote(7.5, scene(0)).scaleY) > 1e-6)
        check("trabajando no se duerme aunque el usuario este ausente", !emote(50, scene(999, .thinking)).sleepy)
        check("un toque la despierta de inmediato", !emote(50.1, scene(301), pokes: [50]).sleepy)
        check("con error se preocupa y tiembla", emote(10, scene(0, .error)).worried && (1..<20).contains { abs(emote(10 + Double($0) * 0.013, scene(0, .error)).dx) > 0.1 })
        check("con musica baila: se mece y rebota", emote(10, scene(0, .idle, dance: true)).dancing && (1..<20).contains { abs(emote(10 + Double($0) * 0.05, scene(0, .idle, dance: true)).rotation) > 3 })
        check("bailar no pisa el salto de terminado", !emote(20.4, scene(0, .idle, dance: true), hop: 20).dancing)
        check("sin movimiento no hay emociones", { let q = PetAnimator.pose(at: 10, gaze: .zero, pokes: [], hopStart: nil, motion: false, scene: scene(999)); return !q.sleepy && !q.worried && !q.dancing }())
        let z = PetAnimator.particles(at: 3, pose: emote(3, scene(400)), scene: scene(400))
        check("dormida suelta z en la esquina superior derecha, dentro del lienzo", !z.isEmpty && z.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) && $0.x >= 10 && $0.y <= 7 })
        check("sin emocion no hay particulas", PetAnimator.particles(at: 3, pose: PetPose(), scene: scene()).isEmpty)
        let conf = scene(0, .idle, confetti: 100)
        let c1 = PetAnimator.particles(at: 101, pose: PetPose(), scene: conf)
        check("el confeti cae durante 2,6 s y desaparece", !c1.isEmpty && c1.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) }
              && !PetAnimator.particles(at: 102, pose: PetPose(), scene: conf).isEmpty && PetAnimator.particles(at: 102.7, pose: PetPose(), scene: conf).isEmpty
              && PetAnimator.particles(at: 99, pose: PetPose(), scene: conf).isEmpty)
        check("el confeti es determinista", PetAnimator.particles(at: 101, pose: PetPose(), scene: conf).map { "\($0.x),\($0.y)" } == c1.map { "\($0.x),\($0.y)" })
        check("preocupada muestra una gota de sudor", PetAnimator.particles(at: 2, pose: emote(2, scene(0, .error)), scene: scene(0, .error)).count == 2)
        check("la musica solo cuenta si el estado es exactamente playing", MusicMonitor.parse("playing\n") && !MusicMonitor.parse("paused") && !MusicMonitor.parse("stopped") && !MusicMonitor.parse("") && !MusicMonitor.parse("not playing"))
        // brillo de color del fondo
        func glow(_ st: PetState = .idle, codex: PetState = .idle, reason: IslandReason = .none, asking: Bool = false, dizzy: Bool = false) -> IslandGlow.Glow? { IslandGlow.glow(state: st, codex: codex, reason: reason, asking: asking, dizzy: dizzy) }
        check("en reposo no hay brillo", glow() == nil)
        check("pedir permiso enciende el ambar", glow(asking: true)?.hex == 0xE7B45B && glow(.waiting)?.hex == 0xE7B45B)
        check("terminar enciende el verde", glow(.done, reason: .finished)?.hex == 0x6CCB8A)
        check("trabajando brilla azul y mas suave que un aviso", glow(.thinking)?.hex == 0x5270E8 && (glow(.thinking)?.strength ?? 1) < (glow(asking: true)?.strength ?? 0))
        check("un error brilla rojo", glow(.error)?.hex == 0xD85C5C)
        check("el mareo manda sobre todo lo demas", glow(.error, asking: true, dizzy: true)?.hex == 0xC25AA0)
        check("un permiso manda sobre trabajar", glow(.thinking, asking: true)?.hex == 0xE7B45B)
        check("el brillo de codex tambien cuenta", glow(.idle, codex: .tool)?.hex == 0x5270E8)
        check("el aviso de mareo cuenta atras desde 3 s", PetAnimator.dizzyRemaining(pokes: three, at: 10.9).map { Int($0.rounded(.up)) } == 3 && PetAnimator.dizzyRemaining(pokes: three, at: 12.0).map { Int($0.rounded(.up)) } == 2 && PetAnimator.dizzyRemaining(pokes: three, at: 13.5).map { Int($0.rounded(.up)) } == 1 && PetAnimator.dizzyRemaining(pokes: three, at: 14.0) == nil)
        check("sin tres toques no hay aviso de mareo", PetAnimator.dizzyRemaining(pokes: [10, 10.5], at: 10.6) == nil)
        m = IslandMachine(); _ = m.tick(input(0, tasks: true)); _ = m.tick(input(1, tasks: true, finished: true))
        var dismiss = input(2, tasks: true); dismiss.dismissFinished = true
        check("pulsar ok cierra la tarjeta de terminado sin esperar", m.reason == .finished && m.tick(dismiss) == .compact)
        // vida propia en reposo
        var looks = 0, stretches = 0, yawns = 0, ears = 0, lastLook = false, lastStretch = false, lastYawn = false, lastEar = false
        for k in 0..<30_000 {
            let life = PetAnimator.idleLife(at: Double(k) / 100)
            if life.look != nil && !lastLook { looks += 1 }; lastLook = life.look != nil
            if life.stretch != nil && !lastStretch { stretches += 1 }; lastStretch = life.stretch != nil
            if life.yawn && !lastYawn { yawns += 1 }; lastYawn = life.yawn
            if life.earLift && !lastEar { ears += 1 }; lastEar = life.earLift
        }
        check("en 5 min mira alrededor entre 30 y 55 veces", (30...55).contains(looks))
        check("en 5 min se estira entre 5 y 14 veces", (5...14).contains(stretches))
        check("bosteza en algunos estiramientos, no en todos", yawns >= 1 && yawns <= stretches)
        check("mueve las orejas con frecuencia", ears > 20)
        check("la vida propia es determinista", PetAnimator.idleLife(at: 123.4) == PetAnimator.idleLife(at: 123.4))
        func quiet(_ t: TimeInterval, state: PetState = .idle, idle: TimeInterval = 5, gaze: CGPoint = .zero) -> PetPose { PetAnimator.pose(at: t, gaze: gaze, pokes: [], hopStart: nil, motion: true, scene: PetScene(idleSeconds: idle, state: state)) }
        let lookTime = (0..<3000).map { Double($0) / 10 }.first { PetAnimator.idleLife(at: $0 + 0.5).look != nil } ?? 0
        check("en reposo sus ojos se mueven solos", { let q = quiet(lookTime + 0.5); return q.eyeDX != 0 || q.eyeDY != 0 }())
        check("si el cursor la distrae, manda el cursor", quiet(lookTime + 0.5, gaze: CGPoint(x: -1, y: 0)).eyeDX == -1)
        check("trabajando no hace sus cosas de reposo", !(0..<400).contains { let q = quiet(Double($0) / 4, state: .tool); return q.earLift || q.yawn })
        check("dormida no hace sus cosas de reposo", !(0..<400).contains { let q = quiet(Double($0) / 4, idle: 400); return q.earLift || q.yawn })
        let stretchTime = (0..<9000).map { Double($0) / 10 }.first { PetAnimator.idleLife(at: $0).stretch != nil } ?? 0
        check("al estirarse crece en vertical y sube un poco", { let q = quiet(stretchTime + 0.35); return q.scaleY > 1.06 && q.dy < 0 }())
        let yawnTime = (0..<9000).map { Double($0) / 10 }.first { PetAnimator.idleLife(at: $0).yawn } ?? -1
        check("el bostezo abre la boca con los ojos cerrados", yawnTime >= 0 && { let q = quiet(yawnTime); return q.yawn && q.blink }())
        let yawned = PetAnimator.apply(Sprite.block(.idle, tick: 3), pose: { var q = PetPose(); q.yawn = true; q.blink = true; return q }())
        check("el bostezo dibuja la boca dentro del cuerpo", yawned.filter { $0.c == Pal.charcoal && $0.y >= 10 && $0.x >= 7 && $0.x <= 8 }.count == 4)
        let lifted = PetAnimator.apply(Sprite.block(.idle, tick: 3), pose: { var q = PetPose(); q.earLift = true; return q }())
        let baseEars = Sprite.block(.idle, tick: 3).filter { $0.x <= 1 || $0.x >= 14 }.map(\.y).min() ?? 0
        check("el tic sube las orejas una celda", (lifted.filter { $0.x <= 1 || $0.x >= 14 }.map(\.y).min() ?? 0) == baseEars - 1)
        check("al terminar titilan destellos y no hay confeti", !PetAnimator.particles(at: 2.0, pose: PetPose(), scene: PetScene(state: .done)).isEmpty && PetAnimator.particles(at: 2.0, pose: PetPose(), scene: PetScene(state: .idle)).isEmpty)
        // inclinacion hacia el cursor
        func lean(_ gx: Double) -> PetPose { PetAnimator.pose(at: 5, gaze: CGPoint(x: gx, y: 0), pokes: [], hopStart: nil, motion: true, scene: PetScene(idleSeconds: 0, state: .tool)) }
        check("se inclina hacia el lado del cursor", lean(1).rotation > 2 && lean(-1).rotation < -2 && lean(1).dx > 0 && lean(-1).dx < 0)
        check("sin cursor cerca va derecha", lean(0).rotation == 0 && lean(0).dx == 0)
        check("la inclinacion tiene un tope", lean(50).rotation <= 3.6 && lean(-50).rotation >= -3.6)
        check("sin movimiento no se inclina", PetAnimator.pose(at: 5, gaze: CGPoint(x: 1, y: 0), pokes: [], hopStart: nil, motion: false).rotation == 0)
        check("el mareo manda sobre la inclinacion", abs(PetAnimator.pose(at: 11.2, gaze: CGPoint(x: 1, y: 0), pokes: [10, 10.4, 10.8], hopStart: nil, motion: true).rotation) != 3.5)
        // entrada, decision e impaciencia
        func moment(_ t: TimeInterval, _ scene: PetScene) -> PetPose { PetAnimator.pose(at: t, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: scene) }
        var opened = PetScene(state: .idle); opened.openedAt = 100
        check("al abrirse entra pequeña y llega a su tamaño", moment(100.02, opened).scaleY < 0.8 && abs(moment(100.7, opened).scaleY - moment(100.7, PetScene(state: .idle)).scaleY) < 1e-9)
        check("la entrada rebota: se pasa un poco de su tamaño antes de asentarse", (1..<55).contains { moment(100 + Double($0) / 100, opened).scaleY > moment(100 + Double($0) / 100, PetScene(state: .idle)).scaleY * 1.01 })
        var nod = PetScene(state: .idle); nod.decisionAllow = true; nod.decisionAt = 50
        var shake = PetScene(state: .idle); shake.decisionAllow = false; shake.decisionAt = 50
        check("al permitir asiente: sube y baja", (1..<80).contains { moment(50 + Double($0) / 100, nod).dy > 0.3 } && !(1..<80).contains { abs(moment(50 + Double($0) / 100, nod).dx) > 0.3 })
        check("al denegar niega: se sacude de lado y cierra los ojos", (1..<80).contains { abs(moment(50 + Double($0) / 100, shake).dx) > 0.3 } && moment(50.1, shake).blink)
        check("la decision dura 0,8 s", moment(50.9, nod).dy == moment(50.9, PetScene(state: .idle)).dy)
        var patient = PetScene(state: .waiting); patient.waitingFor = 5
        var impatient = PetScene(state: .waiting); impatient.waitingFor = 20
        check("con poco tiempo esperando no se impacienta", !moment(3.3, patient).impatient && !(0..<50).contains { abs(moment(Double($0) / 10, patient).rotation) > 3 })
        check("tras 15 s esperando golpetea y se balancea", moment(3.3, impatient).impatient && (0..<50).contains { abs(moment(Double($0) / 10, impatient).rotation) > 1.5 } && (0..<50).contains { moment(Double($0) / 10, impatient).dy < -0.2 })
        var alarmed = PetScene(state: .waiting); alarmed.waitingFor = 50
        check("tras 40 s aparece una exclamacion que parpadea", (0..<20).contains { !PetAnimator.particles(at: Double($0) / 5, pose: PetPose(), scene: alarmed).isEmpty } && PetAnimator.particles(at: 1, pose: PetPose(), scene: impatient).isEmpty)
        // caricia y mariposa
        var petted = PetScene(state: .idle); petted.pettingFor = 1.2
        var brief = PetScene(state: .idle); brief.pettingFor = 0.3
        check("tras 0,8 s con el cursor encima se pone contenta", moment(5, petted).happy && !moment(5, brief).happy)
        check("contenta ronronea: vibra un poco", (0..<30).contains { abs(moment(Double($0) / 7, petted).scaleY - moment(Double($0) / 7, PetScene(state: .idle)).scaleY) > 0.008 })
        let happyEyes = PetAnimator.apply(Sprite.block(.idle, tick: 3), pose: { var q = PetPose(); q.happy = true; return q }())
        check("los ojos contentos son un ^ en cada ojo", happyEyes.filter { $0.c == Pal.charcoal && $0.y >= 8 && $0.y <= 9 }.count == 6)
        check("suben corazones mientras la acarician", !PetAnimator.particles(at: 2, pose: moment(5, petted), scene: petted).isEmpty && PetAnimator.particles(at: 2, pose: moment(5, brief), scene: brief).allSatisfy { $0.c != Color(hex: 0xFF7DA8) } && Petting.hearts(at: 1).allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) })
        var calmDay = PetScene(idleSeconds: 60, state: .idle)
        let followedEyes = (0..<400).map { PetAnimator.pose(at: Double($0) / 10, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: calmDay) }.filter { $0.eyeDX != 0 }.count
        check("de dia, tranquila, sigue la mariposa con los ojos", followedEyes > 40)
        calmDay.idleSeconds = 5
        check("sin tiempo tranquila no hay mariposa que seguir", Butterfly.visible(idleSeconds: 5, hour: 12) == false && Butterfly.visible(idleSeconds: 60, hour: 12) && !Butterfly.visible(idleSeconds: 60, hour: 23) && !Butterfly.visible(idleSeconds: 400, hour: 12))
        check("la mariposa se dibuja en el escenario solo cuando toca", !StageScene.particles(at: 3, state: .idle, hour: 12, idleSeconds: 60).isEmpty && StageScene.particles(at: 3, state: .idle, hour: 12, idleSeconds: 5).isEmpty)
        check("la mariposa revolotea dentro de la caja", (0..<500).allSatisfy { let p = Butterfly.position(at: Double($0) / 10); return (0.05...0.95).contains(p.x) && (0.1...0.5).contains(p.y) })
        check("el cursor manda sobre la mariposa", PetAnimator.pose(at: 3.3, gaze: CGPoint(x: -1, y: 0), pokes: [], hopStart: nil, motion: true, scene: PetScene(idleSeconds: 60, state: .idle)).eyeDX == -1)
        check("bailando saca notas a los lados", !PetAnimator.particles(at: 2, pose: emote(2, scene(0, .idle, dance: true)), scene: scene(0, .idle, dance: true)).isEmpty)

        // el sprite real: los ojos se mueven, parpadean y nunca salen del cuerpo
        var eyesOK = true, moved = false, blinkLine = false
        for st in PetState.allCases where st != .error {
            let base = Sprite.block(st, tick: 5)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (1, 1), (-1, -1)] {
                var q = PetPose(); q.eyeDX = dx; q.eyeDY = dy
                let out = PetAnimator.apply(base, pose: q)
                if out.contains(where: { $0.c == Pal.charcoal && $0.y >= 5 && $0.y <= 11 && ($0.x < 3 || $0.x > 12) }) { eyesOK = false }
                if out.count != base.count && st != .starting { eyesOK = eyesOK && false }
                if st == .idle && (dx, dy) == (1, 0) { moved = out.map { "\($0.x),\($0.y)" }.sorted() != base.map { "\($0.x),\($0.y)" }.sorted() }
            }
            var b = PetPose(); b.blink = true
            let closed = PetAnimator.apply(base, pose: b)
            if st == .idle { blinkLine = closed.filter { $0.c == Pal.charcoal && $0.y == 8 }.count >= 6 }
        }
        check("los ojos del sprite quedan dentro del cuerpo en todos los estados", eyesOK)
        check("mirar a la derecha mueve los ojos del sprite", moved)
        check("parpadear deja una linea en los ojos", blinkLine)

        // sondeo: oculta duerme, pero el cursor cerca de la zona la despierta
        let zone = NotchGeometry.activationZone(metrics: plainMac)
        check("el cursor cerca de la zona de activacion despierta el sondeo", IslandPollingPolicy.isNearZone(CGPoint(x: zone.midX, y: zone.minY - 20), zone: zone) && !IslandPollingPolicy.isNearZone(CGPoint(x: zone.midX, y: zone.minY - 300), zone: zone))
        check("oculta y sin cursor cerca el sondeo es lento", IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: false, cursorNearZone: false) == IslandPollingPolicy.idleInterval)
        check("con el cursor cerca el sondeo es rapido aunque este oculta", IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: false, cursorNearZone: true) == IslandPollingPolicy.activeInterval)

        print(failures == 0 ? "ISLAND OK" : "ISLAND FALLOS: \(failures)")
        return failures == 0
    }
}
