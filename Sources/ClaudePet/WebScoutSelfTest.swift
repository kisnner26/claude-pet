import ApplicationServices
import Foundation

enum WebScoutSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if condition() { print("PASS \(name)") }
            else { failures += 1; print("FAIL \(name)") }
        }

        let regular = CGRect(x: 20, y: 20, width: 80, height: 44)
        let unnamed = WebScoutAuditInput(role: kAXButtonRole as String, title: "", description: "", help: "", frame: regular)
        check("detecta un control sin nombre", WebScoutAudit.finding(for: unnamed)?.tone == .error)

        let named = WebScoutAuditInput(role: kAXButtonRole as String, title: "guardar", description: "", help: "", frame: regular)
        check("acepta un control con nombre", WebScoutAudit.finding(for: named) == nil)

        let small = WebScoutAuditInput(role: "AXLink", title: "documentación", description: "", help: "",
                                       frame: CGRect(x: 20, y: 20, width: 30, height: 18))
        check("detecta un objetivo pequeño", WebScoutAudit.finding(for: small)?.tone == .warning)

        let image = WebScoutAuditInput(role: kAXImageRole as String, title: "", description: "", help: "", frame: regular)
        check("detecta una imagen sin descripción", WebScoutAudit.finding(for: image)?.tone == .error)

        let text = WebScoutAuditInput(role: kAXStaticTextRole as String, title: "", description: "", help: "", frame: regular)
        check("no acusa texto estático", WebScoutAudit.finding(for: text) == nil)

        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
