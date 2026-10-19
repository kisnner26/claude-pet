import AppKit
import SwiftUI

private enum Ink {
    static let accent = Color(hex: 0x7DB4FF)
    static let alert = Color(hex: 0xFF8A7A)
    static let primary = Pal.cream
    static let secondary = Pal.cream.opacity(0.68)
    static let tertiary = Pal.cream.opacity(0.5)
    static let fill = Color.white.opacity(0.055)
    static let line = Color.white.opacity(0.08)
}

struct MissionDashboardView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var control: MissionControl

    @State private var dissolved = 0.0

    init(store: PetStore) {
        self.store = store
        _control = ObservedObject(wrappedValue: store.mission)
    }

    var body: some View {
        let brief = control.brief
        ZStack {
            GlassBackground()
            Color.black.opacity(0.28)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    agents
                    BriefCard(brief: brief) { control.perform($0) }
                    if control.git.available { GitStrip(health: control.git, refresh: control.refreshGit) }
                    if !control.changes.isEmpty {
                        ChangeMapView(files: control.changes, title: "mapa de cambios · claude") { file in
                            store.pullDiff(file)
                        }
                    }
                    if !store.codexChanges.isEmpty, store.codexWorkspace != control.workspace {
                        ChangeMapView(files: store.codexChanges, title: "mapa de cambios · codex") { file in
                            store.pullCodexDiff(file)
                        }
                    }
                    if control.worktrees.count > 1 {
                        BranchWebView(nodes: control.worktrees, title: "telaraña de ramas · claude") { node in
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                        }
                    }
                    if store.codexWorktrees.count > 1, store.codexWorkspace != control.workspace {
                        BranchWebView(nodes: store.codexWorktrees, title: "telaraña de ramas · codex") { node in
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                        }
                    }
                    attention(excluding: brief)
                    Timeline(events: Array(control.timeline.prefix(4)), all: control.timeline, reduceMotion: store.reduceMotion)
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 18)
                .modifier(Condense(progress: dissolved, reduceMotion: store.reduceMotion, anchor: .top))
            }
            .scrollIndicators(.never)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardRevealed)) { _ in
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { dissolved = 0.6 }
            withAnimation(.easeOut(duration: 0.18)) { dissolved = 0 }
        }
        .frame(width: 560, height: 700)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tablero operativo de claude pet")
    }

    private var agents: some View {
        HStack(spacing: 18) {
            AgentDot(name: "claude", state: store.state, active: store.claudePresent, tint: Pal.body)
            AgentDot(name: "codex", state: store.codexState, active: store.codexPresent, tint: Color(hex: 0x96EBFF))
            Spacer(minLength: 0)
            if control.activeSince != nil {
                Text("\(max(1, Int(control.elapsed / 60))) min · \(control.toolCalls) herramientas")
                    .font(.caption).foregroundStyle(Ink.tertiary).monospacedDigit()
            }
        }
    }

    /// Solo lo que pide atención y no es ya el titular. Si todo está tranquilo, no se dibuja nada.
    @ViewBuilder private func attention(excluding brief: MissionBrief) -> some View {
        let items = control.insights.filter { $0.tone == .caution || $0.tone == .danger }
            .filter { !brief.title.contains($0.title) && !Self.covered(by: brief).contains($0.id) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("también")
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(item.tone == .danger ? Ink.alert : Ink.accent).frame(width: 6, height: 6)
                        Text(item.title).font(.callout.weight(.medium)).foregroundStyle(Ink.primary)
                        Text(item.detail).font(.callout).foregroundStyle(Ink.secondary).lineLimit(1)
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
            Divider().overlay(Ink.line)
            HStack(spacing: 8) {
                Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                    AppController.shared.toggleWindow()
                }
                Toggle("burbuja", isOn: $store.showBubble).toggleStyle(.button)
                Spacer(minLength: 0)
                if !store.foregroundAppName.isEmpty {
                    Text("frente: \(store.foregroundAppName)")
                        .font(.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                }
            }
            .controlSize(.small)
            Text("lectura local · sin red ni telemetría")
                .font(.caption2).foregroundStyle(Ink.tertiary)
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(Ink.tertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct AgentDot: View {
    let name: String
    let state: PetState
    let active: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(active ? tint : Ink.tertiary.opacity(0.6)).frame(width: 8, height: 8)
            Text(name).font(.callout.weight(.semibold)).foregroundStyle(Ink.primary)
            Text(active ? state.label.lowercased() : "en reposo").font(.callout).foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BriefCard: View {
    let brief: MissionBrief
    let run: (MissionAction) -> Void

    private var tint: Color {
        switch brief.tone {
        case .danger: return Ink.alert
        case .calm: return Ink.tertiary
        default: return Ink.accent
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(brief.title).font(.title3.weight(.semibold)).foregroundStyle(Ink.primary)
                Text(brief.detail).font(.callout).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 12)
            if let action = brief.action, let title = brief.actionTitle {
                Button(title) { run(action) }
                    .buttonStyle(.borderedProminent)
                    .tint(brief.tone == .danger ? Ink.alert : Ink.accent)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .frame(minHeight: 76)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.line) }
        .accessibilityElement(children: .contain)
    }
}

private struct GitStrip: View {
    let health: GitHealth
    let refresh: () -> Void

    private var parts: [(Int, String)] {
        [(health.changed, "modificados"), (health.staged, "preparados"), (health.untracked, "nuevos"), (health.conflicts, "conflictos")]
            .filter { $0.0 > 0 }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Ink.tertiary)
            if health.available {
                Text(health.branch.isEmpty ? "git" : health.branch).font(.callout.weight(.medium)).foregroundStyle(Ink.primary)
                if parts.isEmpty {
                    Text("limpio").font(.callout).foregroundStyle(Ink.secondary)
                } else {
                    Text(parts.map { "\($0.0) \($0.1)" }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(health.conflicts > 0 ? Ink.alert : Ink.secondary).lineLimit(1)
                }
            } else {
                Text("sin repositorio git").font(.callout).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
            Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).foregroundStyle(Ink.secondary)
                .help("actualizar git")
                .accessibilityLabel("actualizar git")
        }
    }
}

private struct Timeline: View {
    let events: [MissionEvent]
    let all: [MissionEvent]
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("estela de sesión")
            if !all.isEmpty { SessionTrailView(events: all, reduceMotion: reduceMotion) }
            if events.isEmpty {
                Text("sin actividad todavía · aparecerá cuando Claude o Codex empiecen")
                    .font(.callout).foregroundStyle(Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        HStack(spacing: 10) {
                            Text(event.at, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit()).foregroundStyle(Ink.tertiary).frame(width: 40, alignment: .leading)
                            Circle().fill(event.agent == "claude" ? Pal.body : Color(hex: 0x96EBFF)).frame(width: 6, height: 6)
                            Text(event.agent).font(.callout).foregroundStyle(Ink.primary)
                            Text(event.state.label.lowercased()).font(.callout).foregroundStyle(Ink.secondary)
                            Spacer(minLength: 8)
                            if !event.project.isEmpty {
                                Text((event.project as NSString).lastPathComponent)
                                    .font(.caption).foregroundStyle(Ink.tertiary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
