import Foundation
import Combine

/// `ClaudePet --selftest-focus`: modo foco con horario y temporizador pomodoro.
enum FocusPomodoroSelfTest {
    @MainActor static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int) -> Date { cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: 10, day: 27, hour: h))! }

        var focus = FocusMode()
        check("sin activar no hay foco", !focus.isActive(at: at(10), calendar: cal))
        focus.manual = true
        check("manual siempre esta activo", focus.isActive(at: at(3), calendar: cal))
        focus = FocusMode(manual: false, scheduleStart: 9, scheduleEnd: 17)
        check("el horario de dia cubre su rango", focus.isActive(at: at(9), calendar: cal) && focus.isActive(at: at(16), calendar: cal) && !focus.isActive(at: at(17), calendar: cal) && !focus.isActive(at: at(8), calendar: cal))
        focus = FocusMode(manual: false, scheduleStart: 22, scheduleEnd: 7)
        check("el horario puede cruzar la medianoche", focus.isActive(at: at(23), calendar: cal) && focus.isActive(at: at(2), calendar: cal) && !focus.isActive(at: at(7), calendar: cal) && !focus.isActive(at: at(12), calendar: cal))
        check("un horario con inicio igual al fin no hace nada", !FocusMode(manual: false, scheduleStart: 8, scheduleEnd: 8).isActive(at: at(8), calendar: cal))
        check("un horario fuera de rango se ignora", !FocusMode(manual: false, scheduleStart: 25, scheduleEnd: 3).isActive(at: at(1), calendar: cal))
        check("con foco solo suenan las alertas", FocusMode().allows(.permission, active: true) && FocusMode().allows(.error, active: true) && !FocusMode().allows(.done, active: true) && !FocusMode().allows(.hover, active: true) && FocusMode().allows(.done, active: false))

        var p = Pomodoro()
        check("al inicio esta parado", p.phase == .idle && !p.isRunning && p.remaining(now: 0) == 0)
        p.start(now: 100)
        check("empieza una fase de trabajo de 25 min", p.phase == .work && p.label(now: 100) == "25:00" && p.isRunning)
        check("el reloj descuenta", p.label(now: 160) == "24:00")
        check("antes de agotarse no cambia de fase", p.tick(now: 100 + 1499) == nil && p.phase == .work)
        check("al agotarse pasa a descanso corto", p.tick(now: 100 + 1500) == .shortBreak && p.onBreak && p.completed == 1)
        check("el descanso dura 5 min", p.remaining(now: 100 + 1500) == 300 && p.label(now: 100 + 1500) == "05:00")
        let breakStart = 100.0 + 1500
        check("tras el descanso vuelve al trabajo", p.tick(now: breakStart + 300) == .work && p.phase == .work)
        var q = Pomodoro(); q.start(now: 0)
        var now = 0.0
        for _ in 0..<3 { now += Pomodoro.work; q.tick(now: now); now += Pomodoro.shortBreak; q.tick(now: now) }
        now += Pomodoro.work
        check("el cuarto trabajo termina en descanso largo", q.tick(now: now) == .longBreak && q.length(of: .longBreak) == 900 && q.completed == 4)

        var z = Pomodoro(); z.start(now: 0)
        z.pause(now: 600)
        check("en pausa el tiempo no corre", z.isPaused && !z.isRunning && z.remaining(now: 600) == z.remaining(now: 5000) && z.tick(now: 99999) == nil)
        z.resume(now: 5000)
        check("al reanudar sigue donde se quedo", abs(z.remaining(now: 5000) - (Pomodoro.work - 600)) < 0.01 && z.isRunning)
        z.stop()
        check("parar lo deja todo a cero", z.phase == .idle && z.completed == 0)
        var w = Pomodoro(); w.start(now: 0); w.pause(now: 10); w.pause(now: 20)
        check("pausar dos veces no pierde el instante de la primera", abs(w.remaining(now: 30) - (Pomodoro.work - 10)) < 0.01)

        // la tienda: parado no publica nada y en marcha avanza de fase
        let store = PetStore.shared
        let before = store.pomodoro
        store.pomodoro = Pomodoro()
        var publications = 0
        let token = store.objectWillChange.sink { _ in publications += 1 }
        _ = store.tickPomodoro(now: 10); _ = store.tickPomodoro(now: 11)
        check("con el pomodoro parado, tickear no avisa a la interfaz", publications == 0 && store.pomodoroLabel(now: 10) == nil)
        store.pomodoro.start(now: 100)
        check("en marcha muestra el tiempo y el modo", store.pomodoroLabel(now: 100) == "foco 25:00")
        check("al agotarse avanza a descanso y cambia el texto", store.tickPomodoro(now: 100 + 1500) == .shortBreak && store.pomodoroLabel(now: 100 + 1500) == "descanso 05:00")
        token.cancel(); store.pomodoro = before

        print(failures == 0 ? "FOCO OK" : "FOCO FALLOS: \(failures)")
        return failures == 0
    }
}
