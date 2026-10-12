import SwiftUI

struct MissionDashboardView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var control: MissionControl

    init(store: PetStore) {
        self.store = store
        _control = ObservedObject(wrappedValue: store.mission)
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            GlassBackground()
            VStack(alignment: .leading, spacing: 18) {
                header
                statusRail
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(control.insights) { insight in
                        InsightTile(insight: insight, action: action(for: insight))
                    }
                }
                footer
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 530)
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
