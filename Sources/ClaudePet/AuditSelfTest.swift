import Foundation

enum AuditSelfTest {
    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claudepet-audit-\(UUID().uuidString)").path
        setenv("CLAUDE_PET_AUDIT", root, 1)
        let ask = PermissionAsk(id: "audit", session: "s", tool: "Read", project: "demo", detail: "src/a", canAlways: false, at: Date())
        AuditLog.record(ask: ask, result: "allow")
        let path = root + "/decisions.jsonl"
        let ok = FileManager.default.fileExists(atPath: path) && (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue == 0o600
        AuditLog.record(ask: ask, result: "deny")
        AuditLog.record(ask: ask, result: "terminal", source: "terminal")
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let entries = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(AuditEntry.self, from: Data($0.utf8)) }
        let retained = !entries.isEmpty && entries.allSatisfy { $0.tool == "Read" }
        let final = ok && retained && AuditLog.markdown().contains("| herramienta |")
        print(final ? "AUDITORIA OK" : "AUDITORIA FALLOS")
        return final
    }
}
