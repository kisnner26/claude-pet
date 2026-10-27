import Foundation

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
        check("el mareo pasa a los 1,8 s", !pose(12.7, pokes: three).dizzy)
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
        let conf = scene(0, .done, confetti: 100)
        let c1 = PetAnimator.particles(at: 101, pose: PetPose(), scene: conf)
        check("el confeti cae durante 2,6 s y desaparece", !c1.isEmpty && c1.allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) }
              && !PetAnimator.particles(at: 102, pose: PetPose(), scene: conf).isEmpty && PetAnimator.particles(at: 102.7, pose: PetPose(), scene: conf).isEmpty
              && PetAnimator.particles(at: 99, pose: PetPose(), scene: conf).isEmpty)
        check("el confeti es determinista", PetAnimator.particles(at: 101, pose: PetPose(), scene: conf).map { "\($0.x),\($0.y)" } == c1.map { "\($0.x),\($0.y)" })
        check("preocupada muestra una gota de sudor", PetAnimator.particles(at: 2, pose: emote(2, scene(0, .error)), scene: scene(0, .error)).count == 2)
        check("la musica solo cuenta si el estado es exactamente playing", MusicMonitor.parse("playing\n") && !MusicMonitor.parse("paused") && !MusicMonitor.parse("stopped") && !MusicMonitor.parse("") && !MusicMonitor.parse("not playing"))
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

        print(failures == 0 ? "ISLAND OK" : "ISLAND FALLOS: \(failures)")
        return failures == 0
    }
}
