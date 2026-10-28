import SwiftUI
import AppKit

/// Vista abierta de la isla: una escena con la mascota grande a la izquierda y, a la derecha, lo que dice,
/// lo que hizo, lo que puedes hacer y el estado del proyecto. Lo secundario vive en el menu "mas".
struct IslandOverviewView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    @Binding var agentTab: IslandAgentTab
    @ObservedObject private var music: MusicController
    @ObservedObject private var plugins: PluginHost
    @State private var shown = false
    @State private var showMusic = false

    init(store: PetStore, model: IslandModel, agentTab: Binding<IslandAgentTab>) {
        self.store = store
        self.model = model
        _agentTab = agentTab
        _music = ObservedObject(wrappedValue: store.music)
        _plugins = ObservedObject(wrappedValue: store.plugins)
    }

    private var isClaude: Bool { agentTab == .claude }
    private var state: PetState { isClaude ? store.state : store.codexState }
    private var duration: String { isClaude ? store.stateDurationLabel : store.codexStateDurationLabel }
    private var reading: ContextReading? { isClaude ? store.contextReading : store.codexContextReading }
    private var steps: [IslandStep] { Array(IslandSteps.forAgent(agentTab, in: store.recentIslandSteps).suffix(3)) }
    private var animated: Bool { store.animationsEnabled && !store.reduceMotion && !IslandSnapshot.isRendering }

    private var headline: String {
        let last = steps.last
        return IslandHeadline.make(state: state, tool: last?.tool ?? "", target: last?.target ?? "", idleSeconds: model.idleSeconds)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IslandStage(store: store, model: model, agent: agentTab, statusColor: Self.stateColor(state) == .white.opacity(0.5) ? .clear : Self.stateColor(state))
                .id(agentTab)
                .transition(animated ? .asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(x: -16)), removal: .opacity) : .identity)
                .reveal(0, shown, animated: animated)
            VStack(alignment: .leading, spacing: 8) {
                if let loop = store.loopAlert { loopBanner(loop).reveal(0, shown, animated: animated) }
                if let t = plugins.toast { pluginToast(t) }
                header.reveal(1, shown, animated: animated)
                if showMusic && music.nowPlaying != nil {
                    Spacer(minLength: 0)
                    MusicPanelView(music: music, accent: store.musicAccent.map { Color(hex: $0) } ?? .white).transition(.opacity)
                    Spacer(minLength: 0)
                } else {
                    speech.reveal(2, shown, animated: animated)
                    stepList.reveal(3, shown, animated: animated)
                    Spacer(minLength: 0)
                    actions.reveal(4, shown, animated: animated)
                    chips.reveal(5, shown, animated: animated)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { shown = true }
        .onDisappear { shown = false; showMusic = false; music.watching = false }
        .onChange(of: showMusic) { music.watching = $0 }
        .onChange(of: music.nowPlaying == nil) { gone in if gone { showMusic = false } }
    }

    // MARK: encabezado y frase

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.terminalProject.isEmpty ? "sin proyecto" : store.terminalProject).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text(isClaude ? "claude code" : "codex").font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            if store.musicPlayer, music.nowPlaying != nil { musicButton }
            if store.codexPresent { agentSwitch.fixedSize() }
            moreMenu.layoutPriority(2)
        }
    }

    /// Aviso que pide un plugin; desaparece solo a los pocos segundos.
    private func pluginToast(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "puzzlepiece.extension").font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.9)).padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xE0824F).opacity(0.35), Color(hex: 0x5270E8).opacity(0.4)], startPoint: .leading, endPoint: .trailing)))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel("aviso de plugin: \(text)")
    }

    private var musicButton: some View {
        Button { if animated { withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { showMusic.toggle() } } else { showMusic.toggle() } } label: {
            Image(systemName: music.isPlaying ? "music.note" : "pause.fill").font(.system(size: 11, weight: .semibold))
                .foregroundColor(showMusic ? .black : .white.opacity(0.85))
                .frame(width: 26, height: 26).background(Circle().fill(showMusic ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain).help(showMusic ? "volver a la actividad" : "reproductor")
        .accessibilityLabel("reproductor de música")
    }

    private var agentSwitch: some View {
        HStack(spacing: 4) {
            ForEach(IslandAgentTabs.available(codex: true), id: \.self) { tab in
                AgentAvatarTab(tab: tab, selected: agentTab == tab, state: tab == .claude ? store.state : store.codexState, codexSkin: store.codexSkin) {
                    if animated { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { agentTab = tab } } else { agentTab = tab }
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("agente")
    }

    /// Lo que dice la mascota, escrito letra a letra, y debajo el estado con su duracion.
    private var speech: some View {
        VStack(alignment: .leading, spacing: 3) {
            TypewriterText(text: headline, reduceMotion: !animated)
                .font(.system(size: 19, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Text(state == .idle ? "en reposo" : "\(state.label.lowercased()) · \(duration)")
                .font(.system(size: 11)).foregroundColor(Self.stateColor(state))
        }
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
                // el paso nuevo sube desde abajo y los viejos se desvanecen
                .transition(animated ? .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity) : .identity)
            }
        }
        .animation(animated ? .spring(response: 0.4, dampingFraction: 0.85) : nil, value: steps.map(\.id))
    }

    /// Sin actividad reciente: lo de hoy en vez de un espacio en blanco.
    private var emptyState: some View {
        let t = store.today, r = store.weeklyRecap
        return HStack(spacing: 16) {
            stat("\(t.sessions)", "tareas hoy")
            stat("\(t.tools)", "herramientas")
            stat("\(t.permissions)", "permisos")
            HStack(spacing: 4) {
                stat(r.streak == 1 ? "1 día" : "\(r.streak) días", "de racha")
                if animated { StreakFireView(streak: r.streak) }
            }
        }
        .padding(.top, 2)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundColor(.white).contentTransition(.numericText()).animation(animated ? .spring(response: 0.5, dampingFraction: 0.8) : nil, value: value)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: acciones visibles

    private var actions: some View {
        QuickDock(store: store, music: music, plugins: plugins) { "\(store.sessionSummary) · \(agentTab.rawValue) · \(state.label.lowercased())" }
    }

    private func actionButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        ActionPill(title: title, symbol: symbol, prominent: prominent, action: action)
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
            Button("copiar resumen de sesión", systemImage: "doc.on.clipboard") { copy("\(store.sessionSummary) · \(agentTab.rawValue) · \(state.label.lowercased())") }
            Button("copiar actividad reciente", systemImage: "list.bullet") { copy(IslandSteps.forAgent(agentTab, in: store.recentIslandSteps).map(\.label).joined(separator: "\n")) }
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
            if !store.mission.workspace.isEmpty { Button("abrir carpeta del proyecto", systemImage: "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: store.mission.workspace)) } }
            Button("actualizar telemetría", systemImage: "arrow.clockwise") { store.refreshTelemetryNow() }
            let pluginActions = plugins.actions(place: "island")
            if !pluginActions.isEmpty {
                Divider()
                ForEach(pluginActions, id: \.action.id) { item in
                    Button(item.action.title, systemImage: item.action.symbol ?? "puzzlepiece.extension") { plugins.run(item.plugin.id, item.action, name: item.plugin.manifest.name) }
                }
            }
            Divider()
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

/// Boton de accion con vida: sube un poco al pasar el cursor y se hunde al pulsar.
struct ActionPill: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(prominent ? .white : .white.opacity(0.88))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(prominent ? Color(hex: 0x2966ED) : Color.white.opacity(hover ? 0.17 : 0.09)))
        }
        .buttonStyle(ActionPillStyle())
        .onHover { hover = $0 }
        .offset(y: hover ? -1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
        .help(title).accessibilityLabel(title)
    }
}

private struct ActionPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1).animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
