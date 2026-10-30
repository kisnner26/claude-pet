import Foundation

/// Registro local, compacto y privado de hitos de la mascota.
/// Nunca conserva prompts, comandos, rutas ni contenido de archivos.
struct PetMemoryEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case session, tool, permission, error

        var label: String {
            switch self {
            case .session: return "sesión completada"
            case .tool: return "herramienta usada"
            case .permission: return "permiso respondido"
            case .error: return "incidencia registrada"
            }
        }
    }

    let id: UUID
    let at: Date
    let kind: Kind
    let agent: String
    let project: String
}

/// Memoria persistente separada de los contadores diarios: sirve a la visualización sin convertir actividad sensible en telemetría.
final class PetMemoryStore {
    static let shared = PetMemoryStore()
    static let keepEvents = 400
    private(set) var events: [PetMemoryEvent] = []
    private let lock = NSLock()

    static var path: String {
        (ProcessInfo.processInfo.environment["CLAUDE_PET_MEMORY"] ?? (NSHomeDirectory() + "/.claude-pet/memory")) + "/events.json"
    }

    func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)), data.count < 512 * 1024,
              let decoded = try? JSONDecoder().decode([PetMemoryEvent].self, from: data) else { return }
        lock.lock(); events = decoded.sorted { $0.at > $1.at }; lock.unlock()
    }

    func record(_ kind: PetMemoryEvent.Kind, agent: String = "", project: String = "", at: Date = Date()) {
        let safeAgent = String(agent.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(20))
        let safeProject = String(project.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }.prefix(40))
        lock.lock()
        events.insert(PetMemoryEvent(id: UUID(), at: at, kind: kind, agent: safeAgent, project: safeProject), at: 0)
        if events.count > Self.keepEvents { events.removeLast(events.count - Self.keepEvents) }
        lock.unlock()
        save()
    }

    func snapshot() -> [PetMemoryEvent] { lock.lock(); defer { lock.unlock() }; return events }

    func save() {
        lock.lock(); let snapshot = events; lock.unlock()
        let url = URL(fileURLWithPath: Self.path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            chmod(Self.path, 0o600)
        } catch { }
    }
}
