import Foundation

/// `ClaudePet --selftest-relay`: formato, contexto generado y permisos del almacén local.
@MainActor
enum SessionRelaySelfTest {
    static func run() async -> Bool {
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
        do {
            _ = try SessionCapsuleStore.latest(now: Date())
            check("carpeta de relevo ausente no filtra un error de archivos", false)
        } catch SessionCapsuleError.missing {
            check("carpeta de relevo ausente no filtra un error de archivos", true)
        } catch {
            check("carpeta de relevo ausente no filtra un error de archivos", false)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let empty = root + "/empty"
        try? FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
        do {
            _ = try SessionCapsuleFactory.validateWorkspace(empty)
            check("una carpeta vacía no se presenta como contexto", false)
        } catch SessionCapsuleError.emptyWorkspace {
            check("una carpeta vacía no se presenta como contexto", true)
        } catch {
            check("una carpeta vacía no se presenta como contexto", false)
        }
        let health = GitPulse.scan(root)
        do {
            _ = try SessionCapsuleFactory.make(source: .codex, workspace: root, project: "demo", task: "   ", state: .thinking, health: health, now: now)
            check("no crea una cápsula sin contexto", false)
        } catch SessionCapsuleError.missingContext {
            check("no crea una cápsula sin contexto", true)
        } catch {
            check("no crea una cápsula sin contexto", false)
        }
        guard let capsule = try? SessionCapsuleFactory.make(source: .claude, workspace: root, project: "demo", task: "terminar el relevo", state: .thinking, health: health, now: now) else {
            print("FAIL crea cápsula"); return false
        }
        check("la cápsula conserva tarea y huella git", capsule.task == "terminar el relevo" && capsule.branch == "main" && !capsule.revision.isEmpty)
        check("incluye cambios y commits verificables", capsule.changedFiles?.contains(where: { $0.contains("README.md") }) == true && capsule.recentCommits?.contains(where: { $0.contains("base") }) == true)
        let prompt = SessionCapsulePrompt.build(capsule, destination: .codex)
        check("el prompt exige verificar estado y no contiene secretos", prompt.contains("verifica") && prompt.contains(root) && !prompt.contains("token"))
        guard let url = try? SessionCapsuleStore.save(capsule) else { print("FAIL guarda cápsula"); return false }
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
        check("la cápsula se guarda en 0600", mode == 0o600)
        let directoryMode = (try? FileManager.default.attributesOfItem(atPath: SessionCapsuleStore.directory.path)[.posixPermissions] as? Int) ?? 0
        check("el directorio de relevo es privado (0700)", directoryMode == 0o700)
        let loaded = try? SessionCapsuleStore.latest(now: now)
        check("se recupera la última cápsula vigente", loaded?.capsule.id == capsule.id)
        let expired = SessionCapsule(version: SessionCapsule.version, id: UUID(), createdAt: now, expiresAt: now,
                                     source: .claude, project: "x", workspace: root, branch: "", revision: "", gitSummary: "", task: "", state: "", nextStep: "", changedFiles: nil, recentCommits: nil)
        _ = try? SessionCapsuleStore.save(expired)
        let stillValid = try? SessionCapsuleStore.latest(now: now)
        check("las cápsulas vencidas se ignoran", stillValid?.capsule == capsule)
        let oldEmpty = SessionCapsule(version: SessionCapsule.version, id: UUID(), createdAt: now, expiresAt: now.addingTimeInterval(3600),
                                      source: .codex, project: "empty", workspace: empty, branch: "", revision: "", gitSummary: "sin repositorio git", task: "", state: "", nextStep: "", changedFiles: nil, recentCommits: nil)
        _ = try? SessionCapsuleStore.save(oldEmpty)
        check("ignora relevos anteriores sin tarea ni proyecto", (try? SessionCapsuleStore.latest(now: now).capsule.id) == capsule.id)

        var chosen = empty
        var notices: [String] = []
        var previews: [String] = []
        var copied: [String] = []
        var opened: [Agent] = []
        var revealed: [URL] = []
        var saved: [URL] = []
        let interaction = SessionRelayInteraction(
            chooseWorkspace: { _ in chosen },
            editContext: { _, _, _ in "objetivo: corregir el relevo; terminado: pruebas; siguiente: verificar en claude" },
            preview: { text, _, _ in previews.append(text); return true },
            showSaved: { url, _ in saved.append(url) },
            inform: { _, message in notices.append(message) },
            reveal: { revealed.append($0) },
            copy: { copied.append($0) },
            open: { opened.append($0) }
        )
        let controller = SessionRelayController(interaction: interaction)
        controller.create(source: .codex, workspace: "", task: "", state: .thinking)
        check("seleccionar carpeta vacía muestra un error y no guarda", controller.latest == nil && notices.contains(where: { $0.contains("vacía") }) && saved.isEmpty)
        chosen = root
        controller.create(source: .codex, workspace: "", task: "", state: .thinking)
        check("el flujo guarda contexto real fuera del proyecto", controller.latest?.task.contains("objetivo:") == true && controller.latestURL?.deletingLastPathComponent().resolvingSymlinksInPath().path == SessionCapsuleStore.directory.resolvingSymlinksInPath().path && saved.count == 1)
        check("previsualiza y copia el contenido antes de continuar", previews.count == 1 && copied.count == 1 && copied[0].contains("README.md"))
        controller.continueLatest(in: .claude)
        check("continuar reabre la cápsula y abre el agente destino", previews.count == 2 && copied.count == 2 && opened == [.claude])
        controller.revealLatest()
        check("mostrar archivo apunta al json guardado", revealed.map { $0.resolvingSymlinksInPath().path } == saved.map { $0.resolvingSymlinksInPath().path })
        do {
            let draft = try controller.prepare(source: .claude, workspace: root, context: "continuar desde el panel", state: .thinking)
            check("el panel prepara la dirección correcta", draft.0.source == .claude && draft.1.contains("continúa en Codex"))
            let before = copied.count
            let savedFromPanel = try controller.saveAndContinue(draft.0, prompt: draft.1)
            check("el panel guarda, copia y abre en una acción", savedFromPanel == controller.latestURL && copied.count == before + 1 && opened.last == .codex)
            controller.copyAndContinue(draft.0)
            check("reusar el relevo no crea otro archivo", controller.latestURL == savedFromPanel && opened.last == .codex && copied.count == before + 2)
        } catch {
            check("el panel crea un relevo válido", false)
        }
        do {
            _ = try controller.prepare(source: .codex, workspace: empty, context: "algo", state: .idle)
            check("el panel rechaza carpetas vacías", false)
        } catch SessionCapsuleError.emptyWorkspace {
            check("el panel rechaza carpetas vacías", true)
        } catch {
            check("el panel rechaza carpetas vacías", false)
        }
        let priorCodexRoot = LocalAgentSessionReader.codexRoot
        let priorClaudeRoot = LocalAgentSessionReader.claudeRoot
        defer {
            LocalAgentSessionReader.codexRoot = priorCodexRoot
            LocalAgentSessionReader.claudeRoot = priorClaudeRoot
        }
        let codexSessions = URL(fileURLWithPath: root + "/codex-sessions")
        let claudeSessions = URL(fileURLWithPath: root + "/claude-sessions")
        try? FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: claudeSessions, withIntermediateDirectories: true)
        LocalAgentSessionReader.codexRoot = codexSessions
        LocalAgentSessionReader.claudeRoot = claudeSessions
        let encodedPath = (try? JSONSerialization.data(withJSONObject: root, options: .fragmentsAllowed)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let codexLines = [
            "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\(encodedPath)}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"<external_codex_apps_open_page>{}\"}]}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"# Files mentioned by the user:\\n\"}]}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"arreglar la interfaz\"}]}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"function_call_output\",\"output\":\"secreto de herramienta\"}}",
            "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"interfaz terminada\"}]}}"
        ].joined(separator: "\n") + "\n"
        try? Data(codexLines.utf8).write(to: codexSessions.appendingPathComponent("chat.jsonl"))
        let claudeLines = [
            "{\"type\":\"user\",\"cwd\":\(encodedPath),\"message\":{\"role\":\"user\",\"content\":\"continuar proyecto\"}}",
            "{\"type\":\"assistant\",\"cwd\":\(encodedPath),\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"pensamiento privado\"},{\"type\":\"text\",\"text\":\"trabajo listo\"},{\"type\":\"tool_use\",\"name\":\"Bash\"}]}}"
        ].joined(separator: "\n") + "\n"
        try? Data(claudeLines.utf8).write(to: claudeSessions.appendingPathComponent("chat.jsonl"))
        let codexLocal = LocalAgentSessionReader.recent(for: .codex)
        let claudeLocal = LocalAgentSessionReader.recent(for: .claude)
        check("detecta chats de ambos agentes y su proyecto real", codexLocal.count == 1 && claudeLocal.count == 1 && codexLocal.first?.workspace == root && claudeLocal.first?.workspace == root)
        if let codexLocal = codexLocal.first, let claudeLocal = claudeLocal.first {
            let codexText = try? LocalAgentSessionReader.transcript(codexLocal)
            let claudeText = try? LocalAgentSessionReader.transcript(claudeLocal)
            check("codex extrae solo el diálogo visible", codexText?.contains("arreglar la interfaz") == true && codexText?.contains("interfaz terminada") == true && codexText?.contains("secreto de herramienta") == false && codexText?.contains("external_codex") == false && codexText?.contains("Files mentioned") == false)
            check("claude excluye pensamiento y herramientas", claudeText?.contains("continuar proyecto") == true && claudeText?.contains("trabajo listo") == true && claudeText?.contains("pensamiento privado") == false)
        }
        // Una línea enorme y la última línea sin salto no deben perder los mensajes posteriores.
        let largeURL = codexSessions.appendingPathComponent("large.jsonl")
        let largeData = Data((codexLines + String(repeating: "x", count: 17 * 1024 * 1024) + "\n" + codexLines.trimmingCharacters(in: .newlines)).utf8)
        try? largeData.write(to: largeURL)
        let large = LocalAgentSession(url: largeURL, agent: .codex, workspace: root, title: "grande", modifiedAt: Date())
        let largeExcerpt = try? LocalAgentSessionReader.excerpt(large)
        check("una línea enorme no aborta el chat y conserva el final", largeExcerpt?.skipped == 1 && largeExcerpt?.text.hasSuffix("interfaz terminada") == true)
        let single = claudeSessions.appendingPathComponent("single.jsonl")
        try? Data((claudeLines.split(separator: "\n").first.map(String.init) ?? "").utf8).write(to: single)
        check("indexa una sesión sin salto de línea final", LocalAgentSessionReader.recent(for: .claude).contains { $0.url.resolvingSymlinksInPath().path == single.resolvingSymlinksInPath().path })
        if let zstd = AgentLocator.find("zstd") {
            let archive = codexSessions.appendingPathComponent("compressed.jsonl.zst")
            let compressor = Process()
            compressor.executableURL = URL(fileURLWithPath: zstd)
            compressor.arguments = ["-q", "-f", codexSessions.appendingPathComponent("chat.jsonl").path, "-o", archive.path]
            try? compressor.run(); compressor.waitUntilExit()
            let compressed = LocalAgentSessionReader.recent(for: .codex).first { $0.url.resolvingSymlinksInPath().path == archive.resolvingSymlinksInPath().path }
            check("detecta y lee sesiones comprimidas", compressed.flatMap { try? LocalAgentSessionReader.transcript($0) }?.contains("interfaz terminada") == true)
        }
        let flow = SessionRelayModel(relay: controller)
        flow.source = .claude
        flow.manual = true
        flow.workspace = root
        flow.context = "continuar la tarea de prueba"
        await flow.prepare()
        flow.prompt = "contexto revisado por el usuario"
        await flow.complete(open: false)
        check("guarda y copia exactamente la vista previa editada", copied.last == flow.prompt && (try? SessionCapsuleStore.latest().capsule.preparedPrompt) == flow.prompt)
        flow.back()
        flow.source = .codex
        flow.useLatest()
        check("reabrir el último relevo conserva carpeta al cambiar origen", flow.workspace == root && flow.source == .claude && flow.prompt == "contexto revisado por el usuario")
        var failedLaunch = interaction
        failedLaunch.launch = { _ in throw LocalAgentSessionError.unreadable }
        let failedFlow = SessionRelayModel(relay: SessionRelayController(interaction: failedLaunch))
        failedFlow.useLatest()
        await failedFlow.complete(open: true)
        check("un fallo al abrir mantiene el archivo y comunica el error", failedFlow.savedURL != nil && failedFlow.status != nil && failedFlow.error != nil)
        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
