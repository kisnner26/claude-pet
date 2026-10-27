import Foundation

/// `ClaudePet --selftest-batch`: aprobacion por lotes solo de lecturas iguales.
enum ApprovalBatchSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        func ask(_ tool: String, _ detail: String, project: String = "p", session: String = "s") -> PermissionAsk {
            PermissionAsk(id: UUID().uuidString, session: session, tool: tool, project: project, detail: detail, canAlways: false, at: Date())
        }
        check("una sola lectura no forma lote", ApprovalBatch.group([ask("Read", "/p/src/a.swift")]).isEmpty)
        let reads = [ask("Read", "/p/src/a.swift"), ask("Read", "/p/src/b.swift"), ask("Read", "/p/src/c.swift")]
        check("tres lecturas de la misma carpeta forman lote", ApprovalBatch.group(reads).count == 3)
        check("otra carpeta queda fuera del lote", ApprovalBatch.group(reads + [ask("Read", "/p/docs/x.md")]).count == 3)
        check("otra herramienta queda fuera", ApprovalBatch.group(reads + [ask("Grep", "/p/src/q")]).count == 3)
        check("otra sesion queda fuera", ApprovalBatch.group(reads + [ask("Read", "/p/src/d.swift", session: "otra")]).count == 3)
        check("otro proyecto queda fuera", ApprovalBatch.group(reads + [ask("Read", "/p/src/d.swift", project: "otro")]).count == 3)
        check("las ediciones nunca se agrupan", ApprovalBatch.group([ask("Edit", "/p/src/a.swift"), ask("Edit", "/p/src/b.swift")]).isEmpty)
        check("Bash nunca se agrupa", ApprovalBatch.group([ask("Bash", "ls"), ask("Bash", "ls")]).isEmpty)
        check("una lectura de riesgo alto rompe el lote", ApprovalBatch.group([ask("Read", "/p/src/a.swift"), ask("Read", "/p/src/../../.env")]).isEmpty)
        check("un archivo secreto no entra aunque sea lectura", ApprovalBatch.group(reads + [ask("Read", "/p/src/.env")]).count == 3)
        let many = (0..<20).map { ask("Read", "/p/src/f\($0).swift") }
        check("el lote se acota a 8", ApprovalBatch.group(many).count == ApprovalBatch.maximum)
        check("la primera peticion manda: si no es lectura no hay lote", ApprovalBatch.group([ask("Write", "/p/src/a")] + reads).isEmpty)
        print(failures == 0 ? "LOTES OK" : "LOTES FALLOS: \(failures)")
        return failures == 0
    }
}
