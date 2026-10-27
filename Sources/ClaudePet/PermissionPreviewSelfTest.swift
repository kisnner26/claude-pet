import Foundation

enum PermissionPreviewSelfTest {
    static func run() -> Bool {
        let edit = PermissionPreviewBuilder.make(tool: "Edit", detail: (0..<45).map { "+ línea \($0)" }.joined(separator: "\n"), project: "demo")
        let bash = PermissionPreviewBuilder.make(tool: "Bash", detail: "swift test", project: "claude-pet")
        let ok = edit.lines.count == 40 && edit.truncated && bash.title.contains("claude-pet") && bash.lines == ["swift test"]
        print(ok ? "VISTA PREVIA OK" : "VISTA PREVIA FALLOS")
        return ok
    }
}
