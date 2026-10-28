import Foundation

enum IslandPollingSelfTest {
    static func run() -> Bool {
        let idle = IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: false)
        let activeTask = IslandPollingPolicy.interval(hidden: true, tasksRunning: true, attention: false)
        let activeAttention = IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: true)
        let visible = IslandPollingPolicy.interval(hidden: false, tasksRunning: false, attention: false)
        func check(_ name: String, _ ok: Bool) { if !ok { print("FALLO \(name)") } }
        var extra = true
        func record(_ name: String, _ ok: Bool) { if !ok { extra = false }; check(name, ok) }
        record("compacta en reposo con el cursor lejos baja a 10 Hz", IslandPollingPolicy.interval(hidden: false, tasksRunning: false, attention: false, cursorNearZone: false, compact: true) == IslandPollingPolicy.calmCompactInterval)
        record("compacta con trabajo, aviso o cursor cerca sigue a 30 Hz", IslandPollingPolicy.interval(hidden: false, tasksRunning: true, attention: false, compact: true) == IslandPollingPolicy.activeInterval && IslandPollingPolicy.interval(hidden: false, tasksRunning: false, attention: true, compact: true) == IslandPollingPolicy.activeInterval && IslandPollingPolicy.interval(hidden: false, tasksRunning: false, attention: false, cursorNearZone: true, compact: true) == IslandPollingPolicy.activeInterval)
        let ok = extra && idle == 1 && activeTask == IslandPollingPolicy.activeInterval && activeAttention == IslandPollingPolicy.activeInterval && visible == IslandPollingPolicy.activeInterval
        print(ok ? "SONDEO OK" : "SONDEO FALLOS")
        return ok
    }
}
