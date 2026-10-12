import Foundation

/// `ClaudePet --selftest-handoff`: comandos de solo lectura, prompt, busqueda de agentes, repos reales,
/// revisiones con agentes simulados (exito, falla, tiempo, cancelacion) y worktree.
enum HandoffSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ value: @autoclosure () -> Bool) {
            let passed = value()
            print((passed ? "PASS " : "FAIL ") + name)
            if !passed { failures += 1 }
        }

        let codex = HandoffCommand.arguments(reviewer: .codex, workspace: "/p", output: "/o")
        check("codex revisa en sandbox read-only", codex.firstIndex(of: "--sandbox").map { codex[$0 + 1] == "read-only" } == true)
        check("codex lee el prompt por stdin y no acepta full-access", codex.last == "-" && !codex.contains("danger-full-access"))
        let claude = HandoffCommand.arguments(reviewer: .claude, workspace: "/p", output: "/o")
        check("claude revisa en modo plan", claude.firstIndex(of: "--permission-mode").map { claude[$0 + 1] == "plan" } == true)
        let tools = claude.firstIndex(of: "--tools").map { claude[$0 + 1].split(separator: ",").sorted() } ?? []
        check("claude solo tiene Read, Grep y Glob", tools == ["Glob", "Grep", "Read"])
        check("el diff nunca va en argv", !(codex + claude).contains { $0.contains("SECRETO-DEL-DIFF") })

        let prompt = HandoffPrompt.build(author: .claude, project: "pet", task: "arregla login", diff: Data("SECRETO-DEL-DIFF".utf8), truncated: true, untracked: ["n.swift"])
        check("el prompt lleva diff, tarea, nuevos y aviso de recorte",
              ["SECRETO-DEL-DIFF", "arregla login", "n.swift", "recortado", "Claude", "pet"].allSatisfy { prompt.contains($0) })

        guard let root = temporaryDirectory() else { print("FAIL crea carpeta temporal"); return false }
        defer { try? FileManager.default.removeItem(atPath: root) }
        Handoff.reviewDirectory = URL(fileURLWithPath: root + "/reviews")

        // busqueda de agentes fuera del PATH
        let bin = root + "/home/.local/bin"
        makeDirectory(bin)
        write(bin + "/fakeagent", "#!/bin/sh\n"); chmod(bin + "/fakeagent")
        check("encuentra un agente en ~/.local/bin sin PATH", AgentLocator.find("fakeagent", home: root + "/home", path: "") == bin + "/fakeagent")
        check("no inventa agentes", AgentLocator.find("noexiste", home: root + "/home", path: "") == nil)

        // preparar: repo limpio, sucio, no-repo y ruta relativa
        let repo = root + "/proyecto"
        makeDirectory(repo); initRepo(repo)
        write(repo + "/a.swift", "let x = 1\n")
        git(repo, ["add", "-A"]); git(repo, ["commit", "-m", "base"])
        if case .failure(let error) = Handoff.prepare(workspace: repo, author: .claude, project: "p", task: "") {
            check("repo limpio: no hay nada que revisar", error.message.contains("no hay cambios"))
        } else { check("repo limpio: no hay nada que revisar", false) }
        write(repo + "/a.swift", "let x = 2\n"); write(repo + "/nuevo.swift", "let y = 1\n")
        if case .success(let ready) = Handoff.prepare(workspace: repo, author: .claude, project: "p", task: "tarea") {
            check("repo sucio: el prompt trae el diff y los archivos nuevos", ready.prompt.contains("+let x = 2") && ready.prompt.contains("nuevo.swift") && ready.bytes == ready.prompt.utf8.count)
        } else { check("repo sucio: el prompt trae el diff y los archivos nuevos", false) }
        write(repo + "/a.swift", String(repeating: "linea\n", count: 60_000))
        if case .success(let big) = Handoff.prepare(workspace: repo, author: .codex, project: "p", task: "") {
            check("un diff enorme se recorta", big.prompt.contains("recortado") && big.bytes < Handoff.promptDiffLimit + 4096)
        } else { check("un diff enorme se recorta", false) }
        makeDirectory(root + "/plano")
        if case .failure = Handoff.prepare(workspace: root + "/plano", author: .claude, project: "", task: "") { check("carpeta sin git: se rechaza", true) } else { check("carpeta sin git: se rechaza", false) }
        if case .failure = Handoff.prepare(workspace: "relativa", author: .claude, project: "", task: "") { check("ruta relativa: se rechaza", true) } else { check("ruta relativa: se rechaza", false) }

        // revisiones con agentes simulados
        let fakes = root + "/fakes"
        makeDirectory(fakes)
        write(fakes + "/ok", "#!/bin/sh\ncat >/dev/null\necho 'hallazgo: sin problemas graves'\n"); chmod(fakes + "/ok")
        write(fakes + "/codex-file", "#!/bin/sh\nout=''\nwhile [ $# -gt 0 ]; do [ \"$1\" = '-o' ] && out=\"$2\"; shift; done\ncat >/dev/null\n[ -n \"$out\" ] && echo 'revision en archivo' > \"$out\"\necho progreso\n"); chmod(fakes + "/codex-file")
        write(fakes + "/fail", "#!/bin/sh\ncat >/dev/null\necho boom >&2\nexit 3\n"); chmod(fakes + "/fail")
        write(fakes + "/slow", "#!/bin/sh\nsleep 30\n"); chmod(fakes + "/slow")

        let good = ReviewJob(reviewer: .claude, workspace: repo, project: "proyecto", prompt: "p", executable: fakes + "/ok")
        good.start(); _ = good.finished.wait(timeout: .now() + 15)
        let text = good.result.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        check("claude simulado: queda hecha la revision con su cabecera", good.state == .done && text.contains("sin problemas graves") && text.contains("Claude sobre cambios de Codex"))
        let mode = (good.result.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.posixPermissions] as? Int }) ?? 0
        check("el archivo de la revision es privado (0600)", mode == 0o600)

        let viaFile = ReviewJob(reviewer: .codex, workspace: repo, project: "proyecto", prompt: "p", executable: fakes + "/codex-file")
        viaFile.start(); _ = viaFile.finished.wait(timeout: .now() + 15)
        let fileText = viaFile.result.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        check("codex simulado: se usa el ultimo mensaje (-o), no el progreso", viaFile.state == .done && fileText.contains("revision en archivo") && !fileText.contains("progreso"))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: Handoff.reviewDirectory.path))?.filter { $0.hasSuffix(".out") } ?? []
        check("no quedan archivos temporales .out", leftovers.isEmpty)

        let failing = ReviewJob(reviewer: .codex, workspace: repo, project: "p", prompt: "p", executable: fakes + "/fail")
        failing.start(); _ = failing.finished.wait(timeout: .now() + 15)
        if case .failed(let message) = failing.state { check("una falla se reporta con el mensaje del agente", message.contains("boom") && failing.result == nil) }
        else { check("una falla se reporta con el mensaje del agente", false) }

        let missing = ReviewJob(reviewer: .codex, workspace: repo, project: "p", prompt: "p", executable: nil)
        let reallyMissing = AgentLocator.find("codex") == nil
        if reallyMissing { missing.start(); if case .failed(let m) = missing.state { check("sin el CLI instalado no se lanza nada", m.contains("no se encontró")) } else { check("sin el CLI instalado no se lanza nada", false) } }
        else { check("sin el CLI instalado no se lanza nada (omitido: codex esta instalado)", true) }

        let slow = ReviewJob(reviewer: .claude, workspace: repo, project: "p", prompt: "p", executable: fakes + "/slow", timeout: 1)
        slow.start(); _ = slow.finished.wait(timeout: .now() + 15)
        if case .failed(let message) = slow.state { check("el tiempo maximo corta la revision", message.contains("tiempo")) } else { check("el tiempo maximo corta la revision", false) }

        let cancelled = ReviewJob(reviewer: .claude, workspace: repo, project: "p", prompt: "p", executable: fakes + "/slow", timeout: 60)
        cancelled.start(); usleep(500_000); cancelled.cancel(); _ = cancelled.finished.wait(timeout: .now() + 15)
        check("cancelar detiene al agente", cancelled.state == .cancelled)

        // worktree
        if let made = try? Handoff.createWorktree(workspace: repo, agent: .codex) {
            check("worktree: carpeta hermana con rama nueva", made.path == root + "/proyecto-pet-codex" && made.branch.hasPrefix("pet/codex-") && FileManager.default.fileExists(atPath: made.path + "/a.swift"))
            check("worktree: el proyecto original no se toca", (try? String(contentsOfFile: repo + "/nuevo.swift", encoding: .utf8)) == "let y = 1\n")
        } else { check("worktree: carpeta hermana con rama nueva", false) }
        check("worktree: no pisa uno existente", (try? Handoff.createWorktree(workspace: repo, agent: .codex)) == nil)
        check("worktree: ruta relativa rechazada", (try? Handoff.createWorktree(workspace: "relativa", agent: .codex)) == nil)

        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }

    private static func chmod(_ path: String) { _ = Foundation.chmod(path, 0o755) }
    private static func temporaryDirectory() -> String? {
        let path = NSTemporaryDirectory() + "claudepet-handoff-" + UUID().uuidString
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true); return path } catch { return nil }
    }
    private static func makeDirectory(_ path: String) { try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
    private static func write(_ path: String, _ text: String) { try? Data(text.utf8).write(to: URL(fileURLWithPath: path)) }
    private static func initRepo(_ workspace: String) {
        git(workspace, ["init", "-b", "main"])
        git(workspace, ["config", "user.name", "ClaudePet Tests"])
        git(workspace, ["config", "user.email", "tests@local.invalid"])
    }
    @discardableResult private static func git(_ workspace: String, _ arguments: [String]) -> Int32 {
        GitPulse.run(arguments: ["-C", workspace] + arguments, timeout: 30)?.status ?? -1
    }
}
