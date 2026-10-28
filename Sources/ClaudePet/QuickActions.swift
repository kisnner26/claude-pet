import Foundation

/// Acciones del dock de la isla. Cada una solo aparece cuando tiene sentido: sin cambios no hay "commitear".
enum QuickAction: String, CaseIterable, Identifiable {
    case commit, terminal, changes, music, mission, summary, folder, restorePoint, pomodoro, snooze, relay, perimeter, settings
    var id: String { rawValue }
}

/// Lo que el dock necesita saber del momento para decidir que ensenar.
struct QuickContext: Equatable {
    var hasWorkspace = false
    var isRepo = false
    /// Archivos con cambios segun git (para commitear).
    var changeCount = 0
    /// Archivos que ha editado el agente (para ver el diff).
    var agentChanges = 0
    var commiteroAvailable = false
    var terminalAvailable = false
    var musicAvailable = false
    var musicPlaying = false
    var pomodoroRunning = false
    var alertsSnoozed = false
    var hasPerimeter = false
}

struct QuickDescriptor: Equatable {
    let title: String
    let symbol: String
    var prominent = false
    var badge: Int?
    /// Cuando aparece (se ensena en ajustes).
    let when: String
}

enum QuickActions {
    static let maxVisible = 5
    /// Orden de fabrica: lo mas usado primero. Estas cinco vienen activadas.
    static let defaultEnabled: [QuickAction] = [.commit, .terminal, .changes, .music, .mission]
    static var allOrdered: [QuickAction] { defaultEnabled + QuickAction.allCases.filter { !defaultEnabled.contains($0) } }

    static func available(_ a: QuickAction, _ c: QuickContext) -> Bool {
        switch a {
        case .commit: return c.commiteroAvailable && c.hasWorkspace && c.isRepo && c.changeCount > 0
        case .terminal: return c.terminalAvailable
        case .changes: return c.agentChanges > 0
        case .music: return c.musicAvailable
        case .folder, .perimeter: return c.hasWorkspace
        case .restorePoint: return c.hasWorkspace && c.isRepo
        case .mission, .summary, .pomodoro, .snooze, .relay, .settings: return true
        }
    }

    static func descriptor(_ a: QuickAction, _ c: QuickContext) -> QuickDescriptor {
        switch a {
        case .commit: return QuickDescriptor(title: "commitear", symbol: "arrow.triangle.branch", prominent: true, badge: c.changeCount, when: "hay cambios en un repositorio y commitero está instalado")
        case .terminal: return QuickDescriptor(title: "terminal", symbol: "terminal", when: "hay una terminal de la sesión")
        case .changes: return QuickDescriptor(title: "cambios", symbol: "plus.forwardslash.minus", badge: c.agentChanges, when: "el agente ha editado archivos")
        case .music: return QuickDescriptor(title: c.musicPlaying ? "pausar" : "reproducir", symbol: c.musicPlaying ? "pause.fill" : "play.fill", when: "suena algo en Spotify o Apple Music")
        case .mission: return QuickDescriptor(title: "mission control", symbol: "square.grid.2x2", when: "siempre")
        case .summary: return QuickDescriptor(title: "copiar resumen", symbol: "doc.on.clipboard", when: "siempre")
        case .folder: return QuickDescriptor(title: "carpeta del proyecto", symbol: "folder", when: "hay un proyecto activo")
        case .restorePoint: return QuickDescriptor(title: "punto de restauración", symbol: "clock.arrow.circlepath", when: "el proyecto es un repositorio")
        case .pomodoro: return QuickDescriptor(title: c.pomodoroRunning ? "parar pomodoro" : "pomodoro", symbol: c.pomodoroRunning ? "stop.fill" : "timer", when: "siempre")
        case .snooze: return QuickDescriptor(title: c.alertsSnoozed ? "reactivar avisos" : "silenciar avisos", symbol: c.alertsSnoozed ? "bell" : "bell.slash", when: "siempre")
        case .relay: return QuickDescriptor(title: "relevo de sesión", symbol: "arrow.left.arrow.right", when: "siempre")
        case .perimeter: return QuickDescriptor(title: c.hasPerimeter ? "perímetro" : "fijar perímetro", symbol: "scope", when: "hay un proyecto activo")
        case .settings: return QuickDescriptor(title: "ajustes", symbol: "gearshape", when: "siempre")
        }
    }

    /// Lo que se ve y lo que va al menu "+": respeta el orden del usuario, solo lo activado y disponible, con tope de cinco.
    static func layout(order: [QuickAction], context c: QuickContext) -> (visible: [QuickAction], overflow: [QuickAction]) {
        let usable = order.filter { available($0, c) }
        return (Array(usable.prefix(maxVisible)), Array(usable.dropFirst(maxVisible)))
    }

    /// "commit,terminal,...": lo desconocido y lo repetido se descarta; sin nada valido vuelve a los de fabrica.
    static func decode(_ raw: String?) -> [QuickAction] {
        guard let raw else { return defaultEnabled }
        var seen = Set<QuickAction>(), out: [QuickAction] = []
        for part in raw.split(separator: ",") { if let a = QuickAction(rawValue: String(part)), seen.insert(a).inserted { out.append(a) } }
        return out.isEmpty && !raw.isEmpty ? defaultEnabled : out
    }
    static func encode(_ order: [QuickAction]) -> String { order.map(\.rawValue).joined(separator: ",") }
}
