import SwiftUI
import AppKit

/// Vista abierta de la isla, compacta y ordenada: encabezado, tres pasos y una fila de chips.
/// Todo lo secundario vive en el menu "mas" para que nada se amontone.
struct IslandOverviewView: View {
    @ObservedObject var store: PetStore
    @Binding var agentTab: IslandAgentTab

    private var isClaude: Bool { agentTab == .claude }
    private var state: PetState { isClaude ? store.state : store.codexState }
    private var duration: String { isClaude ? store.stateDurationLabel : store.codexStateDurationLabel }
    private var reading: ContextReading? { isClaude ? store.contextReading : store.codexContextReading }
    private var steps: [IslandStep] { Array(IslandSteps.forAgent(agentTab, in: store.recentIslandSteps).suffix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loop = store.loopAlert { loopBanner(loop) }
            header
            stepList
            Spacer(minLength: 0)
            actions
            chips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: encabezado

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.terminalProject.isEmpty ? "sin proyecto" : store.terminalProject).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(isClaude ? "claude code" : "codex").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                }
                Text(state == .idle ? "en reposo" : "\(state.label.lowercased()) · \(duration)")
                    .font(.system(size: 11)).foregroundColor(IslandOverviewView.stateColor(state))
            }
            Spacer(minLength: 8)
            if store.codexPresent { agentSwitch }
            moreMenu
        }
    }

    private var agentSwitch: some View {
        HStack(spacing: 2) {
            ForEach(IslandAgentTabs.available(codex: true), id: \.self) { tab in
                Button(tab.rawValue) { agentTab = tab }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium)).foregroundColor(agentTab == tab ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(agentTab == tab ? Color.white : Color.white.opacity(0.08)))
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("agente")
    }

    // MARK: pasos

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 3) {
            if steps.isEmpty { emptyState }
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                let latest = index == steps.count - 1
                HStack(spacing: 6) {
                    Text(latest ? "›" : "✓").font(.system(size: 11, weight: .bold)).foregroundColor(latest ? Color(hex: 0xE0824F) : .white.opacity(0.35)).frame(width: 10)
                    Text(step.label).font(.system(size: 12, weight: latest ? .medium : .regular)).foregroundColor(.white.opacity(latest ? 0.95 : 0.5)).lineLimit(1)
                    if !step.delta.isEmpty { Text(step.delta).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4)) }
                    Spacer(minLength: 4)
                    Text(step.ageLabel(now: Date())).font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                }
                .contextMenu { Button("copiar paso", systemImage: "doc.on.clipboard") { copy(step.label) } }
                .onTapGesture { if latest { store.openLatestDiff() } }
            }
        }
    }

    // MARK: acciones visibles

    /// Las acciones de uso diario, con nombre y a la vista; lo demas esta en el menu "mas".
    private var actions: some View {
        HStack(spacing: 6) {
            if CommiteroLauncher.available(), !store.mission.workspace.isEmpty, store.mission.git.affected > 0 {
                actionButton("commitear", symbol: "arrow.triangle.branch", prominent: true) { CommiteroLauncher.launch(workspace: store.mission.workspace) }
            }
            if store.terminalTargetAvailable { actionButton("terminal", symbol: "terminal") { store.focusTerminal() } }
            if !store.mission.changes.isEmpty { actionButton("cambios", symbol: "plus.forwardslash.minus") { store.openLatestDiff() } }
            actionButton("resumen", symbol: "doc.on.clipboard") { copy("\(store.sessionSummary) · \(agentTab.rawValue) · \(state.label.lowercased())") }
            actionButton("mission control", symbol: "square.grid.2x2") { AppController.shared.showMissionDashboard() }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(prominent ? .white : .white.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(prominent ? Color(hex: 0x2966ED) : Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    /// Sin actividad reciente: lo de hoy en vez de un espacio en blanco.
    private var emptyState: some View {
        let t = store.today, r = store.weeklyRecap
        return VStack(alignment: .leading, spacing: 6) {
            Text(isClaude ? (store.claudeBubbleActivity?.title ?? "sin actividad reciente") : "línea publicada por codex")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
            HStack(spacing: 14) {
                stat("\(t.sessions)", "tareas hoy")
                stat("\(t.tools)", "herramientas")
                stat("\(t.permissions)", "permisos")
                stat(r.streak == 1 ? "1 día" : "\(r.streak) días", "de racha")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: chips

    private var chips: some View {
        HStack(spacing: 6) {
            if let reading { chip(contextText(reading), color: IslandOverviewView.pressureColor(reading.pressure), help: reading.summary) { copy(reading.summary) } }
            if store.mission.git.available, isClaude {
                chip("⑂ " + (store.mission.git.branch.isEmpty ? "sin rama" : store.mission.git.branch), color: .white.opacity(0.6), help: "copiar rama") { copy(store.mission.git.branch) }
                let git = store.mission.git
                if git.affected > 0 || git.conflicts > 0 {
                    chip("\(git.affected) cambios" + (git.conflicts > 0 ? " · \(git.conflicts) conflictos" : ""), color: git.conflicts > 0 ? Color(hex: 0xD85C5C) : .white.opacity(0.6), help: "abrir mission control") { AppController.shared.showMissionDashboard() }
                }
            }
            Spacer(minLength: 0)
            if store.terminalTargetAvailable { chip("terminal ↗", color: Color(hex: 0xE0824F), help: "saltar a la terminal") { store.focusTerminal() } }
        }
    }

    private func contextText(_ r: ContextReading) -> String { "ctx \(100 - r.remainingPercent)%" }

    private func chip(_ text: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(color).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: menu "mas": todo lo secundario

    private var moreMenu: some View {
        Menu {
            Button("copiar resumen de sesión", systemImage: "doc.on.clipboard") {
                copy("\(store.sessionSummary) · \(agentTab.rawValue) · \(state.label.lowercased())")
            }
            Button("copiar actividad reciente", systemImage: "list.bullet") {
                copy(IslandSteps.forAgent(agentTab, in: store.recentIslandSteps).map(\.label).joined(separator: "\n"))
            }
            if let reading {
                Button("copiar contexto", systemImage: "gauge") { copy(reading.summary) }
                Button("copiar modelo", systemImage: "cpu") { copy(reading.model) }
            }
            if store.mission.git.available {
                Button("copiar rama", systemImage: "arrow.triangle.branch") { copy(store.mission.git.branch) }
                Button("copiar estado git", systemImage: "doc.on.doc") {
                    let g = store.mission.git
                    copy("\(g.affected) cambios · \(g.staged) staged · \(g.conflicts) conflictos")
                }
            }
            Divider()
            if !store.mission.changes.isEmpty { Button("abrir cambios", systemImage: "arrow.up.right") { store.openLatestDiff() } }
            if !store.mission.workspace.isEmpty { Button("abrir carpeta del proyecto", systemImage: "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: store.mission.workspace)) } }
            Button("actualizar telemetría", systemImage: "arrow.clockwise") { store.refreshTelemetryNow() }
            Divider()
            Button("mission control", systemImage: "square.grid.2x2") { AppController.shared.showMissionDashboard() }
            Button("relevo de sesión", systemImage: "arrow.left.arrow.right") { AppController.shared.showRelay() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.7))
                .frame(width: 24, height: 22).background(Circle().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("más acciones").accessibilityLabel("más acciones")
    }

    private func loopBanner(_ loop: LoopAlert) -> some View {
        HStack(spacing: 8) {
            Label(loop.title, systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: 0xE7B45B)).lineLimit(1)
            Spacer(minLength: 0)
            Button("copiar") { copy("\(loop.title)\n\(loop.summary)") }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
            Button("descartar") { store.dismissLoopAlert() }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xE7B45B).opacity(0.12)))
    }

    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

    static func stateColor(_ s: PetState) -> Color {
        switch s {
        case .waiting: return Color(hex: 0xE7B45B)
        case .error: return Color(hex: 0xD85C5C)
        case .done: return Color(hex: 0x6CCB8A)
        case .tool, .thinking, .starting: return Color(hex: 0x7C93F0)
        case .idle: return .white.opacity(0.5)
        }
    }
    static func pressureColor(_ p: ContextPressure) -> Color {
        switch p { case .normal: return .white.opacity(0.6); case .caution: return Color(hex: 0xE7B45B); case .critical: return Color(hex: 0xD85C5C) }
    }
}
