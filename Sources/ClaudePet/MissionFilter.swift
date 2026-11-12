import Foundation

enum MissionStateFilter: String, CaseIterable, Identifiable {
    case all = "todos", active = "activos", waiting = "esperando", done = "listos", error = "error"
    var id: String { rawValue }
    func matches(_ s: PetState) -> Bool {
        switch self {
        case .all: return true
        case .active: return s == .starting || s == .thinking || s == .tool
        case .waiting: return s == .waiting
        case .done: return s == .done
        case .error: return s == .error
        }
    }
}

enum MissionRange: String, CaseIterable, Identifiable {
    case all = "todo", hour = "última hora", today = "hoy"
    var id: String { rawValue }
    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .hour: return now.timeIntervalSince(date) <= 3600
        case .today: return calendar.isDate(date, inSameDayAs: now)
        }
    }
}

enum MissionViewMode: String, CaseIterable, Identifiable {
    case list = "lista", grid = "cuadrícula", timeline = "línea de tiempo"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .list: return "list.bullet"; case .grid: return "square.grid.2x2"; case .timeline: return "chart.bar.xaxis" }
    }
}

/// Todos los filtros de mission control en un solo valor: agente, proyecto, estado, rango, texto y orden.
/// `MissionControl` publica cada pieza por separado (ya existian `timelineFilter`, `timelineProject` y `timelineOrder`)
/// y arma este valor para filtrar; asi la logica se prueba sin interfaz.
struct MissionFilter: Equatable {
    var agent: MissionAgentFilter = .all
    /// "" o "todos" = cualquier proyecto.
    var project = ""
    var state: MissionStateFilter = .all
    var range: MissionRange = .all
    var query = ""
    var order: MissionTimelineOrder = .newest

    static func projectName(_ raw: String) -> String { raw.isEmpty ? "sin proyecto" : URL(fileURLWithPath: raw).lastPathComponent }

    var isActive: Bool { agent != .all || !projectIsAll || state != .all || range != .all || !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var projectIsAll: Bool { project.isEmpty || project == "todos" }
    var activeCount: Int { (agent != .all ? 1 : 0) + (projectIsAll ? 0 : 1) + (state != .all ? 1 : 0) + (range != .all ? 1 : 0) + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1) }

    /// `ignoringProject` sirve para las tarjetas de proyecto: se agrupan todos, no solo el elegido.
    func apply(_ events: [MissionEvent], now: Date, calendar: Calendar = .current, ignoringProject: Bool = false) -> [MissionEvent] {
        let q = SettingsPage.fold(query)
        let out = events.filter { e in
            if agent != .all, e.agent != agent.rawValue { return false }
            if !ignoringProject, !projectIsAll, Self.projectName(e.project) != project { return false }
            if !state.matches(e.state) { return false }
            if !range.includes(e.at, now: now, calendar: calendar) { return false }
            if !q.isEmpty {
                let hay = SettingsPage.fold(e.agent + " " + e.state.label + " " + Self.projectName(e.project))
                if !hay.contains(q) { return false }
            }
            return true
        }
        // la linea de tiempo ya guarda lo mas nuevo primero: se respeta ese orden (sin reordenar, para no romper empates)
        return order == .newest ? out : out.reversed()
    }
}

/// Una tarjeta por proyecto: cuanto paso, quien lo toco, como esta su git y su actividad de la semana.
struct MissionProjectCard: Identifiable, Equatable {
    let name: String
    let events: Int
    let claude: Int
    let codex: Int
    let lastAt: Date
    let lastState: PetState
    var git: GitHealth?
    var series: [Double] = []
    var id: String { name }

    /// Agrupa los eventos por proyecto, el de actividad mas reciente primero.
    static func group(_ events: [MissionEvent]) -> [MissionProjectCard] {
        var buckets: [String: [MissionEvent]] = [:]
        for e in events { buckets[MissionFilter.projectName(e.project), default: []].append(e) }
        return buckets.compactMap { name, list -> MissionProjectCard? in
            guard let last = list.max(by: { $0.at < $1.at }) else { return nil }
            return MissionProjectCard(name: name, events: list.count, claude: list.filter { $0.agent == "claude" }.count, codex: list.filter { $0.agent == "codex" }.count,
                                      lastAt: last.at, lastState: last.state)
        }
        .sorted { $0.lastAt == $1.lastAt ? $0.name < $1.name : $0.lastAt > $1.lastAt }
    }

    /// Acciones por dia del proyecto en los ultimos `count` dias (de `ActivityStats`; los nombres se guardan limpios).
    static func series(_ project: String, _ data: [String: DayStats], endingAt date: Date, count: Int = 7, calendar: Calendar = Calendar(identifier: .gregorian)) -> [Double] {
        let key = ActivityStats.clean(project)
        return stride(from: count - 1, through: 0, by: -1).map { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: date) else { return 0 }
            return Double(data[ActivityStats.dayKey(d, calendar: calendar)]?.projects[key] ?? 0)
        }
    }

    /// "ahora", "hace 5 min", "hace 2 h", "hace 3 d".
    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 86_400 { return "hace \(s / 3600) h" }
        return "hace \(s / 86_400) d"
    }
}
