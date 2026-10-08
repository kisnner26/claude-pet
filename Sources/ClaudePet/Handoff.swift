import Foundation

/// Traspaso entre Claude y Codex: revision cruzada en solo lectura y salidas a una colision.
/// Nada corre solo: el diff solo se envia al otro agente cuando el usuario lo pide desde el menu.
enum Agent: String, CaseIterable {
    case claude, codex
    var displayName: String { self == .claude ? "Claude" : "Codex" }
    var provider: String { self == .claude ? "Anthropic" : "OpenAI" }
    var other: Agent { self == .claude ? .codex : .claude }
}

enum AgentLocator {
    /// Una app de barra de menu no hereda el PATH de la shell: se buscan tambien las rutas habituales.
    static func find(_ name: String, home: String = NSHomeDirectory(),
                     path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> String? {
        var folders = path.split(separator: ":").map(String.init)
        folders += ["/opt/homebrew/bin", "/usr/local/bin"]
        folders += [".local/bin", ".npm-global/bin", ".bun/bin", ".volta/bin", ".claude/local", ".codex/bin"].map { home + "/" + $0 }
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            folders += versions.sorted().reversed().map { nvm + "/" + $0 + "/bin" }
        }
        for folder in folders {
            let candidate = folder + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

enum HandoffCommand {
    /// Invocacion de solo lectura del agente revisor. El prompt siempre viaja por stdin: nunca en argv.
    static func arguments(reviewer: Agent, workspace: String, output: String) -> [String] {
        switch reviewer {
        case .codex:
            return ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral",
                    "-C", workspace, "-o", output, "-"]
        case .claude:
            return ["-p", "--permission-mode", "plan", "--tools", "Read,Grep,Glob", "--no-session-persistence"]
        }
    }
}

enum HandoffPrompt {
    static func build(author: Agent, project: String, task: String, diff: Data, truncated: Bool, untracked: [String]) -> String {
        var parts = [
            "Eres el segundo par de ojos de un cambio hecho por \(author.displayName)" + (project.isEmpty ? "." : " en el proyecto «\(project)»."),
            "Revisa el diff de abajo. Solo lectura: no modifiques archivos ni ejecutes nada que escriba.",
            "Busca, por orden de importancia: errores de lógica, problemas de seguridad, casos límite sin cubrir, pruebas que faltan y regresiones. Puedes leer los archivos del proyecto para entender el contexto. Ignora el estilo salvo que cause errores.",
            "Responde en español, breve. Por cada hallazgo: severidad (alta/media/baja), archivo:línea, el problema y un arreglo concreto. Si no encuentras nada serio, dilo claramente.",
        ]
        if !task.isEmpty { parts.append("Tarea que se le pidió al otro agente: \(task)") }
        if !untracked.isEmpty {
            parts.append("Archivos nuevos sin seguimiento (no están en el diff, léelos): " + untracked.joined(separator: ", "))
        }
        parts.append("--- diff ---\n" + String(decoding: diff, as: UTF8.self)
                     + (truncated ? "\n[diff recortado por tamaño; lee el resto con git diff]" : ""))
        return parts.joined(separator: "\n\n")
    }
}

struct HandoffError: Error { let message: String }

enum Handoff {
    static let promptDiffLimit = 120 * 1024
    static let outputLimit = 1024 * 1024
    static let defaultTimeout: TimeInterval = 600

    /// Las pruebas lo redirigen a una carpeta temporal para no tocar la del usuario.
    nonisolated(unsafe) static var reviewDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude-pet/review")

    static func untrackedNames(_ workspace: String, limit: Int = 50) -> [String] {
        let args = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", workspace,
                    "ls-files", "--others", "--exclude-standard", "-z"]
        guard let result = GitPulse.run(arguments: args, timeout: 10, limit: 256 * 1024), result.status == 0 else { return [] }
        let names = result.data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return Array(names.prefix(limit))
    }

    /// Reune lo que se enviaria. Devuelve el prompt y su tamano, o por que no se puede revisar.
    static func prepare(workspace: String, author: Agent, project: String, task: String) -> Result<(prompt: String, bytes: Int), HandoffError> {
        var isDirectory: ObjCBool = false
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(HandoffError(message: "no hay una carpeta de proyecto conocida"))
        }
        guard let diff = DiffOpener.capture(workspace: workspace, maxBytes: promptDiffLimit) else {
            return .failure(HandoffError(message: "el proyecto no es un repositorio git"))
        }
        let untracked = untrackedNames(workspace)
        if diff.data.isEmpty && untracked.isEmpty {
            return .failure(HandoffError(message: "no hay cambios sin commitear para revisar"))
        }
        let prompt = HandoffPrompt.build(author: author, project: project, task: task, diff: diff.data,
                                         truncated: diff.truncated, untracked: untracked)
        return .success((prompt, prompt.utf8.count))
    }

    /// Un checkout propio para el segundo agente, en una rama nueva. No borra ni mueve nada.
    static func createWorktree(workspace: String, agent: Agent) throws -> (path: String, branch: String) {
        var isDirectory: ObjCBool = false
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HandoffError(message: "no hay una carpeta de proyecto conocida")
        }
        let base = URL(fileURLWithPath: workspace)
        let destination = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-pet-\(agent.rawValue)").path
        if FileManager.default.fileExists(atPath: destination) { throw HandoffError(message: "ya existe \(destination)") }
        let format = DateFormatter()
        format.dateFormat = "yyyyMMdd-HHmmss"
        let branch = "pet/\(agent.rawValue)-\(format.string(from: Date()))"
        guard let result = GitPulse.run(arguments: ["-C", workspace, "worktree", "add", "-b", branch, destination], timeout: 60),
              result.status == 0 else {
            throw HandoffError(message: "git no pudo crear el worktree (¿repositorio sin commits?)")
        }
        return (destination, branch)
    }
}

/// Una revision en segundo plano. Cada instancia corre una sola vez.
final class ReviewJob: @unchecked Sendable {
    enum State: Equatable { case idle, running, done, failed(String), cancelled }

    let reviewer: Agent
    let workspace: String
    let project: String
    private let prompt: String
    private let executable: String?
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var process: Process?
    private var wasCancelled = false
    private var current: State = .idle
    private(set) var result: URL?
    let finished = DispatchSemaphore(value: 0)
    var onChange: (@Sendable (State) -> Void)?

    init(reviewer: Agent, workspace: String, project: String, prompt: String,
         executable: String? = nil, timeout: TimeInterval = Handoff.defaultTimeout) {
        self.reviewer = reviewer; self.workspace = workspace; self.project = project
        self.prompt = prompt; self.timeout = timeout
        self.executable = executable ?? AgentLocator.find(reviewer.rawValue)
    }

    var state: State { lock.lock(); defer { lock.unlock() }; return current }
    var author: Agent { reviewer.other }

    private func set(_ new: State) {
        lock.lock(); current = new; lock.unlock()
        onChange?(new)
    }

    func start() {
        guard executable != nil else {
            set(.failed("no se encontró \(reviewer.rawValue) en este equipo"))
            finished.signal()
            return
        }
        set(.running)
        DispatchQueue.global(qos: .utility).async { [self] in
            work()
            finished.signal()
        }
    }

    func cancel() {
        lock.lock(); wasCancelled = true; let running = process; lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }

    private func work() {
        guard let executable else { return }
        let directory = Handoff.reviewDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp: String = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
        let scratch = directory.appendingPathComponent(".\(reviewer.rawValue)-\(stamp).out")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = HandoffCommand.arguments(reviewer: reviewer, workspace: workspace, output: scratch.path)
        task.currentDirectoryURL = URL(fileURLWithPath: workspace)
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_PET_REVIEW"] = "1"          // el hook no reporta esta sesion como del usuario
        environment["GIT_TERMINAL_PROMPT"] = "0"
        task.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        task.standardInput = input; task.standardOutput = output; task.standardError = errors

        let out = CappedOutput(limit: Handoff.outputLimit), err = CappedOutput(limit: 64 * 1024)
        let readers = DispatchGroup()
        for (pipe, sink) in [(output, out), (errors, err)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty { sink.append(chunk) }
            }
        }
        lock.lock(); process = task; lock.unlock()
        do { try task.run() } catch {
            try? input.fileHandleForWriting.close(); try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
            _ = readers.wait(timeout: .now() + 1)
            return set(.failed("no se pudo lanzar \(reviewer.rawValue): \(error.localizedDescription)"))
        }
        DispatchQueue.global(qos: .utility).async { [prompt] in
            try? input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
            try? input.fileHandleForWriting.close()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(50_000) }
        var timedOut = false
        if task.isRunning {
            timedOut = true
            task.terminate()
            let grace = Date().addingTimeInterval(0.5)
            while task.isRunning && Date() < grace { usleep(20_000) }
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        }
        task.waitUntilExit()
        _ = readers.wait(timeout: .now() + 2)

        lock.lock(); let cancelled = wasCancelled; lock.unlock()
        if cancelled { return set(.cancelled) }
        if timedOut { return set(.failed("la revisión superó el tiempo máximo")) }

        var text = ""
        if reviewer == .codex, let written = try? String(contentsOf: scratch, encoding: .utf8) { text = written }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = String(decoding: out.result.data, as: UTF8.self) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task.terminationStatus == 0, !text.isEmpty else {
            let last = String(decoding: err.result.data, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? "sin respuesta"
            return set(.failed("\(reviewer.rawValue) terminó con error (\(task.terminationStatus)): \(last.prefix(160))"))
        }
        let when: String = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: Date()) }()
        let header = "# revisión de \(reviewer.displayName) sobre cambios de \(author.displayName)\nproyecto: \(project.isEmpty ? "-" : project) · \(when)\n\n"
        let url = directory.appendingPathComponent("review-\(reviewer.rawValue)-\(stamp).md")
        guard (try? Data((header + String(text.prefix(Handoff.outputLimit)) + "\n").utf8).write(to: url, options: .atomic)) != nil else {
            return set(.failed("no se pudo guardar la revisión"))
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)   // puede citar codigo sensible
        result = url
        set(.done)
    }
}
