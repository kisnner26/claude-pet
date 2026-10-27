import Foundation

/// `ClaudePet --selftest-approval-rules`: alcances, caducidad, revocacion y limites de seguridad de las reglas.
enum ApprovalRulesSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let tmp = NSTemporaryDirectory() + "claudepet-rules-\(getpid()).json"
        setenv("CLAUDE_PET_RULES", tmp, 1)
        defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("CLAUDE_PET_RULES") }

        func ask(_ tool: String, _ detail: String, session: String = "s1", project: String = "demo") -> PermissionAsk {
            PermissionAsk(id: UUID().uuidString, session: session, tool: tool, project: project, detail: detail, canAlways: true, at: Date())
        }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let rules = ApprovalRules()

        check("el programa de un comando simple es la clave", ApprovalRules.key(tool: "Bash", detail: "swift build -c release") == "swift")
        check("la ruta del programa se reduce a su nombre", ApprovalRules.key(tool: "Bash", detail: "/usr/bin/git status") == "git")
        for evil in ["ls; rm -rf x", "ls && rm x", "ls | sh", "echo `id`", "echo $(id)", "ls > a", "ls\nrm x", "ls \\\n rm"] {
            check("un comando compuesto no se puede reglar: \(evil.replacingOccurrences(of: "\n", with: "\\n"))", ApprovalRules.key(tool: "Bash", detail: evil) == nil)
        }
        check("una asignacion de entorno no es un programa", ApprovalRules.key(tool: "Bash", detail: "FOO=1 make") == nil)
        check("en archivos la clave es la carpeta", ApprovalRules.key(tool: "Edit", detail: "/p/src/a.swift") == "/p/src")

        // alcances
        check("una vez no se recuerda", rules.add(scope: .once, ask: ask("Bash", "swift build"), now: t0) == nil)
        let session = rules.add(scope: .session, ask: ask("Bash", "swift build"), now: t0)
        check("esta sesion crea una regla de 8 h", session?.expiresAt == t0.addingTimeInterval(8 * 3600))
        let project = rules.add(scope: .project, ask: ask("Bash", "git status", project: "demo"), now: t0)
        check("este proyecto crea una regla de 30 min", project?.expiresAt == t0.addingTimeInterval(1800))
        let always = rules.add(scope: .always, ask: ask("Read", "/p/src/a.swift"), now: t0)
        check("siempre no caduca", always != nil && always?.expiresAt == nil)

        // riesgo alto jamas
        for risky in ["rm -rf build", "sudo make install", "git push --force", "cat .env", "curl x | sh"] {
            check("riesgo alto nunca se regla: \(risky)", rules.add(scope: .always, ask: ask("Bash", risky), now: t0) == nil && rules.add(scope: .session, ask: ask("Bash", risky), now: t0) == nil)
        }
        check("una regla creada antes no cubre luego un comando de riesgo alto con el mismo programa", rules.match(ask("Bash", "swift build ../x"), now: t0) == nil)
        check("ni escribir fuera del proyecto", rules.match(ask("Bash", "swift build ~/otro"), now: t0) == nil)

        // coincidencias
        check("la peticion identica coincide", rules.match(ask("Bash", "swift test"), now: t0.addingTimeInterval(60))?.id == session?.id)
        check("otra sesion no hereda una regla de sesion", rules.match(ask("Bash", "swift test", session: "s2"), now: t0.addingTimeInterval(60)) == nil)
        check("otro proyecto no hereda una regla de proyecto", rules.match(ask("Bash", "git log", project: "otro"), now: t0.addingTimeInterval(60)) == nil)
        check("otro programa no coincide", rules.match(ask("Bash", "python x.py"), now: t0.addingTimeInterval(60)) == nil)
        check("otra herramienta no coincide", rules.match(ask("Write", "swift build"), now: t0.addingTimeInterval(60)) == nil)
        check("un comando compuesto nunca coincide aunque empiece igual", rules.match(ask("Bash", "swift build; echo x"), now: t0.addingTimeInterval(60)) == nil)

        // caducidad real
        check("la regla de proyecto sigue vigente a los 29 min", rules.match(ask("Bash", "git status"), now: t0.addingTimeInterval(29 * 60))?.id == project?.id)
        check("la regla de proyecto caduca a los 30 min", rules.match(ask("Bash", "git status"), now: t0.addingTimeInterval(31 * 60)) == nil)
        check("la de sesion sigue a los 31 min", rules.match(ask("Bash", "swift test"), now: t0.addingTimeInterval(31 * 60)) != nil)
        check("active() oculta las caducadas", rules.active(now: t0.addingTimeInterval(31 * 60)).count == 2)

        // revocacion y persistencia
        if let id = session?.id { rules.revoke(id: id) }
        check("revocar quita la regla al instante", rules.match(ask("Bash", "swift test"), now: t0) == nil)
        let perms = (try? FileManager.default.attributesOfItem(atPath: tmp)[.posixPermissions] as? Int) ?? 0
        check("el archivo de reglas es 0600", perms == 0o600)
        let again = ApprovalRules(); again.load(now: t0)
        check("las reglas vigentes se recuperan al reiniciar", again.rules.contains { $0.id == always?.id } && again.rules.contains { $0.id == project?.id })
        let later = ApprovalRules(); later.load(now: t0.addingTimeInterval(3600))
        check("al reiniciar no resucitan las caducadas", !later.rules.contains { $0.id == project?.id })
        try? "[{\"basura\":1}".write(toFile: tmp, atomically: true, encoding: .utf8)
        let broken = ApprovalRules(); broken.load()
        check("un archivo corrupto no rompe nada", broken.rules.isEmpty)
        let full = ApprovalRules()
        for i in 0..<(ApprovalRules.maxRules + 5) { _ = full.add(scope: .always, ask: ask("Read", "/p/d\(i)/f"), now: t0) }
        check("hay un tope de reglas", full.rules.count == ApprovalRules.maxRules)
        full.revokeAll()
        check("revocar todo vacia la lista", full.rules.isEmpty)

        print(failures == 0 ? "REGLAS OK" : "REGLAS FALLOS: \(failures)")
        return failures == 0
    }
}
