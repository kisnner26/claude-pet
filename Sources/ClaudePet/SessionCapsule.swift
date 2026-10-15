import Foundation

/// Contexto portable entre agentes. No representa ni modifica una sesión nativa de Claude o Codex.
struct SessionCapsule: Codable, Identifiable, Equatable {
    static let version = 1

    let version: Int
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let source: Agent
    let project: String
    let workspace: String
    let branch: String
    let revision: String
    let gitSummary: String
    let task: String
    let state: String
    let nextStep: String

    var expired: Bool { expiresAt <= Date() }
}

enum SessionCapsuleError: LocalizedError {
    case noWorkspace
    case invalidWorkspace
    case missing
    case invalid

    var errorDescription: String? {
        switch self {
        case .noWorkspace: "todavía no hay un proyecto activo para crear el relevo"
        case .invalidWorkspace: "el proyecto activo ya no es accesible"
        case .missing: "no hay un relevo guardado"
        case .invalid: "el relevo está dañado o usa un formato incompatible"
        }
    }
}

enum SessionCapsuleFactory {
    static func make(source: Agent, workspace: String, project: String, task: String,
                     state: PetState, health: GitHealth, now: Date = Date()) throws -> SessionCapsule {
        guard !workspace.isEmpty else { throw SessionCapsuleError.noWorkspace }
        var isDirectory: ObjCBool = false
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SessionCapsuleError.invalidWorkspace
        }
        let branch = git(workspace, ["branch", "--show-current"])
        let revision = git(workspace, ["rev-parse", "--short", "HEAD"])
        let cleanTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = cleanTask.isEmpty ? "inspecciona el estado actual y define el siguiente paso antes de editar" : cleanTask
        return SessionCapsule(version: SessionCapsule.version, id: UUID(), createdAt: now,
                              expiresAt: now.addingTimeInterval(24 * 60 * 60), source: source,
                              project: project.isEmpty ? URL(fileURLWithPath: workspace).lastPathComponent : project,
                              workspace: workspace, branch: branch, revision: revision,
                              gitSummary: health.label, task: cleanTask, state: state.label,
                              nextStep: next)
    }

    private static func git(_ workspace: String, _ arguments: [String]) -> String {
        guard let result = GitPulse.run(arguments: ["-C", workspace] + arguments, timeout: 5, limit: 512), result.status == 0 else { return "" }
        return String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SessionCapsulePrompt {
    static func build(_ capsule: SessionCapsule, destination: Agent) -> String {
        let task = capsule.task.isEmpty ? "no se capturó una tarea explícita" : capsule.task
        return """
        continúa una tarea que venía de \(capsule.source.displayName). esta es una cápsula de relevo creada por claude pet; no es una sesión nativa importada.

        proyecto: \(capsule.project)
        carpeta: \(capsule.workspace)
        rama: \(capsule.branch.isEmpty ? "desconocida" : capsule.branch)
        revisión: \(capsule.revision.isEmpty ? "sin commit" : capsule.revision)
        git al crearla: \(capsule.gitSummary)
        estado del agente anterior: \(capsule.state)
        tarea: \(task)
        siguiente paso sugerido: \(capsule.nextStep)

        antes de editar, verifica la carpeta, la rama y el estado git actual. no asumas que el diff sigue igual ni repitas trabajo ya terminado. explica brevemente qué encontraste y continúa con la tarea.
        """
    }
}
