import Foundation

@MainActor
enum AlertPolicySelfTest {
    static func run() -> Bool {
        let ok = AlertDisplayMode.allowsAll
        let store = PetStore(); store.snoozeAlerts(minutes: 1); let muted = store.alertsAreSnoozed; store.wakeAlerts(); let awake = !store.alertsAreSnoozed
        let final = ok && muted && awake
        print(final ? "ALERTAS OK" : "ALERTAS FALLOS")
        return final
    }
}

private extension AlertDisplayMode {
    static var allowsAll: Bool {
        AlertDisplayMode.allows(.all, critical: true) && AlertDisplayMode.allows(.all, critical: false)
            && AlertDisplayMode.allows(.critical, critical: true) && !AlertDisplayMode.allows(.critical, critical: false)
            && !AlertDisplayMode.allows(.none, critical: true)
    }
    static func allows(_ mode: AlertDisplayMode, critical: Bool) -> Bool { mode.allows(critical: critical) }
}
