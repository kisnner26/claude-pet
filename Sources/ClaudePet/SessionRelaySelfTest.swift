import Foundation

/// `ClaudePet --selftest-relay`: formato, contexto generado y permisos del almacén local.
enum SessionRelaySelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ value: @autoclosure () -> Bool) {
            let passed = value()
            print((passed ? "PASS " : "FAIL ") + name)
            if !passed { failures += 1 }
        }
        let root = NSTemporaryDirectory() + "claudepet-relay-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        _ = GitPulse.run(arguments: ["-C", root, "init", "-b", "main"], timeout: 10)
        _ = GitPulse.run(arguments: ["-C", root, "config", "user.email", "tests@local.invalid"], timeout: 10)
        _ = GitPulse.run(arguments: ["-C", root, "config", "user.name", "ClaudePet Tests"], timeout: 10)
        try? Data("base\n".utf8).write(to: URL(fileURLWithPath: root + "/README.md"))
        _ = GitPulse.run(arguments: ["-C", root, "add", "."], timeout: 10)
        _ = GitPulse.run(arguments: ["-C", root, "commit", "-m", "base"], timeout: 10)
        try? Data("cambio\n".utf8).write(to: URL(fileURLWithPath: root + "/README.md"))

        let prior = SessionCapsuleStore.directory
        SessionCapsuleStore.directory = URL(fileURLWithPath: root + "/handoff")
        defer { SessionCapsuleStore.directory = prior }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let health = GitPulse.scan(root)
        guard let capsule = try? SessionCapsuleFactory.make(source: .claude, workspace: root, project: "demo", task: "terminar el relevo", state: .thinking, health: health, now: now) else {
            print("FAIL crea cápsula"); return false
        }
        check("la cápsula conserva tarea y huella git", capsule.task == "terminar el relevo" && capsule.branch == "main" && !capsule.revision.isEmpty)
        let prompt = SessionCapsulePrompt.build(capsule, destination: .codex)
        check("el prompt exige verificar estado y no contiene secretos", prompt.contains("verifica") && prompt.contains(root) && !prompt.contains("token"))
        guard let url = try? SessionCapsuleStore.save(capsule) else { print("FAIL guarda cápsula"); return false }
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
        check("la cápsula se guarda en 0600", mode == 0o600)
        let loaded = try? SessionCapsuleStore.latest(now: now)
        check("se recupera la última cápsula vigente", loaded?.capsule.id == capsule.id)
        let expired = SessionCapsule(version: SessionCapsule.version, id: UUID(), createdAt: now, expiresAt: now,
                                     source: .claude, project: "x", workspace: root, branch: "", revision: "", gitSummary: "", task: "", state: "", nextStep: "")
        _ = try? SessionCapsuleStore.save(expired)
        let stillValid = try? SessionCapsuleStore.latest(now: now)
        check("las cápsulas vencidas se ignoran", stillValid?.capsule == capsule)
        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
