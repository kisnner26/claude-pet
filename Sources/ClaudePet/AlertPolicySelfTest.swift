import Foundation

enum AlertPolicySelfTest {
    static func run() -> Bool {
        let ok = AlertDisplayMode.allowsAll
        print(ok ? "ALERTAS OK" : "ALERTAS FALLOS")
        return ok
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
