import Foundation

enum MissionInsightTone: String, Equatable {
    case calm, active, caution, danger
}

struct MissionInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let tone: MissionInsightTone
}

enum MissionAction: String, CaseIterable, Identifiable {
    case refreshGit, openDiff, clearRecovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refreshGit: return "actualizar git"
        case .openDiff: return "abrir diff"
        case .clearRecovery: return "descartar recuperación"
        }
    }
}

/// Lo único que el tablero pide atender ahora: una lectura y, si de verdad hay algo que hacer, una acción.
struct MissionBrief: Equatable {
    let title: String
    let detail: String
    let tone: MissionInsightTone
    let action: MissionAction?
    let actionTitle: String?
}

extension MissionControl {
    var brief: MissionBrief {
        let byID = Dictionary(uniqueKeysWithValues: insights.map { ($0.id, $0) })
        if recovery != nil {
            return .init(title: "claude falló", detail: "hay un punto seguro para revisar", tone: .danger, action: .openDiff, actionTitle: "abrir recuperación")
        }
        if git.conflicts > 0 {
            let noun = git.conflicts == 1 ? "conflicto" : "conflictos"
            return .init(title: "\(git.conflicts) \(noun) de merge", detail: "resuélvelos antes de seguir", tone: .danger, action: .openDiff, actionTitle: "abrir diff")
        }
        if byID["approval"]?.tone == .caution {
            return .init(title: "claude espera tu aprobación", detail: "el flujo está detenido hasta que respondas", tone: .caution, action: nil, actionTitle: nil)
        }
        if collision {
            return .init(title: "mismo proyecto", detail: "claude y codex trabajan a la vez: revisa que no se pisen", tone: .caution, action: nil, actionTitle: nil)
        }
        if byID["handoff"]?.tone == .active {
            return .init(title: "codex terminó", detail: "revisa su resultado antes de continuar", tone: .active, action: git.affected > 0 ? .openDiff : nil, actionTitle: git.affected > 0 ? "abrir diff" : nil)
        }
        guard git.available else {
            return .init(title: "sin proyecto git", detail: "empieza una sesión dentro de un repositorio", tone: .calm, action: nil, actionTitle: nil)
        }
        if git.affected == 0 {
            return .init(title: "todo en orden", detail: "árbol limpio, sin nada pendiente", tone: .calm, action: nil, actionTitle: nil)
        }
        let noun = git.affected == 1 ? "cambio" : "cambios"
        return .init(title: "\(git.affected) \(noun) sin commit", detail: git.staged > 0 ? "\(git.staged) ya preparados" : "ninguno preparado todavía", tone: .active, action: .openDiff, actionTitle: "abrir diff")
    }
}
