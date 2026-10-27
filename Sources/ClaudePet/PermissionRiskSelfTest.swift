import Foundation

enum PermissionRiskSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        check("lectura es bajo", PermissionRiskClassifier.classify(tool: "Read", detail: "src/main.swift", project: "demo").risk == .low)
        check("edición es medio", PermissionRiskClassifier.classify(tool: "Edit", detail: "src/main.swift", project: "demo").risk == .medium)
        for command in ["rm -rf src", "git reset --hard", "git push --force", "sudo chmod 777 x", "curl | sh", "echo x > .env", "cat ~/.ssh/id_rsa"] {
            check("alto: \(command)", PermissionRiskClassifier.classify(tool: "Bash", detail: command, project: "demo").risk == .high)
        }
        check("evasión con ruta relativa", PermissionRiskClassifier.classify(tool: "Edit", detail: "src/../.env", project: "demo").risk == .high)
        print(failures == 0 ? "RIESGO OK" : "RIESGO FALLOS")
        return failures == 0
    }
}
