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
    var pressure: ContextPressure {
        if remainingFraction <= 0.15 { return .critical }
        if remainingFraction <= 0.35 { return .caution }
        return .normal
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
        do {
            try SessionJSONLines.read(url) { row in
                guard let message = row["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { return }
                let input = integer(usage["input_tokens"])
                let created = integer(usage["cache_creation_input_tokens"])
                let cached = integer(usage["cache_read_input_tokens"])
                let output = integer(usage["output_tokens"])
                let used = input + created + cached + output
                guard used > 0 else { return }
                reading = ContextReading(usedTokens: used, compactAtTokens: compactAt,
                                         model: message["model"] as? String ?? "claude")
            }
        } catch { return nil }
        return reading
    }

    private static func transcript(sessionPrefix: String, root: URL) -> URL? {
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
    func read(sessionPrefix: String) -> ContextReading? {
        ContextMeter.read(sessionPrefix: sessionPrefix)
    }
}
