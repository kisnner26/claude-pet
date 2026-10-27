import Foundation

enum IslandPollingPolicy {
    static let activeInterval: TimeInterval = 1.0 / 60.0
    static let idleInterval: TimeInterval = 1.0

    static func interval(hidden: Bool, tasksRunning: Bool, attention: Bool) -> TimeInterval {
        hidden && !tasksRunning && !attention ? idleInterval : activeInterval
    }
}
