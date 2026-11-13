import Foundation

/// `ClaudePet --selftest-claudemd`: la auditoria de CLAUDE.md y el generador del borrador con un proyecto de muestra.
enum ClaudeMdSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15
        let savedLang = L.current
        defer { L.current = savedLang }
        L.current = .es

        // auditoria
        check("sin archivo: falta", ClaudeMdAudit.audit(text: nil, now: now).findings == [.missing])
        check("vacio", ClaudeMdAudit.audit(text: "  \n", now: now).findings == [.empty])
        check("corto y sano no avisa", ClaudeMdAudit.audit(text: "# app\n\nusa swift build.\n", now: now).isHealthy)
        let long = String(repeating: "una linea de reglas del proyecto\n", count: 250)       // ~8000 caracteres ~ 2300 tokens
        let longAudit = ClaudeMdAudit.audit(text: long, now: now)
        check("largo avisa con tokens estimados a 3,5 caracteres", longAudit.findings.contains { if case .long(let t) = $0 { return t == TokenEstimate.tokens(long) } else { return false } })
        check("la estimacion es caracteres / 3,5 redondeada hacia arriba", TokenEstimate.tokens(characters: 7) == 2 && TokenEstimate.tokens(characters: 8) == 3 && TokenEstimate.tokens(characters: 0) == 0)
        let huge = String(repeating: "x", count: 20_000)
        check("muy largo", ClaudeMdAudit.audit(text: huge, now: now).findings.contains { if case .veryLong = $0 { return true } else { return false } })
        let aging = ClaudeMdAudit.audit(text: "# app\n## Pendientes\n- algo\n## Estado actual\nrama 1.2\n## Arquitectura\nfija\n", now: now)
        check("detecta secciones que envejecen", aging.findings.contains(.agingSection(heading: "Pendientes")) && aging.findings.contains(.agingSection(heading: "Estado actual")))
        check("no marca secciones estables", !aging.findings.contains(.agingSection(heading: "Arquitectura")))
        check("la palabra debe ser entera", ClaudeMdAudit.audit(text: "## Todos los modulos\n", now: now).isHealthy)
        let dated = ClaudeMdAudit.audit(text: "## Notas\nsubido el 2026-03-01 a prod\ny el 2027-01-10 de nuevo\n", now: now)
        check("fecha de hace mas de 90 dias", dated.findings == [.staleDate(heading: "Notas", date: "2026-03-01")])
        check("los mensajes salen en espanol", ClaudeMdAudit.Finding.missing.message.hasPrefix("no tiene"))
        L.current = .en
        check("y en ingles", ClaudeMdAudit.Finding.missing.message.hasPrefix("no CLAUDE.md"))
        L.current = .es

        // proyecto de muestra
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sample-\(UUID().uuidString)/mi-app")
        defer { try? fm.removeItem(at: root.deletingLastPathComponent()) }
        func put(_ path: String, _ text: String) {
            let url = root.appendingPathComponent(path)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        put("Package.swift", "// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: \"MiApp\", targets: [.executableTarget(name: \"MiApp\"), .testTarget(name: \"MiAppTests\")])\n")
        for i in 0..<6 { put("Sources/MiApp/F\(i).swift", "let x = \(i)\n") }
        put("Tests/MiAppTests/T.swift", "// t\n")
        put("web/app.ts", "export {}\n"); put("web/b.ts", "export {}\n")
        put("package.json", #"{"scripts":{"dev":"vite","build":"vite build","test":"vitest","postinstall":"x"}}"#)
        put("pnpm-lock.yaml", "")
        put("Makefile", "build:\n\tswift build\n.PHONY: build\nclean:\n\trm -rf .build\nVAR := 1\n")
        put("tests/run.sh", "#!/bin/sh\n")
        put(".swiftlint.yml", "disabled_rules: []\n")
        put("README.md", "# mi app\n"); put("docs/GUIA.md", "# guia\n")
        put("node_modules/zzz/index.js", "ignorado")
        put(".build/ignorado.swift", "ignorado")
        put("CLAUDE.md", "# reglas mias\nNO TOCAR\n")
        for subject in ["feat: a", "fix: b", "feat(ui): c", "docs: d", "test: e", "feat: f"] {
            put("c.txt", subject)
            for args in [["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", subject]] where !(args[0] == "init" && fm.fileExists(atPath: root.appendingPathComponent(".git").path)) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", root.path] + args
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try? p.run(); p.waitUntilExit()
            }
        }

        let draft = ProjectSummary.generate(folder: root)
        check("el borrador cabe en 1500 tokens", TokenEstimate.tokens(draft) <= ProjectSummary.tokenBudget)
        check("es determinista", draft == ProjectSummary.generate(folder: root))
        check("detecta swift build y swift test", draft.contains("`swift build`") && draft.contains("`swift test`"))
        check("detecta el ejecutable de Package.swift", draft.contains("`swift run MiApp`"))
        check("detecta scripts de package.json con el gestor correcto", draft.contains("`pnpm run dev`") && draft.contains("`pnpm test`") && !draft.contains("postinstall"))
        check("detecta objetivos de Makefile y no variables", draft.contains("`make build`") && draft.contains("`make clean`") && !draft.contains("make VAR"))
        check("lista los scripts de pruebas", draft.contains("`tests/run.sh`"))
        check("lenguajes por numero de archivos", draft.contains("Swift (") && draft.contains("TypeScript (2 archivos)"))
        check("estructura sin carpetas de ruido", draft.contains("`Sources/`") && !draft.contains("node_modules") && !draft.contains(".build"))
        check("convenciones: lint y prefijos de commit", draft.contains("SwiftLint") && draft.contains("`feat:`"))
        check("documentacion existente", draft.contains("`README.md`") && draft.contains("`docs/GUIA.md`"))
        check("no cita el nombre ni la ruta del usuario", !draft.contains(NSHomeDirectory()))

        // escritura: nunca pisa CLAUDE.md ni borradores anteriores
        let first = try? ProjectSummary.writeDraft(draft, in: root)
        let second = try? ProjectSummary.writeDraft(draft, in: root)
        check("escribe CLAUDE.md.borrador", first?.lastPathComponent == "CLAUDE.md.borrador")
        check("el segundo borrador no pisa el primero", second?.lastPathComponent == "CLAUDE.md.borrador.2")
        check("CLAUDE.md existente intacto", (try? String(contentsOf: root.appendingPathComponent("CLAUDE.md"), encoding: .utf8)) == "# reglas mias\nNO TOCAR\n")
        check("la auditoria de la carpeta lee el CLAUDE.md real", ClaudeMdAudit.audit(folder: root, now: now).exists)
        check("carpeta sin CLAUDE.md: falta", ClaudeMdAudit.audit(folder: root.appendingPathComponent("web"), now: now).findings == [.missing])
        check("carpeta vacia no rompe", !ProjectSummary.generate(folder: root.appendingPathComponent("web/../docs")).isEmpty)

        // presupuesto: un proyecto enorme sigue cabiendo
        for i in 0..<200 { put("modulo\(i)/a.py", "x = 1\n") }
        for i in 0..<40 { put("Makefile.d/\(i).txt", "x") }
        put("Makefile", (0..<60).map { "t\($0):\n\techo\n" }.joined())
        check("con mucha estructura sigue cabiendo", TokenEstimate.tokens(ProjectSummary.generate(folder: root)) <= ProjectSummary.tokenBudget)

        print(failures == 0 ? "CLAUDEMD OK" : "CLAUDEMD \(failures) FALLOS")
        return failures == 0
    }
}
