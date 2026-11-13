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
        // el cambio, el comando integro y el cwd de un permiso nunca llegan al registro
        var rich = PermissionAsk(id: "audit2", session: "s", tool: "Bash", project: "demo", detail: "echo x", canAlways: false, at: Date())
        rich.rawCommand = "echo SECRETO-DEL-COMANDO"; rich.cwd = "/Users/x/RUTA-PRIVADA"
        rich.change = ChangeWire.build(ChangeRequest(kind: .write, path: "/p/a", edits: [], content: ChangePart(text: "CONTENIDO-DEL-DIFF", omitted: 0)), base: .missing)
        AuditLog.record(ask: rich, result: "allow")
        let after = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let private_ = !after.contains("SECRETO-DEL-COMANDO") && !after.contains("RUTA-PRIVADA") && !after.contains("CONTENIDO-DEL-DIFF")
        let final = ok && private_ && retained && AuditLog.markdown().contains("| herramienta |")
        print(final ? "AUDITORIA OK" : "AUDITORIA FALLOS")
        return final
    }
}
