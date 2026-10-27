import Foundation

enum PerimeterSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        // patrones
        let cases: [(String, String, Bool)] = [
            ("*.swift", "Sources/App/Main.swift", true), ("Sources/*.swift", "Sources/App/Main.swift", false), ("Sources/**", "Sources/App/Main.swift", true),
            ("Sources/**/*.swift", "Sources/Main.swift", true), ("Sources/**/*.swift", "Sources/a/b/c/Main.swift", true), ("**/Main.swift", "Main.swift", true),
            (".env*", ".env", true), (".env*", "app/.env.local", true), (".env*", "app/env.txt", false), ("*.PEM", "keys/server.pem", true),
            (".git/**", ".git/config", true), (".git/**", ".github/ci.yml", false), (".github/**", ".github/ci.yml", true),
            ("Sources/", "Sources/a.swift", true), ("a?c", "abc", true), ("a?c", "abbc", false), ("", "x", false), ("**", "any/thing", true), ("docs", "docs/readme.md", false),
            ("Sources/Auth", "Sources/Auth/Login.swift", false),
        ]
        for (pattern, path, want) in cases { check("glob \(pattern) vs \(path)", Glob.matches(pattern, path) == want) }

        let root = "/tmp/claudepet-perimeter-test/proj"
        var p = Perimeter(root: root, allow: ["Sources/Auth", "Tests/**"], protect: Perimeter.defaultProtect, mode: .ask)
        check("inside", p.evaluate(tool: "Edit", path: root + "/Sources/Auth/Login.swift") == .inside)
        check("inside-glob", p.evaluate(tool: "Write", path: root + "/Tests/A/B.swift") == .inside)
        check("outside", p.evaluate(tool: "Edit", path: root + "/Sources/Billing/Pay.swift") == .outside("Sources/Billing/Pay.swift"))
        check("protected-wins", p.evaluate(tool: "Edit", path: root + "/Sources/Auth/.env") == .protected(".env*"))
        check("protected-git", p.evaluate(tool: "MultiEdit", path: root + "/.git/hooks/pre-commit") == .protected(".git/**"))
        check("dotdot-escape", p.evaluate(tool: "Edit", path: root + "/Sources/Auth/../Billing/Pay.swift") == .outside("Sources/Billing/Pay.swift"))
        check("dotdot-out-of-root", p.evaluate(tool: "Edit", path: root + "/../other/x.swift") == .none)
        check("sibling-prefix", p.evaluate(tool: "Edit", path: root + "-evil/x.swift") == .none)
        check("read-ignored", p.evaluate(tool: "Read", path: root + "/Sources/Billing/Pay.swift") == .none && p.evaluate(tool: "Bash", path: root + "/x") == .none)
        check("relative-ignored", p.evaluate(tool: "Edit", path: "Sources/Billing/Pay.swift") == .none)
        check("case-insens-tool", p.evaluate(tool: "edit", path: root + "/Sources/Billing/Pay.swift").isViolation)
        p.allow = []
        check("empty-allow-is-whole-project", p.evaluate(tool: "Edit", path: root + "/anything/at/all.swift") == .inside)
        check("empty-allow-still-protects", p.evaluate(tool: "Edit", path: root + "/deploy/key.pem").isViolation)
        check("reason", PerimeterVerdict.outside("a/b").reason.contains("a/b") && PerimeterVerdict.protected(".env*").reason.contains(".env*") && PerimeterVerdict.inside.reason.isEmpty)

        // validacion
        check("valid", Perimeter(root: root).isValid)
        check("invalid-root", !Perimeter(root: "relative/path").isValid)
        check("invalid-glob", !Perimeter(root: root, allow: [""]).isValid && !Perimeter(root: root, allow: ["a\nb"]).isValid && !Perimeter(root: root, allow: [String(repeating: "x", count: 500)]).isValid)
        check("invalid-count", !Perimeter(root: root, allow: Array(repeating: "a", count: 31)).isValid)

        // almacen
        let file = NSTemporaryDirectory() + "perimeters-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: file) }
        let store = PerimeterStore()
        let outer = Perimeter(root: root, allow: ["Sources/**"], mode: .block)
        let inner = Perimeter(root: root + "/Sources/Auth", allow: ["Login"], mode: .ask)
        check("upsert", store.upsert(outer) && store.upsert(inner) && !store.upsert(Perimeter(root: "nope")))
        check("most-specific", store.perimeter(covering: root + "/Sources/Auth/Login.swift")?.root == inner.root && store.perimeter(covering: root + "/Sources/X.swift")?.root == outer.root)
        check("verdict-specific", store.verdict(tool: "Edit", detail: root + "/Sources/Auth/Other.swift") == .outside("Other.swift") && store.verdict(tool: "Edit", detail: root + "/Sources/Auth/Login/a.swift") == .inside)
        check("verdict-none", store.verdict(tool: "Edit", detail: "/somewhere/else.swift") == .none)
        store.save(path: file)
        let perms = (try? FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int) ?? 0
        check("file-0600", perms == 0o600)
        let reloaded = PerimeterStore(); reloaded.load(path: file)
        check("roundtrip", reloaded.all() == store.all())
        try? Data("[{\"root\":\"relative\"}]".utf8).write(to: URL(fileURLWithPath: file))
        let bad = PerimeterStore(); bad.load(path: file)
        check("load-drops-invalid", bad.all().isEmpty)
        try? Data("basura".utf8).write(to: URL(fileURLWithPath: file))
        let junk = PerimeterStore(); junk.load(path: file)
        check("load-junk", junk.all().isEmpty)
        store.remove(root: inner.root)
        check("remove", store.all().count == 1)
        var many = PerimeterStore().all(); many = []
        let cap = PerimeterStore()
        var accepted = 0
        for i in 0..<(PerimeterStore.maxPerimeters + 5) where cap.upsert(Perimeter(root: "/tmp/p\(i)")) { accepted += 1 }
        check("cap", accepted == PerimeterStore.maxPerimeters && many.isEmpty)

        // decision de la puerta
        func ask(_ id: String, _ tool: String, _ path: String) -> PermissionAsk { PermissionAsk(id: id, session: "s", tool: tool, project: "p", detail: path, canAlways: true, at: Date()) }
        let gateStore = PerimeterStore()
        gateStore.upsert(Perimeter(root: root, allow: ["Sources/**"], mode: .block))
        let soft = PerimeterStore()
        soft.upsert(Perimeter(root: root, allow: ["Sources/**"], mode: .ask))
        let badAsk = ask("bad", "Edit", root + "/Package.swift"), okAsk = ask("ok", "Edit", root + "/Sources/a.swift"), outsideProject = ask("out", "Edit", "/elsewhere/x")
        check("gate-block-denies", PermissionGate.decide(asks: [okAsk, badAsk], check: gateStore.check, ruleMatches: { _ in true }) == .deny(id: "bad", reason: "fuera del perímetro: Package.swift"))
        check("gate-ask-mode-never-auto-approves", PermissionGate.decide(asks: [badAsk], check: soft.check, ruleMatches: { _ in true }) == .none)
        check("gate-rule-allows-inside", PermissionGate.decide(asks: [badAsk, okAsk], check: soft.check, ruleMatches: { _ in true }) == .allowByRule(id: "ok"))
        check("gate-rule-allows-without-perimeter", PermissionGate.decide(asks: [outsideProject], check: soft.check, ruleMatches: { _ in true }) == .allowByRule(id: "out"))
        check("gate-nothing", PermissionGate.decide(asks: [okAsk], check: soft.check, ruleMatches: { _ in false }) == .none && PermissionGate.decide(asks: [], check: soft.check, ruleMatches: { _ in true }) == .none)
        check("gate-ignores-bash", PermissionGate.decide(asks: [ask("b", "Bash", "rm -rf /")], check: gateStore.check, ruleMatches: { _ in false }) == .none)

        print(failures == 0 ? "PERIMETRO OK" : "PERIMETRO \(failures) FALLOS")
        return failures == 0
    }
}
