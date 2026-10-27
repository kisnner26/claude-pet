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
        check("sin notch hay una barra de 80 x 32", !NotchGeometry.hasNotch(plainMac) && NotchGeometry.notchSize(plainMac) == CGSize(width: 80, height: 32))
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
        let right = ScreenMetrics(frame: CGRect(x: 3432, y: 0, width: 1512, height: 982), safeTop: 0, auxLeft: 0, auxRight: 0)
        check("seguir al ratón elige la pantalla bajo el cursor", NotchGeometry.pick([plainMac, right], preference: .mouse, mouse: CGPoint(x: 3600, y: 200)) == right)
        check("sobre el notch (con margen de 6 pt) cuenta como encima",
              NotchGeometry.overNotch(CGPoint(x: 756, y: 975), metrics: notchMac) && NotchGeometry.overNotch(CGPoint(x: 756 + 92 + 5, y: 975), metrics: notchMac)
              && !NotchGeometry.overNotch(CGPoint(x: 756 + 92 + 8, y: 975), metrics: notchMac) && !NotchGeometry.overNotch(CGPoint(x: 756, y: 900), metrics: notchMac))
        check("la zona transparente de la ventana no cuenta como isla", !NotchGeometry.contains(CGPoint(x: 756, y: 800), mode: .compact, metrics: notchMac))

        // 10. animacion de personaje
        let calm = CGPoint.zero
        func pose(_ t: TimeInterval, gaze: CGPoint = calm, pokes: [TimeInterval] = [], hop: TimeInterval? = nil, motion: Bool = true) -> PetPose {
            PetAnimator.pose(at: t, gaze: gaze, pokes: pokes, hopStart: hop, motion: motion)
        }
        let scales = stride(from: 0.0, to: 8.0, by: 0.05).map { pose($0).scaleY }
        check("respira entre 1,00 y 1,04 y sube y baja", scales.min()! >= 1 && scales.max()! <= 1.0401 && scales.max()! - scales.min()! > 0.03)
        check("la respiracion se repite cada 4 s", abs(pose(1).scaleY - pose(5).scaleY) < 1e-9)
        var blinkFrames = 0, blinkStarts = 0, wasBlinking = false
        for k in 0..<6000 { let b = PetAnimator.isBlinking(at: Double(k) / 100); if b { blinkFrames += 1 }; if b && !wasBlinking { blinkStarts += 1 }; wasBlinking = b }
        check("en 60 s parpadea entre 12 y 45 veces", (12...45).contains(blinkStarts))
        check("cada parpadeo dura poco: menos del 8 % del tiempo con los ojos cerrados", blinkFrames < 480)
        check("con movimiento reducido no respira ni parpadea", { let q = pose(1.2, motion: false); return q.scaleY == 1 && !q.blink && q.dy == 0 }())
        check("la mirada sigue al cursor: derecha, izquierda, arriba y abajo",
              PetAnimator.eyes(gaze: CGPoint(x: 1, y: 0)) == (1, 0) && PetAnimator.eyes(gaze: CGPoint(x: -1, y: 0)) == (-1, 0)
              && PetAnimator.eyes(gaze: CGPoint(x: 0, y: 1)) == (0, -1) && PetAnimator.eyes(gaze: CGPoint(x: 0, y: -1)) == (0, 1))
        check("con el cursor cerca del centro mira al frente", PetAnimator.eyes(gaze: CGPoint(x: 0.1, y: -0.2)) == (0, 0))
        check("la mirada sigue funcionando con movimiento reducido", pose(1, gaze: CGPoint(x: 1, y: 0), motion: false).eyeDX == 1)
        check("un toque sacude el cuerpo", (1..<10).contains { abs(pose(10 + Double($0) * 0.03, pokes: [10]).dx) > 0.2 })
        check("la sacudida termina a los 0,35 s", pose(10.5, pokes: [10]).dx == 0)
        let three: [TimeInterval] = [10, 10.4, 10.8]
        check("tres toques seguidos marean", pose(11.2, pokes: three).dizzy && pose(11.2, pokes: three).rotation != 0)
        check("el mareo pasa a los 1,8 s", !pose(12.7, pokes: three).dizzy)
        check("dos toques espaciados no marean", !pose(11, pokes: [5, 10.5]).dizzy)
        check("el salto sube a media altura y vuelve al suelo", { let top = pose(20.3, hop: 20).dy; return top < -2.9 && pose(20.7, hop: 20).dy == 0 && pose(19.9, hop: 20).dy == 0 }())

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
