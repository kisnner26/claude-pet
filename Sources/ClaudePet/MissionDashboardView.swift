import SwiftUI

struct MissionDashboardView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var control: MissionControl

    init(store: PetStore) {
        self.store = store
        _control = ObservedObject(wrappedValue: store.mission)
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            GlassBackground()
            VStack(alignment: .leading, spacing: 18) {
                header
                statusRail
                PriorityCard(insight: priority, action: action(for: priority))
                metrics
                HStack(alignment: .top, spacing: 10) {
                    GitCard(health: control.git, refresh: control.refreshGit)
                    quickActions
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("señales activas")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Pal.cream.opacity(0.58))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(keyInsights) { insight in
                        InsightTile(insight: insight, action: action(for: insight))
                        }
                    }
                }
                timeline
                footer
            }
            .padding(22)
        }
        .frame(minWidth: 680, minHeight: 650)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tablero operativo de claude pet")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("mission control")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Pal.cream)
                Text("lectura local de la sesión actual")
                    .font(.subheadline)
                    .foregroundStyle(Pal.cream.opacity(0.58))
            }
            Spacer()
            Button("actualizar git", systemImage: "arrow.clockwise") { control.refreshGit() }
                .buttonStyle(.bordered)
        }
    }

    private var statusRail: some View {
        HStack(spacing: 10) {
            AgentStatus(name: "claude", state: store.state, active: store.claudePresent, tint: Pal.body)
            AgentStatus(name: "codex", state: store.codexState, active: store.codexPresent, tint: Color(hex: 0x96EBFF))
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Label(control.git.label, systemImage: control.git.conflicts > 0 ? "exclamationmark.triangle.fill" : "point.3.connected.trianglepath.dotted")
                Label(store.foregroundAppName.isEmpty ? "sin app activa" : store.foregroundAppName, systemImage: "rectangle.inset.filled")
            }
            .font(.caption)
            .foregroundStyle(control.git.conflicts > 0 ? Pal.body : Pal.cream.opacity(0.72))
            .lineLimit(1)
        }
        .padding(12)
        .background(Pal.charcoal.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08)) }
    }

    private var priority: MissionInsight {
        control.insights.first { $0.tone == .danger }
            ?? control.insights.first { $0.id == "approval" && $0.tone == .caution }
            ?? control.insights.first { $0.id == "radar" && $0.tone == .caution }
            ?? control.insights.first { $0.id == "handoff" && $0.tone == .active }
            ?? control.insights.first { $0.id == "checkpoint" }
            ?? control.insights[0]
    }

    private var keyInsights: [MissionInsight] {
        control.insights.filter { ["radar", "approval", "handoff", "tools", "focus", "boundary"].contains($0.id) }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricCell(title: "sesión", value: control.activeSince == nil ? "en pausa" : "\(Int(control.elapsed / 60)) min", symbol: "timer")
            MetricCell(title: "herramientas", value: "\(control.toolCalls)", symbol: "hammer")
            MetricCell(title: "cambios", value: control.git.available ? "\(control.git.affected)" : "—", symbol: "point.3.connected.trianglepath.dotted")
            MetricCell(title: "frente", value: store.foregroundAppName.isEmpty ? "—" : store.foregroundAppName, symbol: "rectangle.inset.filled")
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("acciones rápidas")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Pal.cream.opacity(0.58))
            Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                AppController.shared.toggleWindow()
            }
            Button("abrir diff", systemImage: "arrow.left.arrow.right") { control.perform(.openDiff) }
            Toggle("burbuja", isOn: $store.showBubble)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)) }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("traza reciente")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Pal.cream.opacity(0.58))
                Spacer()
                Text("últimos \(min(6, control.timeline.count)) eventos")
                    .font(.caption)
                    .foregroundStyle(Pal.cream.opacity(0.38))
            }
            if control.timeline.isEmpty {
                Label("aún no hay actividad · aparecerá al iniciar Claude o Codex", systemImage: "clock")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(Pal.cream.opacity(0.58))
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    ForEach(control.timeline.prefix(6)) { event in TimelineChip(event: event) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("sin red · sin telemetría", systemImage: "lock.fill")
            Spacer()
            if control.recovery != nil {
                Button("abrir recuperación", systemImage: "arrow.left.arrow.right") { control.perform(.openDiff) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.caption)
        .foregroundStyle(Pal.cream.opacity(0.55))
    }

    private func action(for insight: MissionInsight) -> MissionAction? {
        switch insight.id {
        case "recovery": return control.recovery == nil ? nil : .openDiff
        case "conflicts", "checkpoint", "staging", "untracked": return .refreshGit
        default: return nil
        }
    }
}

private struct MetricCell: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Pal.cream.opacity(0.55))
            Text(value).font(.headline).foregroundStyle(Pal.cream).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Pal.charcoal.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PriorityCard: View {
    let insight: MissionInsight
    let action: MissionAction?

    private var tint: Color {
        switch insight.tone { case .calm: Color(hex: 0x96EBFF); case .active: Pal.cream; case .caution: Pal.body; case .danger: Color(hex: 0xFF8A7A) }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: insight.tone == .danger ? "exclamationmark.octagon.fill" : "sparkles")
                .font(.title2).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.headline).foregroundStyle(Pal.cream)
                Text(insight.detail).font(.subheadline).foregroundStyle(Pal.cream.opacity(0.65))
            }
            Spacer(minLength: 0)
            if let action {
                Button(action.title, systemImage: "arrow.right") { MissionActionRunner.run(action) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(16)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.32)) }
    }
}

private struct GitCard: View {
    let health: GitHealth
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(health.branch.isEmpty ? "git" : health.branch, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline).foregroundStyle(Pal.cream)
                Spacer()
                Button("actualizar", systemImage: "arrow.clockwise", action: refresh).labelStyle(.iconOnly).buttonStyle(.plain)
            }
            HStack(spacing: 5) {
                GitCount(value: health.changed, title: "mod.", tint: Pal.body)
                GitCount(value: health.staged, title: "staged", tint: Color(hex: 0x96EBFF))
                GitCount(value: health.untracked, title: "nuevos", tint: Pal.cream)
                GitCount(value: health.conflicts, title: "conf.", tint: Color(hex: 0xFF8A7A))
            }
            Text(health.label).font(.caption).foregroundStyle(Pal.cream.opacity(0.58)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Pal.charcoal.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)) }
    }
}

private struct GitCount: View {
    let value: Int
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) { Text("\(value)").bold(); Text(title).font(.caption) }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .foregroundStyle(value > 0 ? tint : Pal.cream.opacity(0.36))
            .background(tint.opacity(value > 0 ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimelineChip: View {
    let event: MissionEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.agent).font(.caption.weight(.semibold))
            Text(event.state.label.lowercased()).font(.caption).foregroundStyle(Pal.cream.opacity(0.64))
            Text(event.at, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(Pal.cream.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AgentStatus: View {
    let name: String
    let state: PetState
    let active: Bool
    let tint: Color

    var body: some View {
        Label {
            Text("\(name) · \(active ? state.label.lowercased() : "en reposo")")
        } icon: {
            Circle().fill(active ? tint : Pal.cream.opacity(0.25)).frame(width: 8, height: 8)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Pal.cream)
    }
}

private struct InsightTile: View {
    let insight: MissionInsight
    let action: MissionAction?

    private var symbol: String {
        switch insight.tone {
        case .calm: return "checkmark"
        case .active: return "bolt"
        case .caution: return "exclamationmark"
        case .danger: return "xmark"
        }
    }

    private var tint: Color {
        switch insight.tone {
        case .calm: return Color(hex: 0x96EBFF)
        case .active: return Pal.cream
        case .caution: return Pal.body
        case .danger: return Color(hex: 0xFF8A7A)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(insight.title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if let action {
                    Button(action.title, systemImage: "arrow.right") { MissionActionRunner.run(action) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                }
            }
            Text(insight.detail)
                .font(.caption)
                .foregroundStyle(Pal.cream.opacity(0.65))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.15)) }
    }
}

@MainActor
private enum MissionActionRunner {
    static func run(_ action: MissionAction) {
        PetStore.shared.mission.perform(action)
    }
}
