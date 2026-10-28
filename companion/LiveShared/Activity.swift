import ActivityKit
import AppIntents
import Foundation

/// Lo que muestra la Isla Dinámica y la pantalla bloqueada: el agente que más trabaja y, si hay, el permiso que espera.
struct VistoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var agent: String
        var state: String
        var project: String
        var since: Date
        var pending: Int
        var askID: String?
        var askTool: String?
        var canAllow: Bool
        var context: Int?
    }
    var host: String
}

/// Botones de la Isla Dinámica. Se ejecutan en la app, que responde a claude pet.
struct LiveDecisionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Responder permiso"
    static var openAppWhenRun = false

    @Parameter(title: "Permiso") var askID: String
    @Parameter(title: "Permitir") var allow: Bool

    init() {}
    init(askID: String, allow: Bool) { self.askID = askID; self.allow = allow }

    func perform() async throws -> some IntentResult {
        await LiveBridge.decide?(askID, allow)
        return .result()
    }
}

/// La app engancha aquí su manera de responder; la extensión solo declara el intent.
enum LiveBridge {
    nonisolated(unsafe) static var decide: (@Sendable (String, Bool) async -> Void)?
}
