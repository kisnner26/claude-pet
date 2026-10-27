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

        print(failures == 0 ? "ISLAND OK" : "ISLAND FALLOS: \(failures)")
        return failures == 0
    }
}
