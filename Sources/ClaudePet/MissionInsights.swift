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
