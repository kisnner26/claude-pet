import AppKit
import SwiftUI

/// Mission control: el mismo lenguaje que los ajustes (cristal oscuro, etiquetas mono, un solo acento).
/// Arriba lo que pide atencion, luego filtros y tres vistas (lista, cuadricula, linea de tiempo) y, debajo, el proyecto actual.
struct MissionDashboardView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var control: MissionControl
    @State private var dissolved = 0.0
    private let fixedSize: Bool

    init(store: PetStore, control: MissionControl? = nil, fixedSize: Bool = false) {
        self.store = store
        self.fixedSize = fixedSize
        _control = ObservedObject(wrappedValue: control ?? store.mission)
    }

    private var now: Date { Date() }

    var body: some View {
        let brief = control.brief
        ZStack {
            VisualEffect()
            DashboardTheme.black.opacity(0.86)
            RadialGradient(colors: [SettingsTheme.accent.opacity(0.12), .clear], center: .topLeading, startRadius: 10, endRadius: 480)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    BriefCard(brief: brief) { control.perform($0) }
                    filterBar
                    results
                    currentProject(brief: brief)
                    footer
                }
                .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 20)
                .modifier(Condense(progress: dissolved, reduceMotion: store.reduceMotion, anchor: .top))
            }
            .scrollIndicators(.never)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardRevealed)) { _ in
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { dissolved = 0.6 }
            withAnimation(.easeOut(duration: 0.18)) { dissolved = 0 }
        }
        .frame(width: 760, height: fixedSize ? 980 : 660)
        .environment(\.settingsReduceMotion, store.reduceMotion)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tablero operativo de claude pet")
    }

    // MARK: cabecera

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SLabel("mission control", tint: SettingsTheme.accent)
                Text("lo que pasa en tus proyectos").font(.system(size: 22, weight: .bold)).tracking(-0.3)
            }
            Spacer(minLength: 8)
            agentPill("claude", store.state, store.claudePresent)
            agentPill("codex", store.codexState, store.codexPresent)
        }
    }

    private func agentPill(_ name: String, _ state: PetState, _ present: Bool) -> some View {
        HStack(spacing: 7) {
            Circle().fill(present ? SettingsTheme.agentColor(name) : Color.white.opacity(0.25)).frame(width: 7, height: 7)
            Text(name).font(.system(size: 11.5, weight: .medium, design: .monospaced))
            Text(present ? state.label.lowercased() : "en reposo").font(.system(size: 11, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: filtros

    private func shortTitle(_ m: MissionViewMode) -> String { m == .timeline ? "línea" : m.rawValue }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(DashboardTheme.muted)
                    TextField("buscar proyecto, agente o estado", text: $control.searchText).textFieldStyle(.plain).font(.system(size: 13))
                        .accessibilityLabel("buscar en mission control")
                    if !control.searchText.isEmpty {
                        Button { control.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DashboardTheme.muted) }
                            .buttonStyle(.plain).accessibilityLabel("borrar la búsqueda")
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                SSegmentedControl(selection: $control.viewMode, options: MissionViewMode.allCases.map { ($0, shortTitle($0)) }, compact: true)
                    .accessibilityLabel("modo de vista")
            }
            HStack(spacing: 14) {
                labeled("agente") { SSegmentedControl(selection: $control.timelineFilter, options: MissionAgentFilter.allCases.map { ($0, $0.rawValue) }, compact: true) }
                labeled("rango") { SSegmentedControl(selection: $control.timelineRange, options: MissionRange.allCases.map { ($0, $0.rawValue) }, compact: true) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                SLabel("estado")
                ForEach(MissionStateFilter.allCases) { s in
                    SChip(title: s.rawValue, count: s == .all ? nil : stateCount(s), selected: control.timelineState == s) { control.timelineState = s }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Text(summaryLine).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
                if control.filter.isActive {
                    Button { control.clearFilters() } label: {
                        Text("quitar filtros (\(control.filter.activeCount))").font(.system(size: 10.5, design: .monospaced)).underline().foregroundStyle(SettingsTheme.accent)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                projectMenu
                orderButton
            }
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { SLabel(title); content() }
    }

    private func stateCount(_ s: MissionStateFilter) -> Int {
        var f = control.filter; f.state = s
        return f.apply(control.timeline, now: now).count
    }

    private var summaryLine: String {
        let n = control.filteredTimeline.count, total = control.timeline.count
        return control.filter.isActive ? "\(n) de \(total) eventos" : "\(total) eventos · \(control.timelineAgentCounts)"
    }

    private var projectMenu: some View {
        Menu {
            ForEach(control.timelineProjects, id: \.self) { p in
                Button(p) { control.timelineProject = (p == "todos" ? "" : p) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10))
                Text(control.timelineProject.isEmpty ? "proyecto: todos" : control.timelineProject).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(DashboardTheme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(control.timelineProject.isEmpty ? Color.white.opacity(0.06) : SettingsTheme.accent.opacity(0.25)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("filtrar por proyecto")
    }

    private var orderButton: some View {
        Button { control.timelineOrder = control.timelineOrder == .newest ? .oldest : .newest } label: {
            HStack(spacing: 5) {
                Image(systemName: control.timelineOrder == .newest ? "arrow.down" : "arrow.up").font(.system(size: 9, weight: .bold))
                Text(control.timelineOrder == .newest ? "recientes" : "antiguos").font(.system(size: 11, design: .monospaced)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain).help("cambiar el orden").accessibilityLabel("orden: \(control.timelineOrder.rawValue)")
    }

    // MARK: resultados

    @ViewBuilder private var results: some View {
        let events = control.filteredTimeline
        if control.timeline.isEmpty {
            emptyState(title: "sin actividad todavía", detail: "cuando claude o codex empiecen a trabajar, sus eventos y proyectos aparecerán aquí.", showClear: false)
        } else {
            switch control.viewMode {
            case .list:
                if events.isEmpty { noMatches } else { eventList(events) }
            case .grid:
                let cards = control.projectCards
                if cards.isEmpty { noMatches } else { projectGrid(cards) }
            case .timeline:
                if events.isEmpty { noMatches } else { timelineView(events) }
            }
        }
    }

    private var noMatches: some View {
        emptyState(title: "ningún evento coincide", detail: "prueba con otro rango o quita algún filtro.", showClear: true)
    }

    private func emptyState(title: String, detail: String, showClear: Bool) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: -10) {
                ClaudeSprite().frame(width: 52, height: 52).opacity(0.7)
                CodexSprite(skin: store.codexSkin).frame(width: 52, height: 52).opacity(0.7)
            }
            VStack(alignment: .leading, spacing: 6) {
                SLabel("vacío")
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(DashboardTheme.muted).fixedSize(horizontal: false, vertical: true)
                if showClear { SButton(title: "quitar filtros", symbol: "xmark") { control.clearFilters() }.padding(.top, 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    private func eventList(_ events: [MissionEvent]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(events.prefix(40).enumerated()), id: \.element.id) { i, e in
                if i > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                HStack(spacing: 12) {
                    Text(e.at, format: .dateTime.hour().minute()).font(.system(size: 11, design: .monospaced)).foregroundStyle(DashboardTheme.muted).lineLimit(1).fixedSize().frame(width: 66, alignment: .leading)
                    Rectangle().fill(SettingsTheme.agentColor(e.agent)).frame(width: 6, height: 6)
                    Text(e.agent).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 52, alignment: .leading)
                    stateTag(e.state)
                    Spacer(minLength: 8)
                    Text(MissionFilter.projectName(e.project)).font(.system(size: 12)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
                    Text(MissionProjectCard.ago(e.at, now: now)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted.opacity(0.8)).frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func stateTag(_ s: PetState) -> some View {
        let tint: Color = s == .error ? SettingsTheme.red : s == .waiting ? SettingsTheme.amber : s == .done ? SettingsTheme.green : s.isActive ? SettingsTheme.accent : DashboardTheme.muted
        return Text(s == .waiting ? "tu aprobación" : s.label.lowercased()).font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.14)))
    }

    private func projectGrid(_ cards: [MissionProjectCard]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(cards) { card in projectCard(card) }
        }
    }

    private func projectCard(_ c: MissionProjectCard) -> some View {
        let selected = control.timelineProject == c.name
        return Button { control.timelineProject = selected ? "" : c.name } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(c.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    stateTag(c.lastState)
                }
                gitLine(c.git)
                SBars(values: c.series, height: 38, summary: "actividad de \(c.name) en 7 días: " + c.series.map { "\(Int($0))" }.joined(separator: ", "))
                HStack(spacing: 12) {
                    HStack(spacing: 5) { Rectangle().fill(SettingsTheme.agentClaude).frame(width: 6, height: 6); Text("\(c.claude)") }
                    HStack(spacing: 5) { Rectangle().fill(SettingsTheme.agentCodex).frame(width: 6, height: 6); Text("\(c.codex)") }
                    Spacer(minLength: 4)
                    Text(MissionProjectCard.ago(c.lastAt, now: now))
                }
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(selected ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? SettingsTheme.accent : Color.white.opacity(0.09), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("filtrar por este proyecto")
    }

    @ViewBuilder private func gitLine(_ g: GitHealth?) -> some View {
        if let g, g.available {
            let tint: Color = g.conflicts > 0 ? SettingsTheme.red : g.affected == 0 ? SettingsTheme.green : SettingsTheme.amber
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(g.branch.isEmpty ? "git" : g.branch).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                Text(g.label).font(.system(size: 11)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
            }
        } else {
            HStack(spacing: 7) {
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 1).frame(width: 7, height: 7)
                Text("git sin leer").font(.system(size: 11)).foregroundStyle(DashboardTheme.muted)
            }
        }
    }

    private func timelineView(_ events: [MissionEvent]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SessionTrailView(events: control.timeline, reduceMotion: store.reduceMotion)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.prefix(30).enumerated()), id: \.element.id) { i, e in
                    HStack(alignment: .top, spacing: 14) {
                        Text(e.at, format: .dateTime.hour().minute()).font(.system(size: 11, design: .monospaced)).foregroundStyle(DashboardTheme.muted).lineLimit(1).fixedSize().frame(width: 66, alignment: .trailing).padding(.top, 1)
                        VStack(spacing: 0) {
                            Circle().fill(SettingsTheme.agentColor(e.agent)).frame(width: 9, height: 9)
                            if i < min(events.count, 30) - 1 { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1).frame(maxHeight: .infinity) }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(e.agent).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                stateTag(e.state)
                            }
                            Text(MissionFilter.projectName(e.project)).font(.system(size: 11.5)).foregroundStyle(DashboardTheme.muted)
                        }
                        .padding(.bottom, 14)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    // MARK: proyecto actual

    @ViewBuilder private func currentProject(brief: MissionBrief) -> some View {
        let hasAny = control.git.available || !control.changes.isEmpty || !store.codexChanges.isEmpty || control.worktrees.count > 1 || !attentionItems(brief).isEmpty
        if hasAny {
            VStack(alignment: .leading, spacing: 14) {
                SLabel("proyecto actual" + (control.workspace.isEmpty ? "" : " · " + URL(fileURLWithPath: control.workspace).lastPathComponent))
                if control.git.available { GitStrip(health: control.git, refresh: control.refreshGit) }
                if !control.changes.isEmpty {
                    ChangeMapView(files: control.changes, title: "mapa de cambios · claude") { store.pullDiff($0) }
                }
                if !store.codexChanges.isEmpty, store.codexWorkspace != control.workspace {
                    ChangeMapView(files: store.codexChanges, title: "mapa de cambios · codex") { store.pullCodexDiff($0) }
                }
                if control.worktrees.count > 1 {
                    BranchWebView(nodes: control.worktrees, title: "telaraña de ramas · claude") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0.path)]) }
                }
                if store.codexWorktrees.count > 1, store.codexWorkspace != control.workspace {
                    BranchWebView(nodes: store.codexWorktrees, title: "telaraña de ramas · codex") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0.path)]) }
                }
                attention(attentionItems(brief))
            }
        }
    }

    private func attentionItems(_ brief: MissionBrief) -> [MissionInsight] {
        control.insights.filter { $0.tone == .caution || $0.tone == .danger }
            .filter { !brief.title.contains($0.title) && !Self.covered(by: brief).contains($0.id) }
    }

    @ViewBuilder private func attention(_ items: [MissionInsight]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SLabel("también")
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(item.tone == .danger ? SettingsTheme.red : SettingsTheme.amber).frame(width: 6, height: 6)
                        Text(item.title).font(.system(size: 12.5, weight: .medium))
                        Text(item.detail).font(.system(size: 12)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private static func covered(by brief: MissionBrief) -> Set<String> {
        switch brief.title {
        case "claude espera tu aprobación": return ["approval"]
        case "mismo proyecto": return ["radar"]
        case "claude falló": return ["recovery"]
        default: return brief.tone == .danger ? ["conflicts"] : []
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 8) {
                SButton(title: store.userHidden ? "mostrar mascotas" : "ocultar mascotas", symbol: store.userHidden ? "eye" : "eye.slash") { AppController.shared.toggleWindow() }
                SButton(title: store.showBubble ? "burbuja: sí" : "burbuja: no", symbol: "bubble.left") { store.showBubble.toggle() }
                Spacer(minLength: 0)
                if !store.foregroundAppName.isEmpty {
                    Text("frente: \(store.foregroundAppName)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
                }
            }
            SLabel("lectura local · sin red ni telemetría")
        }
    }
}

private struct BriefCard: View {
    let brief: MissionBrief
    let run: (MissionAction) -> Void

    private var tint: Color {
        switch brief.tone {
        case .danger: return SettingsTheme.red
        case .caution: return SettingsTheme.amber
        case .calm: return SettingsTheme.green
        case .active: return SettingsTheme.accent
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Rectangle().fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                SLabel("ahora", tint: tint)
                Text(brief.title).font(.system(size: 19, weight: .semibold))
                Text(brief.detail).font(.system(size: 12.5)).foregroundStyle(DashboardTheme.muted)
            }
            Spacer(minLength: 12)
            if let action = brief.action, let title = brief.actionTitle {
                SButton(title: title, prominent: true) { run(action) }
            }
        }
        .padding(.vertical, 16).padding(.trailing, 18)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.04)))
        .accessibilityElement(children: .contain)
    }
}

private struct GitStrip: View {
    let health: GitHealth
    let refresh: () -> Void

    private var parts: [(Int, String)] {
        [(health.changed, "modificados"), (health.staged, "preparados"), (health.untracked, "nuevos"), (health.conflicts, "conflictos")].filter { $0.0 > 0 }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(DashboardTheme.muted)
            if health.available {
                Text(health.branch.isEmpty ? "git" : health.branch).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                if parts.isEmpty {
                    Text("limpio").font(.system(size: 12.5)).foregroundStyle(DashboardTheme.muted)
                } else {
                    Text(parts.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                        .font(.system(size: 12.5)).foregroundStyle(health.conflicts > 0 ? SettingsTheme.red : DashboardTheme.muted).lineLimit(1)
                }
            } else {
                Text("sin repositorio git").font(.system(size: 12.5)).foregroundStyle(DashboardTheme.muted)
            }
            Spacer(minLength: 0)
            Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(DashboardTheme.muted)
                .help("actualizar git").accessibilityLabel("actualizar git")
        }
    }
}

/// Captura de documentacion de mission control con datos de ejemplo, fuera de pantalla.
enum MissionSnapshot {
    @MainActor static func render(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        setenv("CLAUDE_PET_REDUCE_MOTION", "1", 1)
        let tmp = NSTemporaryDirectory() + "snap-mission-\(UUID().uuidString)"
        setenv("CLAUDE_PET_STATS", tmp, 1)
        let base = URL(fileURLWithPath: tmp, isDirectory: true)
        let names = ["claude-pet", "volve", "tonada"]
        for n in names { try? FileManager.default.createDirectory(at: base.appendingPathComponent(n), withIntermediateDirectories: true) }
        let t0 = Date().addingTimeInterval(-3 * 3600)
        var clock = t0
        let health: [String: GitHealth] = [
            "claude-pet": GitHealth(changed: 3, staged: 2, untracked: 1, conflicts: 0, affected: 6, branch: "main", available: true, limited: false),
            "volve": GitHealth(changed: 0, staged: 0, untracked: 0, conflicts: 0, affected: 0, branch: "feat/mapa", available: true, limited: false),
            "tonada": GitHealth(changed: 1, staged: 0, untracked: 0, conflicts: 1, affected: 2, branch: "fix/audio", available: true, limited: false)]
        let mc = MissionControl(now: { clock }, scanner: { path in health[URL(fileURLWithPath: path).lastPathComponent] ?? GitHealth() })
        let plan: [(Int, String, PetState, Int)] = [(0, "claude", .thinking, 0), (4, "claude", .tool, 0), (9, "codex", .thinking, 1), (14, "claude", .done, 0), (22, "claude", .thinking, 1),
                                                    (31, "codex", .tool, 2), (40, "claude", .waiting, 1), (47, "claude", .tool, 1), (63, "codex", .done, 2), (80, "claude", .error, 2), (95, "claude", .thinking, 0), (120, "codex", .tool, 0)]
        for (min, agent, state, p) in plan {
            clock = t0.addingTimeInterval(Double(min) * 60)
            let ws = base.appendingPathComponent(names[p]).path
            if agent == "claude" { mc.recordLocal(state: state, project: ws, workspace: ws, session: "s\(p)") } else { mc.recordPeer(state: state, project: ws) }
        }
        clock = Date()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let stats = ActivityStats.shared
        for (i, n) in names.enumerated() { for d in 0..<7 { for _ in 0..<((d * (i + 2) + 3 * i) % 9) { stats.recordTool(agent: "claude", project: n, at: Date().addingTimeInterval(Double(d - 6) * 86_400)) } } }
        mc.viewMode = .list; mc.timelineFilter = .all; mc.timelineState = .all; mc.timelineRange = .all; mc.searchText = ""
        for (name, mode, filtered) in [("lista", MissionViewMode.list, false), ("cuadricula", .grid, false), ("linea", .timeline, false), ("filtrado", .list, true), ("vacio", .list, true)] {
            mc.viewMode = mode
            mc.clearFilters()
            if filtered { mc.timelineFilter = .claude; mc.timelineState = .active; mc.timelineRange = .hour }
            if name == "vacio" { mc.searchText = "zzz" }
            capture(MissionDashboardView(store: PetStore.shared, control: mc, fixedSize: true), to: directory + "/mission-\(name).png")
        }
        mc.clearFilters(); mc.timelineFilter = .all
    }

    @MainActor private static func capture(_ view: MissionDashboardView, to path: String) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 980), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 980)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }
}
