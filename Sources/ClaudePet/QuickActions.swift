import Foundation

/// Acciones del dock de la isla. Cada una solo aparece cuando tiene sentido: sin cambios no hay "commitear".
enum QuickAction: String, CaseIterable, Identifiable {
    case commit, terminal, changes, music, mission, summary, folder, restorePoint, pomodoro, snooze, relay, perimeter, settings
    // las que traen los perfiles por app
    case openInEditor, openRepoWeb, copyCd, copyPath, musicPrev, musicNext
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
    /// App en primer plano: decide que herramientas se ensenan primero.
    var profile: AppProfile = .other
    var frontAppName: String?
    var hasRemote = false
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
        case .openInEditor: return c.hasWorkspace && c.profile == .editor && c.frontAppName != nil
        case .openRepoWeb: return c.hasWorkspace && c.hasRemote
        case .copyCd, .copyPath: return c.hasWorkspace
        case .musicPrev, .musicNext: return c.musicAvailable
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
        case .openInEditor: return QuickDescriptor(title: "abrir en \(c.frontAppName ?? "el editor")", symbol: "arrow.up.forward.app", when: "estás en un editor y hay proyecto activo")
        case .openRepoWeb: return QuickDescriptor(title: "abrir el repo en la web", symbol: "safari", when: "el proyecto tiene un remoto en GitHub, GitLab, Bitbucket o Codeberg")
        case .copyCd: return QuickDescriptor(title: "copiar «cd» al proyecto", symbol: "terminal.fill", when: "hay un proyecto activo")
        case .copyPath: return QuickDescriptor(title: "copiar la ruta", symbol: "doc.on.doc", when: "hay un proyecto activo")
        case .musicPrev: return QuickDescriptor(title: "anterior", symbol: "backward.fill", when: "suena algo en Spotify o Apple Music")
        case .musicNext: return QuickDescriptor(title: "siguiente", symbol: "forward.fill", when: "suena algo en Spotify o Apple Music")
        }
    }

    /// Lo que se ve y lo que va al menu "+": con perfiles por app, primero lo que esa app necesita y luego el orden del usuario;
    /// solo lo disponible, sin repetir y con tope de cinco.
    static func layout(order: [QuickAction], context c: QuickContext, appAware: Bool = true) -> (visible: [QuickAction], overflow: [QuickAction]) {
        var list = order
        if appAware { let pri = c.profile.priority; list = pri + order.filter { !pri.contains($0) } }
        var seen = Set<QuickAction>()
        let usable = list.filter { available($0, c) && seen.insert($0).inserted }
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
