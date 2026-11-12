import Foundation

@MainActor
enum MissionFilterSelfTest {
    static func run() -> Bool {
        // las preferencias de vista viven en UserDefaults: se parte de cero y se limpian al salir
        let prefKeys = ["missionAgent", "missionOrder", "missionState", "missionRange", "missionView"]
        prefKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer { prefKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let mission = MissionControl()
        mission.recordLocal(state: .thinking, project: "demo", workspace: "/tmp/demo", session: "a")
        mission.recordPeer(state: .tool, project: "demo")
        mission.timelineFilter = .claude
        let claudeOnly = mission.filteredTimeline.allSatisfy { $0.agent == "claude" }
        mission.timelineFilter = .codex
        let codexOnly = mission.filteredTimeline.allSatisfy { $0.agent == "codex" }
        mission.timelineFilter = .all
        let all = mission.filteredTimeline.count >= 2
        let label = mission.filteredTimelineLabel == "2 eventos"
        let markdown = mission.timelineMarkdown.contains("**") && !mission.timelineMarkdown.contains("/tmp")
        let json = (try? JSONSerialization.jsonObject(with: Data(mission.timelineJSON.utf8)) as? [[String: String]])?.count == 2
            && !mission.timelineJSON.contains("/tmp")
        let newest = mission.filteredTimeline.first?.agent == "codex"
        mission.timelineOrder = .oldest
        let oldest = mission.filteredTimeline.first?.agent == "claude"
        mission.timelineProject = "demo"
        let projectOnly = mission.filteredTimeline.count == 2 && mission.timelineProjects.contains("demo")
        mission.clearTimeline()
        let cleared = mission.filteredTimeline.isEmpty
        var extra = true
        func check(_ name: String, _ v: Bool) { if !v { extra = false; print("FALLO \(name)") } }

        // MissionFilter: agente, proyecto, estado, rango, texto y orden sobre eventos con hora conocida
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func ev(_ minutesAgo: Double, _ agent: String, _ state: PetState, _ project: String) -> MissionEvent { MissionEvent(at: ref.addingTimeInterval(-minutesAgo * 60), agent: agent, state: state, project: project) }
        let events = [ev(5, "codex", .tool, "/w/alfa"), ev(30, "claude", .waiting, "/w/beta"), ev(90, "claude", .done, "/w/alfa"), ev(60 * 30, "claude", .error, "/w/beta"), ev(61 * 24 * 60, "codex", .thinking, "")]
        var f = MissionFilter()
        check("mf-default", !f.isActive && f.activeCount == 0 && f.apply(events, now: ref, calendar: cal).count == 5)
        f.agent = .codex
        check("mf-agent", f.apply(events, now: ref, calendar: cal).count == 2 && f.activeCount == 1)
        f.agent = .all; f.project = "alfa"
        check("mf-project", f.apply(events, now: ref, calendar: cal).count == 2 && f.apply(events, now: ref, calendar: cal, ignoringProject: true).count == 5)
        f.project = "sin proyecto"
        check("mf-no-project", f.apply(events, now: ref, calendar: cal).count == 1)
        f.project = "todos"
        check("mf-todos-is-all", !f.isActive)
        f.state = .active
        check("mf-state-active", f.apply(events, now: ref, calendar: cal).map(\.state) == [.tool, .thinking])
        f.state = .waiting
        check("mf-state-waiting", f.apply(events, now: ref, calendar: cal).count == 1)
        f.state = .error
        check("mf-state-error", f.apply(events, now: ref, calendar: cal).first?.project == "/w/beta")
        f.state = .all; f.range = .hour
        check("mf-range-hour", f.apply(events, now: ref, calendar: cal).count == 2)
        f.range = .today
        check("mf-range-today", f.apply(events, now: ref, calendar: cal).count == 3)
        f.range = .all; f.query = "BETA"
        check("mf-query-project", f.apply(events, now: ref, calendar: cal).count == 2)
        f.query = "ejecutando"
        check("mf-query-state", f.apply(events, now: ref, calendar: cal).count == 1)
        f.query = "  "
        check("mf-blank-query-inactive", !f.isActive)
        f.query = "zzz"
        check("mf-query-none", f.apply(events, now: ref, calendar: cal).isEmpty)
        f = MissionFilter(); f.order = .oldest
        check("mf-order", f.apply(events, now: ref, calendar: cal).first?.agent == "codex" && f.apply(events, now: ref, calendar: cal).first?.project == "" && f.activeCount == 0)
        f = MissionFilter(agent: .claude, project: "beta", state: .error, range: .all, query: "", order: .newest)
        check("mf-combined", f.apply(events, now: ref, calendar: cal).count == 1 && f.activeCount == 3)
        check("mf-state-all-matches", PetState.allCases.allSatisfy { MissionStateFilter.all.matches($0) })

        // tarjetas de proyecto
        let cards = MissionProjectCard.group(events)
        check("cards-group", cards.count == 3 && cards.first?.name == "alfa" && cards.first?.events == 2 && cards.first?.claude == 1 && cards.first?.codex == 1)
        check("cards-last-state", cards.first?.lastState == .tool && cards.last?.name == "sin proyecto")
        check("cards-empty", MissionProjectCard.group([]).isEmpty)
        var stats: [String: DayStats] = [:]
        stats[ActivityStats.dayKey(ref, calendar: cal)] = DayStats(sessions: 0, tools: 4, permissions: 0, errors: 0, agents: [:], projects: ["alfa": 4])
        stats[ActivityStats.dayKey(ref.addingTimeInterval(-2 * 86_400), calendar: cal)] = DayStats(sessions: 0, tools: 2, permissions: 0, errors: 0, agents: [:], projects: ["alfa": 2, "beta": 1])
        check("cards-series", MissionProjectCard.series("alfa", stats, endingAt: ref, calendar: cal) == [0, 0, 0, 0, 2, 0, 4] && MissionProjectCard.series("zeta", stats, endingAt: ref, calendar: cal) == [Double](repeating: 0, count: 7))
        check("cards-ago", MissionProjectCard.ago(ref, now: ref) == "ahora" && MissionProjectCard.ago(ref.addingTimeInterval(-300), now: ref) == "hace 5 min" && MissionProjectCard.ago(ref.addingTimeInterval(-7_300), now: ref) == "hace 2 h" && MissionProjectCard.ago(ref.addingTimeInterval(-3 * 86_400), now: ref) == "hace 3 d")

        // MissionControl: los filtros nuevos se aplican y se quitan de una vez
        let m2 = MissionControl()
        m2.recordLocal(state: .waiting, project: "demo", workspace: "/tmp/demo", session: "a")
        m2.recordPeer(state: .tool, project: "otro")
        m2.clearFilters()
        m2.timelineState = .waiting
        check("mc-state", m2.filteredTimeline.count == 1 && m2.filteredTimeline.first?.agent == "claude" && m2.filter.activeCount == 1)
        m2.timelineState = .all; m2.searchText = "otro"
        check("mc-search", m2.filteredTimeline.count == 1 && m2.projectCards.count == 1 && m2.projectCards.first?.name == "otro")
        m2.clearFilters()
        check("mc-clear", !m2.filter.isActive && m2.filteredTimeline.count == 2 && m2.projectCards.count == 2)
        m2.viewMode = .grid
        check("mc-view-persisted", UserDefaults.standard.string(forKey: "missionView") == "cuadrícula")
        m2.viewMode = .list

        // traducciones: etiquetas fijas y frases con cifras
        let labels = MissionStateFilter.allCases.map(\.rawValue) + MissionRange.allCases.map(\.rawValue) + MissionViewMode.allCases.map(\.rawValue)
            + ["línea", "mission control", "lo que pasa en tus proyectos", "sin actividad todavía", "ningún evento coincide", "vacío", "ahora", "tu aprobación", "git sin leer", "proyecto actual", "recientes", "antiguos"]
        let missing = labels.filter { L10nEN.table[$0] == nil }
        check("lang-mission-labels \(missing)", missing.isEmpty)
        let saved = L.current; L.current = .en
        check("lang-mission-phrases", L.tr("hace 5 min") == "5 min ago" && L.tr("3 de 12 eventos") == "3 of 12 events" && L.tr("12 eventos · claude 8 · codex 4") == "12 events · claude 8 · codex 4" && L.tr("quitar filtros (2)") == "clear filters (2)")
        L.current = saved

        let ok = extra && claudeOnly && codexOnly && all && label && markdown && json && newest && oldest && projectOnly && cleared
        print(ok ? "FILTRO OK" : "FILTRO FALLOS")
        return ok
    }
}
