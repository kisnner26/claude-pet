import Foundation

enum ContextPressure: Equatable {
    case normal, caution, critical
}

struct ContextReading: Equatable {
    let usedTokens: Int
    let compactAtTokens: Int
    let model: String

    var remainingTokens: Int { max(0, compactAtTokens - usedTokens) }
    var remainingFraction: Double {
        guard compactAtTokens > 0 else { return 0 }
        return min(1, max(0, Double(remainingTokens) / Double(compactAtTokens)))
    }
    var remainingPercent: Int { Int((remainingFraction * 100).rounded()) }
    var summary: String { "\(model) · \(remainingPercent)% restante · \(usedTokens) usados · \(remainingTokens) disponibles" }
    var pressure: ContextPressure {
        if remainingFraction <= 0.15 { return .critical }
        if remainingFraction <= 0.35 { return .caution }
        return .normal
    }
    var pressureLabel: String {
        switch pressure {
        case .normal: return "normal"
        case .caution: return "cuidado"
        case .critical: return "crítico"
        }
    }
}

/// Lee solo contadores de uso del transcript local. No conserva mensajes, herramientas ni prompts.
enum ContextMeter {
    /// Claude Code compacta antes del límite total para reservar salida y herramientas. Puede ajustarse
    /// para instalaciones con otra ventana mediante `CLAUDE_PET_COMPACTION_TOKENS`.
    static var compactAtTokens: Int {
        let value = ProcessInfo.processInfo.environment["CLAUDE_PET_COMPACTION_TOKENS"].flatMap(Int.init)
        return max(16_000, value ?? 160_000)
    }

    static func read(sessionPrefix: String, root: URL = LocalAgentSessionReader.claudeRoot) -> ContextReading? {
        guard sessionPrefix.count >= 4,
              sessionPrefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              let url = transcript(sessionPrefix: sessionPrefix, root: root) else { return nil }
        return read(url: url)
    }

    static func read(url: URL, compactAt: Int = compactAtTokens) -> ContextReading? {
        var reading: ContextReading?
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            let start = end > 4 * 1024 * 1024 ? end - 4 * 1024 * 1024 : 0
            try handle.seek(toOffset: start)
            guard var data = try handle.readToEnd(), !data.isEmpty else { return nil }
            if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(data.startIndex...newline) }
            for line in data.split(separator: 10) {
                guard let row = SessionJSONLines.object(Data(line)) else { continue }
                guard let message = row["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                let input = integer(usage["input_tokens"])
                let created = integer(usage["cache_creation_input_tokens"])
                let cached = integer(usage["cache_read_input_tokens"])
                let output = integer(usage["output_tokens"])
                let used = input + created + cached + output
                guard used > 0 else { continue }
                reading = ContextReading(usedTokens: used, compactAtTokens: compactAt,
                                         model: message["model"] as? String ?? "claude")
            }
        } catch { return nil }
        return reading
    }

    /// Codex registra el conteo vigente y la ventana del modelo en eventos `token_count`.
    /// Se lee solo la cola del JSONL, igual que con Claude, y no se conserva contenido.
    static func readCodex(url: URL) -> ContextReading? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            let start = end > 4 * 1024 * 1024 ? end - 4 * 1024 * 1024 : 0
            try handle.seek(toOffset: start)
            guard var data = try handle.readToEnd(), !data.isEmpty else { return nil }
            if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(data.startIndex...newline) }
            var reading: ContextReading?
            for line in data.split(separator: 10) {
                guard let row = SessionJSONLines.object(Data(line)), row["type"] as? String == "event_msg",
                      let payload = row["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any] else { continue }
                let used = integer(usage["total_tokens"])
                let window = integer(info["model_context_window"])
                guard used > 0, window > 0 else { continue }
                reading = ContextReading(usedTokens: used, compactAtTokens: window, model: "codex")
            }
            return reading
        } catch { return nil }
    }

    static func transcript(sessionPrefix: String, root: URL) -> URL? {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in files {
            if Task.isCancelled { return nil }
            guard url.lastPathComponent.hasPrefix(sessionPrefix), url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            return url
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }
}

actor ContextMeterScanner {
    private var locations: [String: URL] = [:]

    func read(sessionPrefix: String) -> ContextReading? {
        if let url = locations[sessionPrefix], FileManager.default.fileExists(atPath: url.path) {
            return ContextMeter.read(url: url)
        }
        guard let url = ContextMeter.transcript(sessionPrefix: sessionPrefix, root: LocalAgentSessionReader.claudeRoot) else { return nil }
        locations[sessionPrefix] = url
        return ContextMeter.read(url: url)
    }
}
