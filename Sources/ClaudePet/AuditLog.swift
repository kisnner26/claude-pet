import Foundation

struct AuditEntry: Codable, Equatable {
    let at: Date
    let tool: String
    let risk: String
    let result: String
    let source: String
}

enum AuditLog {
    static var path: String { (ProcessInfo.processInfo.environment["CLAUDE_PET_AUDIT"] ?? (NSHomeDirectory() + "/.claude-pet/audit")) + "/decisions.jsonl" }

    static func record(ask: PermissionAsk, result: String, source: String = "isla") {
        let entry = AuditEntry(at: Date(), tool: ask.tool, risk: PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk.rawValue, result: result, source: source)
        guard let data = try? JSONEncoder().encode(entry), let line = String(data: data, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: Data((line + "\n").utf8)); try handle.close()
            chmod(path, 0o600)
            prune(url: url)
        } catch { }
    }

    static func ensureFile() -> URL? {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            chmod(url.path, 0o600)
            return url
        } catch { return nil }
    }

    private static func prune(url: URL) {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let kept = text.split(separator: "\n").compactMap { line -> String? in
            guard let d = try? JSONDecoder().decode(AuditEntry.self, from: Data(line.utf8)), d.at >= cutoff else { return nil }; return String(line)
        }
        try? Data((kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")).utf8).write(to: url, options: .atomic)
    }
}
