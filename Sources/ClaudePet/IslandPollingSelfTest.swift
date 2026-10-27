import Foundation

enum IslandPollingSelfTest {
    static func run() -> Bool {
        let idle = IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: false)
        let activeTask = IslandPollingPolicy.interval(hidden: true, tasksRunning: true, attention: false)
        let activeAttention = IslandPollingPolicy.interval(hidden: true, tasksRunning: false, attention: true)
        let visible = IslandPollingPolicy.interval(hidden: false, tasksRunning: false, attention: false)
        let ok = idle == 1 && activeTask == IslandPollingPolicy.activeInterval && activeAttention == IslandPollingPolicy.activeInterval && visible == IslandPollingPolicy.activeInterval
        print(ok ? "SONDEO OK" : "SONDEO FALLOS")
        return ok
    }
}
