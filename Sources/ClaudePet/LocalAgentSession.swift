import Foundation

struct LocalAgentSession: Identifiable, Equatable {
    let url: URL
    let agent: Agent
    let workspace: String
    let title: String
    let modifiedAt: Date
    var id: String { url.path }
    var project: String { URL(fileURLWithPath: workspace).lastPathComponent }
}

enum LocalAgentSessionError: LocalizedError {
    case unreadable, noMessages, compressedUnavailable
    var errorDescription: String? {
        switch self {
        case .unreadable: "no se pudo leer ese chat local; actualiza la lista o elige otro"
        case .noMessages: "ese chat no contiene mensajes visibles para continuar"
        case .compressedUnavailable: "este chat está comprimido y falta zstd para leerlo"
        }
    }
}

struct SessionExcerpt {
    let text: String
    let included: Int
    let total: Int
    let clipped: Bool
    let skipped: Int
    var description: String {
        "\(included) de \(total) mensajes" + (clipped ? " · extracto limitado por tamaño" : "")
            + (skipped > 0 ? " · \(skipped) registros grandes omitidos" : "")
    }
}

enum LocalAgentSessionReader {
    static var codexRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex").appendingPathComponent("sessions")
    static var claudeRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude").appendingPathComponent("projects")

    static func recent(for agent: Agent, limit: Int = 100) -> [LocalAgentSession] {
        let root = agent == .codex ? codexRoot : claudeRoot
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".jsonl") || url.lastPathComponent.hasSuffix(".jsonl.zst") {
            if Task.isCancelled { return [] }
            guard !url.path.contains("/tool-results/"), !url.path.contains("/vercel-plugin/"), !url.path.contains("/subagents/"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        var names: [String: String] = [:]
        if agent == .codex {
            let index = root.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
            _ = try? SessionJSONLines.read(index) { row in
                if let id = row["id"] as? String, let name = row["thread_name"] as? String { names[id] = name }
            }
        }
        var result: [LocalAgentSession] = []
        for (url, date) in files.sorted(by: { $0.1 > $1.1 }) {
            if Task.isCancelled { break }
            if let session = metadata(url: url, agent: agent, date: date, names: names) { result.append(session) }
            if result.count >= limit { break }
        }
        return result
    }

    static func transcript(_ session: LocalAgentSession) throws -> String { try excerpt(session).text }

    /// Diagnóstico local sin imprimir mensajes ni copiar datos al portapapeles.
    static func diagnose() -> Bool {
        var failures = 0
        for agent in Agent.allCases {
            let started = Date()
            let sessions = recent(for: agent)
            print("\(agent.rawValue): \(sessions.count) chats detectados en \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            let samples = Array(sessions.prefix(5)) + Array(sessions.filter { $0.url.pathExtension == "zst" }.prefix(1))
            for session in samples {
                do {
                    let excerpt = try excerpt(session)
                    print("PASS \(agent.rawValue) \(session.url.lastPathComponent): \(excerpt.description)")
                } catch LocalAgentSessionError.noMessages {
                    print("INFO sesión sin diálogo visible")
                } catch { failures += 1; print("FAIL \(error.localizedDescription)") }
            }
        }
        return failures == 0
    }

    static func excerpt(_ session: LocalAgentSession) throws -> SessionExcerpt {
        var firstUser: String?
        var recent: [(String, String)] = []
        var total = 0
        var previousID: String?
        let report = try SessionJSONLines.read(session.url) { row in
            guard let message = visibleMessage(row, agent: session.agent) else { return }
            let id = row["uuid"] as? String
            if let id, id == previousID { return }
            previousID = id
            if recent.last?.0 == message.0 && recent.last?.1 == message.1 { return }
            total += 1
            if message.0 == "usuario" && firstUser == nil { firstUser = message.1 }
            recent.append(message)
            if recent.count > 60 { recent.removeFirst() }
        }
        guard !recent.isEmpty else { throw LocalAgentSessionError.noMessages }
        var blocks: [String] = []
        var count = 0
        var clipped = total > recent.count
        var budget = 48_000
        for (role, text) in recent.reversed() {
            let maximum = min(8000, budget - role.count - 40)
            guard maximum > 200 else { clipped = true; break }
            let cut = text.count > maximum
            let block = "\(role):\n" + String(text.prefix(maximum)) + (cut ? "\n[mensaje recortado]" : "")
            blocks.insert(block, at: 0)
            budget -= block.count + 2
            clipped = clipped || cut
            count += 1
        }
        var header = "extracto del chat local de \(session.agent.rawValue)\n\(count) de \(total) mensajes visibles. herramientas e imágenes no incluidas."
        if let firstUser, count < total { header += "\n\nsolicitud inicial:\n" + String(firstUser.prefix(3000)) }
        return SessionExcerpt(text: header + "\n\n" + blocks.joined(separator: "\n\n"), included: count, total: total, clipped: clipped, skipped: report.skipped)
    }

    private static func metadata(url: URL, agent: Agent, date: Date, names: [String: String]) -> LocalAgentSession? {
        var workspace: String?
        var title: String?
        var sessionID: String?
        do {
            try SessionJSONLines.read(url, byteLimit: 1_048_576) { row in
                if agent == .codex, row["type"] as? String == "session_meta", let payload = row["payload"] as? [String: Any] {
                    workspace = payload["cwd"] as? String
                    sessionID = payload["id"] as? String ?? payload["session_id"] as? String
                }
                if agent == .claude, workspace == nil { workspace = row["cwd"] as? String }
                if title == nil, let message = visibleMessage(row, agent: agent), message.0 == "usuario" {
                    title = message.1.split(separator: "\n").first.map(String.init)
                }
            }
        } catch { return nil }
        if agent == .claude, let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let end = try? handle.seekToEnd() {
                try? handle.seek(toOffset: end > 131_072 ? end - 131_072 : 0)
                if let data = try? handle.readToEnd() {
                    for line in data.split(separator: 10) {
                        guard let row = SessionJSONLines.object(Data(line)) else { continue }
                        if row["type"] as? String == "custom-title", let name = row["customTitle"] as? String { title = name }
                        if workspace == nil { workspace = row["cwd"] as? String }
                    }
                }
            }
        }
        guard let workspace, workspace.hasPrefix("/") else { return nil }
        let indexedName = sessionID.flatMap { names[$0] }.flatMap { usableTitle($0) }
        guard let name = indexedName ?? title.flatMap(usableTitle) else { return nil }
        return LocalAgentSession(url: url, agent: agent, workspace: workspace, title: String(name.prefix(160)), modifiedAt: date)
    }

    private static func visibleMessage(_ row: [String: Any], agent: Agent) -> (String, String)? {
        let payload: [String: Any]
        if agent == .codex {
            guard row["type"] as? String == "response_item", let item = row["payload"] as? [String: Any], item["type"] as? String == "message" else { return nil }
            payload = item
        } else {
            guard let type = row["type"] as? String, ["user", "assistant"].contains(type), row["isMeta"] as? Bool != true,
                  let item = row["message"] as? [String: Any] else { return nil }
            payload = item
        }
        guard let role = payload["role"] as? String, role == "user" || role == "assistant" else { return nil }
        let text: String
        if let string = payload["content"] as? String { text = string }
        else if let blocks = payload["content"] as? [[String: Any]] {
            text = blocks.compactMap { block in
                guard ["text", "input_text", "output_text"].contains(block["type"] as? String ?? "") else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        } else { return nil }
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if role == "user" {
            if let range = clean.range(of: "## My request:\n") { clean = String(clean[range.upperBound...]) }
            if ["# AGENTS.md instructions", "# Files mentioned by the user:", "<environment_context>", "<permissions instructions>", "<local-command-", "<command-name>", "<external_", "<codex_apps_", "<app-context>"].contains(where: { clean.hasPrefix($0) }) { return nil }
        }
        guard !clean.isEmpty else { return nil }
        return (role == "user" ? "usuario" : "asistente", clean)
    }

    private static func usableTitle(_ value: String) -> String? {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !["<external_", "<codex_apps_", "<environment_context>", "<permissions instructions>"].contains(where: { title.hasPrefix($0) }) else { return nil }
        return title
    }
}
