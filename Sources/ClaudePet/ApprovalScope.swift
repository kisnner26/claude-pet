import Foundation

enum ApprovalScope: String, CaseIterable, Codable {
    case once = "una vez"
    case session = "esta sesión"
    case project = "este proyecto"
    case always = "siempre"
    var duration: TimeInterval? {
        switch self { case .once: return nil; case .session: return 8 * 3600; case .project: return 30 * 60; case .always: return nil }
    }
    func isAllowed(for risk: PermissionRisk) -> Bool { self != .always || risk != .high }
}
