import Foundation

struct MissionEvent: Identifiable, Equatable {
    let id = UUID()
    let at: Date
    let agent: String
    let state: PetState
    let project: String
}

struct GitHealth: Equatable {
    var changed = 0
    var staged = 0
    var untracked = 0
    var conflicts = 0
    var affected = 0
    var branch = ""
    var available = false
    var limited = false

    var label: String {
        guard available else { return "sin repositorio git" }
        if conflicts > 0 { return "\(conflicts) conflictos" }
        if affected == 0 { return "árbol limpio" }
        let noun = affected == 1 ? "cambio" : "cambios"
        return "\(affected) \(noun) · \(staged) staged" + (limited ? " · sin untracked" : "")
    }
}

struct RecoveryCapsule: Equatable {
    let createdAt: Date
    let project: String
    let workspace: String
    let health: GitHealth
    let session: String
}

extension PetState {
    var isActive: Bool { self == .starting || self == .thinking || self == .tool || self == .waiting }
    var isCollisionWork: Bool { self == .thinking || self == .tool }
}
