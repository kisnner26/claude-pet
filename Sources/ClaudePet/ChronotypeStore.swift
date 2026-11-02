import Foundation

/// El resumen por hora vive junto a la memoria (`hours.json`, solo el usuario) y se alimenta de cada evento que se registra.
/// La primera vez se siembra con los eventos que ya hubiera.
final class ChronotypeStore: @unchecked Sendable {
    static let shared = ChronotypeStore()
    private let lock = NSLock()
    private var value = Chronotype()

    static var path: String {
        (ProcessInfo.processInfo.environment["CLAUDE_PET_MEMORY"] ?? (NSHomeDirectory() + "/.claude-pet/memory")) + "/hours.json"
    }

    var current: Chronotype { lock.lock(); defer { lock.unlock() }; return value }

    /// Lee el archivo; si no existe, parte de los eventos dados (los mas viejos primero no importa: solo cuentan por hora).
    func load(seed: [PetMemoryEvent] = []) {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)), data.count < 64 * 1024,
           let decoded = try? JSONDecoder().decode(Chronotype.self, from: data), decoded.hours.count == 24 {
            lock.lock(); value = decoded; lock.unlock()
            return
        }
        var fresh = Chronotype()
        for e in seed { fresh.add(e.kind, at: e.at) }
        lock.lock(); value = fresh; lock.unlock()
        if !seed.isEmpty { save() }
    }

    func add(_ kind: PetMemoryEvent.Kind, at date: Date = Date()) {
        lock.lock(); value.add(kind, at: date); lock.unlock()
        save()
    }

    private func save() {
        lock.lock(); let snapshot = value; lock.unlock()
        let url = URL(fileURLWithPath: Self.path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            chmod(Self.path, 0o600)
        } catch { }
    }
}
