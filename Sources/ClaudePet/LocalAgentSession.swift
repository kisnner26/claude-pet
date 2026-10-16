import Foundation

/// Una conversación local identificada por su carpeta real, no por una carpeta de exportación.
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
    case unreadable
    case noMessages

    var errorDescription: String? {
        switch self {
        case .unreadable: "no se pudo leer ese chat local"
        case .noMessages: "ese chat no contiene mensajes de usuario y asistente para continuar"
        }
    }
}

/// Lee únicamente mensajes visibles del usuario y del asistente. Omite herramientas, razonamiento y datos del sistema.
enum LocalAgentSessionReader {
    static var codexRoot = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/sessions")
    static var claudeRoot = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")

    static func recent(for agent: Agent, limit: Int = 20) -> [LocalAgentSession] {
        let root = agent == .codex ? codexRoot : claudeRoot
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard !url.path.contains("/tool-results/"), !url.path.contains("/vercel-plugin/"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.1 > $1.1 }.prefix(200).compactMap { url, date in
            metadata(url: url, agent: agent, date: date)
        }.prefix(limit).map { $0 }
    }

    static func transcript(_ session: LocalAgentSession) throws -> String {
        var firstUser: String?
        var recent: [(String, String)] = []
        try eachLine(at: session.url) { object in
            guard let message = visibleMessage(object, agent: session.agent) else { return }
            if message.0 == "usuario" && firstUser == nil { firstUser = message.1 }
            recent.append(message)
            if recent.count > 24 { recent.removeFirst() }
        }
        guard !recent.isEmpty else { throw LocalAgentSessionError.noMessages }
        var sections = ["extracto del chat local de \(session.agent.rawValue)"]
        if let firstUser, !recent.contains(where: { $0.0 == "usuario" && $0.1 == firstUser }) {
            sections.append("objetivo inicial del usuario:\n\(String(firstUser.prefix(2500)))")
        }
        sections.append("mensajes recientes (sin llamadas a herramientas):")
        let dialogue = recent.map { role, text in "\(role):\n\(String(text.prefix(3000)))" }.joined(separator: "\n\n")
        return sections.joined(separator: "\n\n") + "\n\n" + String(dialogue.suffix(30_000))
    }

    private static func metadata(url: URL, agent: Agent, date: Date) -> LocalAgentSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 262_144), !data.isEmpty else { return nil }
        var workspace: String?
        var title: String?
        for line in data.split(separator: 10).dropLast() {
            guard let object = dictionary(Data(line)) else { continue }
            if agent == .codex, object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] { workspace = payload["cwd"] as? String }
            if agent == .claude, workspace == nil { workspace = object["cwd"] as? String }
            if title == nil, let message = visibleMessage(object, agent: agent), message.0 == "usuario" {
                title = message.1.split(separator: "\n").first.map(String.init)
            }
            if workspace != nil && title != nil { break }
        }
        guard let workspace, (try? SessionCapsuleFactory.validateWorkspace(workspace)) != nil else { return nil }
        let cleanTitle = (title ?? "chat sin título").trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalAgentSession(url: url, agent: agent, workspace: workspace,
                                 title: String(cleanTitle.prefix(90)), modifiedAt: date)
    }

    private static func eachLine(at url: URL, _ visit: ([String: Any]) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                if let object = dictionary(Data(line)) { visit(object) }
                pending.removeSubrange(...newline)
            }
            if pending.count > 4_000_000 { throw LocalAgentSessionError.unreadable }
        }
        if let object = dictionary(pending) { visit(object) }
    }

    private static func dictionary(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func visibleMessage(_ object: [String: Any], agent: Agent) -> (String, String)? {
        let payload: [String: Any]
        if agent == .codex {
            guard object["type"] as? String == "response_item",
                  let item = object["payload"] as? [String: Any], item["type"] as? String == "message" else { return nil }
            payload = item
        } else {
            guard let type = object["type"] as? String, ["user", "assistant"].contains(type),
                  let item = object["message"] as? [String: Any] else { return nil }
            payload = item
        }
        guard let role = payload["role"] as? String, role == "user" || role == "assistant" else { return nil }
        let raw = payload["content"]
        let text: String
        if let string = raw as? String { text = string }
        else if let blocks = raw as? [[String: Any]] {
            text = blocks.compactMap { block in
                guard ["text", "input_text", "output_text"].contains(block["type"] as? String ?? "") else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        } else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return (role == "user" ? "usuario" : "asistente", clean)
    }
}
