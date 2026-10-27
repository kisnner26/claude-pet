import Foundation

/// Una aprobacion recordada: "permitir esta herramienta con este programa o carpeta durante un tiempo".
struct ApprovalRule: Codable, Equatable, Identifiable {
    let id: String
    let scope: ApprovalScope
    let tool: String
    /// Programa (Bash) o carpeta (herramientas de archivos) al que aplica.
    let key: String
    let project: String
    let session: String
    let createdAt: Date
    let expiresAt: Date?

    func isActive(at now: Date) -> Bool { expiresAt.map { now < $0 } ?? true }

    var title: String {
        let target = key.isEmpty ? tool : "\(tool) · \(key)"
        return project.isEmpty ? target : "\(target) · \(project)"
    }
}

/// Reglas de aprobacion con caducidad real y revocables. Nunca cubren riesgo alto ni comandos compuestos.
final class ApprovalRules {
    static let shared = ApprovalRules()
    private(set) var rules: [ApprovalRule] = []
    private let lock = NSLock()
    var onChange: (() -> Void)?

    static var path: String { ProcessInfo.processInfo.environment["CLAUDE_PET_RULES"] ?? (NSHomeDirectory() + "/.claude-pet/rules.json") }
    static let maxRules = 50

    /// Lo que identifica una peticion para las reglas. nil = no se puede reglar (comando compuesto, sin objetivo).
    static func key(tool: String, detail: String) -> String? {
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        // un plan se aprueba cada vez: nunca se recuerda
        guard !d.isEmpty, tool != "ExitPlanMode" else { return nil }
        if tool.lowercased() == "bash" || tool.lowercased().contains("shell") {
            // un comando con operadores, sustitucion o redireccion puede esconder otro: no se regla
            let forbidden = [";", "&", "|", "`", "$(", ">", "<", "\n", "\\"]
            if forbidden.contains(where: { d.contains($0) }) { return nil }
            let first = d.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let program = (first as NSString).lastPathComponent
            return program.isEmpty || program.contains("=") ? nil : program
        }
        if d.hasPrefix("/") || d.hasPrefix("./") || d.contains("/") { return (d as NSString).deletingLastPathComponent }
        return d
    }

    /// Crea una regla si el alcance lo permite. `.once` no se recuerda; `.always` jamas para riesgo alto.
    @discardableResult
    func add(scope: ApprovalScope, ask: PermissionAsk, now: Date = Date()) -> ApprovalRule? {
        guard scope != .once else { return nil }
        let risk = PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk
        guard scope.isAllowed(for: risk), risk != .high, let key = Self.key(tool: ask.tool, detail: ask.detail) else { return nil }
        lock.lock()
        rules.removeAll { !$0.isActive(at: now) }
        if let same = rules.first(where: { $0.tool == ask.tool && $0.key == key && $0.project == ask.project && $0.scope == scope && (scope != .session || $0.session == ask.session) }) { lock.unlock(); return same }
        guard rules.count < Self.maxRules else { lock.unlock(); return nil }
        let rule = ApprovalRule(id: UUID().uuidString, scope: scope, tool: ask.tool, key: key, project: ask.project,
                                session: scope == .session ? ask.session : "", createdAt: now, expiresAt: scope.duration.map { now.addingTimeInterval($0) })
        rules.append(rule)
        lock.unlock()
        save(); onChange?()
        return rule
    }

    /// La regla vigente que cubre esta peticion, si existe. Riesgo alto nunca coincide.
    func match(_ ask: PermissionAsk, now: Date = Date()) -> ApprovalRule? {
        guard PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk != .high,
              let key = Self.key(tool: ask.tool, detail: ask.detail) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return rules.first { $0.isActive(at: now) && $0.tool == ask.tool && $0.key == key && $0.project == ask.project && ($0.scope != .session || $0.session == ask.session) }
    }

    func revoke(id: String) {
        lock.lock(); rules.removeAll { $0.id == id }; lock.unlock()
        save(); onChange?()
    }

    func revokeAll() {
        lock.lock(); rules = []; lock.unlock()
        save(); onChange?()
    }

    func active(now: Date = Date()) -> [ApprovalRule] {
        lock.lock(); defer { lock.unlock() }
        return rules.filter { $0.isActive(at: now) }
    }

    func load(now: Date = Date()) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)), data.count < 512 * 1024,
              let decoded = try? JSONDecoder.iso.decode([ApprovalRule].self, from: data) else { return }
        lock.lock(); rules = decoded.filter { $0.isActive(at: now) && $0.scope != .once && $0.scope.isAllowed(for: .medium) }.prefix(Self.maxRules).map { $0 }; lock.unlock()
    }

    func save() {
        lock.lock(); let snapshot = rules; lock.unlock()
        let url = URL(fileURLWithPath: Self.path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder.iso.encode(snapshot).write(to: url, options: .atomic)
            chmod(Self.path, 0o600)
        } catch { }
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
