import Foundation

struct CodexVisualSnapshot: Equatable {
    let session: String
    let workspace: String
    let task: String
    let context: ContextReading?
    let modifiedAt: Date
}

/// Lee la sesión local más reciente de Codex sin depender del pet bus. Solo conserva carpeta,
/// último mensaje visible del usuario y contadores; nunca razonamiento ni salidas de herramientas.
actor CodexVisualScanner {
    private var cachedURL: URL?
    private var cachedWorkspace = ""

    func read(now: Date = Date()) -> CodexVisualSnapshot? {
        let url = Self.latestSessionURL(now: now) ?? cachedURL
        guard let url,
              let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil,
              now.timeIntervalSince(modified) < 30 * 60 else { return nil }
        if url != cachedURL {
            cachedURL = url
            cachedWorkspace = Self.workspace(url)
        }
        guard !cachedWorkspace.isEmpty else { return nil }
        return CodexVisualSnapshot(session: url.path, workspace: cachedWorkspace,
                                   task: Self.lastUserTask(url), context: ContextMeter.readCodex(url: url),
                                   modifiedAt: modified)
    }

    /// Las sesiones activas viven en carpetas YYYY/MM/DD. Revisar hoy y los días vecinos evita
    /// recorrer todo el historial cada ocho segundos; una sesión ya detectada queda en caché.
    static func latestSessionURL(root: URL = LocalAgentSessionReader.codexRoot, now: Date) -> URL? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy/MM/dd"
        var candidates: [(URL, Date)] = []
        for offset in -1...1 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let folder = root.appendingPathComponent(formatter.string(from: date), isDirectory: true)
            guard let urls = try? FileManager.default.contentsOfDirectory(at: folder,
                                                                          includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for url in urls where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                candidates.append((url, values.contentModificationDate ?? .distantPast))
            }
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    static func workspace(_ url: URL) -> String {
        var result = ""
        _ = try? SessionJSONLines.read(url, byteLimit: 1_048_576) { row in
            guard result.isEmpty, row["type"] as? String == "session_meta",
                  let payload = row["payload"] as? [String: Any], let cwd = payload["cwd"] as? String,
                  cwd.hasPrefix("/") else { return }
            result = cwd
        }
        return result
    }

    static func lastUserTask(_ url: URL, byteLimit: UInt64 = 2 * 1024 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return "" }
        let start = end > byteLimit ? end - byteLimit : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return "" }
        if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(data.startIndex...newline) }
        var task = ""
        for line in data.split(separator: 10) {
            guard let row = SessionJSONLines.object(Data(line)), row["type"] as? String == "response_item",
                  let payload = row["payload"] as? [String: Any], payload["type"] as? String == "message",
                  payload["role"] as? String == "user" else { continue }
            let text: String
            if let value = payload["content"] as? String { text = value }
            else if let blocks = payload["content"] as? [[String: Any]] {
                text = blocks.compactMap { block in
                    guard ["text", "input_text"].contains(block["type"] as? String ?? "") else { return nil }
                    return block["text"] as? String
                }.joined(separator: "\n")
            } else { continue }
            var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = clean.range(of: "## My request:\n") { clean = String(clean[range.upperBound...]) }
            guard !clean.isEmpty,
                  !["# AGENTS.md instructions", "# Files mentioned by the user:", "<environment_context>",
                    "<permissions instructions>", "<local-command-", "<command-name>", "<external_",
                    "<codex_apps_", "<app-context>"].contains(where: { clean.hasPrefix($0) }) else { continue }
            task = String(clean.split(separator: "\n").first?.prefix(140) ?? "")
        }
        return task
    }
}
