import Foundation

/// Cuando suena el cerebro y que se cuenta por la manana. El parte se guarda junto a la memoria (`dream.json`).
@MainActor final class DreamKeeper: ObservableObject {
    static let shared = DreamKeeper()
    nonisolated static let every: TimeInterval = 20 * 3600
    nonisolated static let idleToSleep: TimeInterval = 3600

    @Published private(set) var report: DreamReport?
    private(set) var running = false

    static var path: String {
        (ProcessInfo.processInfo.environment["CLAUDE_PET_MEMORY"] ?? (NSHomeDirectory() + "/.claude-pet/memory")) + "/dream.json"
    }

    /// Toca sonar si pasaron unas 20 horas desde la ultima vez y es de noche (de 0 a 7 h) o llevas una hora sin tocar la Mac.
    /// Nunca mientras un agente trabaja.
    nonisolated static func isDue(last: Date?, now: Date, hour: Int, idle: TimeInterval, busy: Bool) -> Bool {
        guard !busy else { return false }
        if let last, now.timeIntervalSince(last) < every { return false }
        return (0..<7).contains(hour) || idle >= idleToSleep
    }

    func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)), data.count < 32 * 1024 else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        report = try? dec.decode(DreamReport.self, from: data)
    }

    private func save() {
        guard let report else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let url = URL(fileURLWithPath: Self.path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try enc.encode(report).write(to: url, options: .atomic)
            chmod(Self.path, 0o600)
        } catch { }
    }

    func markSeen() {
        guard var r = report, !r.seen else { return }
        r.seen = true; report = r; save()
    }

    /// Repasa todos los proyectos con notas. Es rapido (milisegundos por proyecto, mas el recorrido de archivos), pero va fuera del hilo principal.
    func dream(now: Date = Date(), store: BrainStore = .shared, perimeterRoots: [String]) async -> DreamReport {
        running = true
        defer { running = false }
        let result = await Task.detached(priority: .utility) { () -> DreamReport in
            var r = DreamReport(at: now)
            for project in store.projects() {
                let root = DreamRoots.root(for: project.name, perimeterRoots: perimeterRoots)
                let index = root.map { ProjectFileIndex.build(root: $0) }
                // sin carpeta conocida no se puede juzgar si un archivo existe: se deja como esta
                let outcome = store.dream(project: project.name, now: now, exists: { index?.exists($0) ?? true })
                r.projects += 1; r.merged += outcome.merged; r.stale += outcome.stale.count; r.lingering += outcome.lingering.count
                r.notesAfter += outcome.notes.count
            }
            return r
        }.value
        report = result
        save()
        return result
    }

    /// Lo llama un temporizador: sueña si toca.
    func tick(idle: TimeInterval, busy: Bool, now: Date = Date(), perimeterRoots: [String]) {
        let hour = Calendar.current.component(.hour, from: now)
        guard !running, Self.isDue(last: report?.at, now: now, hour: hour, idle: idle, busy: busy) else { return }
        Task { _ = await dream(now: now, perimeterRoots: perimeterRoots) }
    }
}
