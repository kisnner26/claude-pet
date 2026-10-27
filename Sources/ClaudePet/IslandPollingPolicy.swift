import Foundation

enum IslandPollingPolicy {
    /// treinta actualizaciones por segundo mantienen el seguimiento fluido sin forzar
    /// una reevaluación de toda la isla a 60 hz.
    static let activeInterval: TimeInterval = 1.0 / 30.0
    static let idleInterval: TimeInterval = 1.0

    static func interval(hidden: Bool, tasksRunning: Bool, attention: Bool) -> TimeInterval {
        hidden && !tasksRunning && !attention ? idleInterval : activeInterval
    }
}
