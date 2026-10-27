import SwiftUI
import AppKit
import Combine

/// Isla pegada al notch (o a una barra arriba si no hay notch). Reemplaza a las mascotas flotantes.
@MainActor
final class IslandController {
    private let store: PetStore
    private let model = IslandModel()
    private var panel: PetPanel?
    private var timer: Timer?
    private var machine = IslandMachine()
    private var metrics: ScreenMetrics?
    private var clicked = false
    private var lastClaude: PetState = .idle
    private var lastCodex: PetState = .idle
    private var finishedAt: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var timerInterval: TimeInterval = IslandPollingPolicy.activeInterval

    init(store: PetStore) { self.store = store }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let p = PetPanel(contentRect: NSRect(origin: .zero, size: NotchGeometry.panelSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = FirstMouseHostingView(rootView: IslandView(model: model, store: store))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // por encima de la barra de menus y de las apps en pantalla completa
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        panel = p
        model.onPetClick = { [weak self] in self?.clicked = true }
        model.pokes = []; model.hopStart = nil
        model.greetUntil = ProcessInfo.processInfo.systemUptime + 1.4
        relocate()
        p.orderFrontRegardless()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.relocate() }
        })
        scheduleTimer(interval: IslandPollingPolicy.activeInterval)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        panel?.orderOut(nil); panel = nil
        machine = IslandMachine()
    }

    private static func metrics(of s: NSScreen) -> ScreenMetrics {
        ScreenMetrics(frame: s.frame, safeTop: s.safeAreaInsets.top,
                      auxLeft: s.auxiliaryTopLeftArea?.width ?? 0, auxRight: s.auxiliaryTopRightArea?.width ?? 0)
    }

    /// Recalcula la pantalla elegida cada vez que se conecta, desconecta o cambia una pantalla.
    private func relocate() {
        guard let m = NotchGeometry.pick(NSScreen.screens.map(Self.metrics), preference: store.islandScreenPreference, mouse: NSEvent.mouseLocation) else { return }
        metrics = m
        model.hasNotch = NotchGeometry.hasNotch(m)
        panel?.setFrame(NotchGeometry.panelFrame(m), display: false)
    }

    private func tasksRunning() -> Bool {
        [store.state, store.codexState].contains { $0 != .idle && $0 != .done }
    }

    private func tick() {
        guard let m = metrics, let panel else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation

        // transiciones de estado: terminar de trabajar dispara la vista de fin
        let c = store.state, x = store.codexState
        let doneNow = (c == .done && lastClaude != .done) || (x == .done && lastCodex != .done)
        if doneNow { finishedAt = now; model.hopStart = now }
        lastClaude = c; lastCodex = x
        let finishedPending = finishedAt.map { now - $0 < 0.1 } ?? false

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let asking = !store.permissionAsks.isEmpty || !store.questionAsks.isEmpty
        let eh = asking ? NotchGeometry.permissionHeight : NotchGeometry.expandedHeight
        let input = IslandInput(now: now,
                                overNotch: NotchGeometry.overNotch(mouse, metrics: m),
                                overIsland: NotchGeometry.contains(mouse, mode: machine.mode, metrics: m, expandedHeight: eh),
                                tasksRunning: tasksRunning(),
                                alertPending: asking || c == .waiting || c == .error || x == .waiting || x == .error,
                                finishedPending: finishedPending,
                                idleSeconds: idle,
                                clickedPet: clicked)
        clicked = false
        let mode = machine.tick(input)
        if model.hover != input.overIsland { model.hover = input.overIsland }
        let desiredInterval = IslandPollingPolicy.interval(hidden: mode == .hidden, tasksRunning: tasksRunning(), attention: asking)
        if desiredInterval != timerInterval { scheduleTimer(interval: desiredInterval) }

        let size = NotchGeometry.islandSize(mode, metrics: m, expandedHeight: eh)
        if model.mode != mode {
            if mode == .peek && model.mode == .hidden { model.greetUntil = now + 1.4 }
            model.mode = mode
        }
        if model.reason != machine.reason { model.reason = machine.reason }
        if model.countdown != machine.countdown { model.countdown = machine.countdown }
        if model.size != size { model.size = size }

        // los ojos siguen al cursor por toda la pantalla
        let f = NotchGeometry.islandFrame(mode, metrics: m, expandedHeight: eh)
        let cursorGaze = CGPoint(x: max(-1, min(1, (mouse.x - f.midX) / 400)), y: max(-1, min(1, (mouse.y - f.midY) / 300)))
        // la tarjeta aparece a la izquierda de la mascota en la vista abierta.
        model.gaze = asking && mode == .expanded ? CGPoint(x: -0.8, y: 0) : cursorGaze

        // clics traversantes: la ventana solo recibe el raton sobre la forma visible de la isla
        let interactive = mode != .hidden && NotchGeometry.contains(mouse, mode: mode, metrics: m, expandedHeight: eh)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timerInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var store: PetStore
    @State private var agentTab: IslandAgentTab = .claude
    @State private var questionSelections: [Int: Set<Int>] = [:]
    @State private var questionIndex = 0
    @State private var questionFreeText = ""

    private var transition: Animation { store.reduceMotion ? IslandMotion.reduced : IslandMotion.spring }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island.frame(width: model.size.width, height: model.size.height)
        }
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
        .animation(transition, value: model.size)
        .animation(transition, value: model.mode)
    }

    private var island: some View {
        ZStack(alignment: .topLeading) {
            IslandShape(radius: NotchGeometry.cornerRadius(model.mode))
                .fill(Color.black)
                .opacity(model.mode == .hidden && model.hasNotch ? 0 : 1)
            if model.mode != .hidden { content }
            if let c = model.countdown {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 160 * c, height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            }
        }
        .clipShape(IslandShape(radius: NotchGeometry.cornerRadius(model.mode)))
    }

    @ViewBuilder private var content: some View {
        let compact = model.mode != .expanded
        let side: CGFloat = compact ? 20 : 56
        HStack(alignment: .center, spacing: compact ? 6 : 16) {
            PetFace(store: store, model: model)
                .frame(width: side, height: side)
                .overlay(Circle().stroke(statusColor, lineWidth: compact ? 1.5 : 2.5).opacity(store.state == .idle ? 0 : 0.9))
                .contentShape(Rectangle())
                .onTapGesture { model.poke() }
                .accessibilityLabel("claude: \(store.state.label.lowercased()), \(store.stateDurationLabel)")
                .accessibilityHint("pulsa para abrir el detalle")
            if compact && store.state != .idle {
                Image(systemName: statusSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(statusColor)
                    .accessibilityHidden(true)
                    .help("estado claude: \(store.state.label.lowercased())")
            }
            if compact, let reading = store.contextReading {
                IslandContextMeter(reading: reading, label: "contexto", onOpen: { model.poke() })
                if reading.pressure == .critical { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundColor(contextColor(reading.pressure)).accessibilityHidden(true).onTapGesture { model.poke() }.contextMenu { Button("copiar contexto", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.summary, forType: .string) } } }
            }
            if compact, let badge = store.attentionBadgeLabel {
                Button { model.poke() } label: {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: 0xF0A24B)))
                }.buttonStyle(.plain).accessibilityLabel(store.attentionLabel)
                    .help("\(store.attentionLabel) · pulsa para abrir")
            }
            if compact, let alert = store.safetyAlert {
                Button { model.poke() } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: 0xD85C5C))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("alerta de seguridad: \(alert.title)")
                .help("\(alert.title) · pulsa para abrir el detalle")
                .contextMenu {
                    Button("copiar alerta", systemImage: "doc.on.clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(alert.title) · \(alert.subtitle)", forType: .string)
                    }
                }
            }
            if !compact { if let ask = store.permissionAsks.first { PermissionCardView(store: store, ask: ask) } else if let ask = store.questionAsks.first { QuestionCardView(store: store, ask: ask, selections: $questionSelections, index: $questionIndex, freeText: $questionFreeText, commit: commitQuestion) } else { details } }
            Spacer(minLength: 0)
            if compact && store.codexPresent {
                if let reading = store.codexContextReading {
                    IslandContextMeter(reading: reading, label: "contexto codex", onOpen: { model.poke() })
                    if reading.pressure == .critical { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundColor(contextColor(reading.pressure)).accessibilityHidden(true).onTapGesture { model.poke() }.contextMenu { Button("copiar contexto codex", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.summary, forType: .string) } } }
                }
                CodexMini(store: store, model: model, greet: false).frame(width: 22, height: 24)
                    .accessibilityLabel("codex: \(store.codexState.label.lowercased()), \(store.codexStateDurationLabel)")
                    .accessibilityHint("adaptador de codex; pulsa para abrir el detalle")
                if store.codexState != .idle {
                    Image(systemName: codexStatusSymbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(codexColor)
                        .accessibilityHidden(true)
                        .help("estado codex: \(store.codexState.label.lowercased())")
                }
            }
        }
        .padding(.leading, compact ? 8 : 24)
        .padding(.trailing, compact ? 10 : 24)
        .padding(.top, compact ? 0 : 38)
        .frame(maxHeight: .infinity, alignment: compact ? .center : .top)
        .transition(.opacity)
    }

    private func commitQuestion(_ ask: QuestionAsk, index: Int, selected: [Int]) {
        questionSelections[index] = Set(selected)
        guard index + 1 >= ask.questions.count else { questionIndex = index + 1; return }
        let answers = Dictionary(uniqueKeysWithValues: ask.questions.enumerated().map { i, item in
            let labels = (questionSelections[i] ?? []).sorted().compactMap { index -> String? in
                guard item.options.indices.contains(index) else { return nil }
                return item.options[index].label.lowercased().contains("otra") && !questionFreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? questionFreeText.trimmingCharacters(in: .whitespacesAndNewlines) : item.options[index].label
            }.joined(separator: ", ")
            return (item.question, labels)
        })
        store.answerQuestion(ask.id, answers)
        questionSelections.removeAll(); questionIndex = 0; questionFreeText = ""
    }

    private var codexColor: Color { store.codexState == .idle ? Color.white.opacity(0.35) : Color(hex: 0x5270E8) }

    private var statusColor: Color {
        switch store.state {
        case .waiting: return Color(hex: 0xE7B45B)
        case .error: return Color(hex: 0xD85C5C)
        case .done: return Color(hex: 0x6CCB8A)
        case .tool, .thinking, .starting: return Color(hex: 0x5270E8)
        case .idle: return .clear
        }
    }

    private var statusSymbol: String {
        switch store.state {
        case .thinking: return "ellipsis"
        case .tool, .starting: return "hammer"
        case .waiting: return "hand.raised"
        case .error: return "exclamationmark.triangle"
        case .done: return "checkmark"
        case .idle: return "circle"
        }
    }

    private var codexStatusSymbol: String {
        switch store.codexState {
        case .thinking: return "ellipsis"
        case .tool, .starting: return "hammer"
        case .waiting: return "hand.raised"
        case .error: return "exclamationmark.triangle"
        case .done: return "checkmark"
        case .idle: return "circle"
        }
    }

    private func contextColor(_ pressure: ContextPressure) -> Color {
        switch pressure {
        case .normal: return Color(hex: 0x5270E8)
        case .caution: return Color(hex: 0xE7B45B)
        case .critical: return Color(hex: 0xD85C5C)
        }
    }

    private func durationColor(_ seconds: Int) -> Color {
        if seconds >= 300 { return Color(hex: 0xD85C5C) }
        if seconds >= 60 { return Color(hex: 0xE7B45B) }
        return .white.opacity(0.5)
    }

    private var details: some View {
        let agentSteps = IslandSteps.forAgent(agentTab, in: store.recentIslandSteps)
        return VStack(alignment: .leading, spacing: 6) {
            if store.contextReading != nil || !store.mission.changes.isEmpty {
                HStack(spacing: 8) {
                    if let reading = store.contextReading {
                        ContextRingView(reading: reading).scaleEffect(0.42).frame(width: 48, height: 48)
                            .help(reading.summary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.model.isEmpty ? "modelo no disponible" : reading.model).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                            Text(store.contextPressureLabel).font(.system(size: 9, design: .monospaced)).foregroundColor(contextColor(reading.pressure))
                            Button("copiar modelo") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.model, forType: .string)
                            }.buttonStyle(.plain).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                            Button("copiar contexto") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.summary, forType: .string)
                            }.buttonStyle(.plain).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                        }
                    }
                    if !store.mission.changes.isEmpty { FileOrbitView(files: store.mission.changes).scaleEffect(0.52).frame(width: 66, height: 66) }
                }
                if !store.contextHistory.isEmpty {
                    ContextTrendView(samples: store.contextHistory)
                        .frame(height: 30)
                }
                HStack(spacing: 8) {
                    Button("actualizar", systemImage: "arrow.clockwise") { store.refreshTelemetryNow() }
                        .buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    if store.contextReading != nil {
                        Button("copiar contexto", systemImage: "doc.on.clipboard") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.contextReading?.summary ?? store.contextLabel, forType: .string)
                        }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                    }
                    if !store.mission.changes.isEmpty {
                        Button("abrir cambios", systemImage: "arrow.up.right") { store.openLatestDiff() }
                            .buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: 0xE0824F))
                    }
                }
            }
            if store.codexPresent { Picker("agente", selection: $agentTab) { ForEach(IslandAgentTabs.available(codex: true), id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of: store.codexPresent) { agentTab = IslandAgentTabs.keep(agentTab, codex: $0) } }
            if agentTab == .claude {
                Text("claude · \(store.state.label.lowercased())").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                    .contextMenu { Button("copiar estado", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("claude · \(store.state.label.lowercased()) · \(store.stateDurationLabel)", forType: .string) } }
                if store.state != .idle { Text("activo desde hace \(store.stateDurationLabel)").font(.system(size: 10, design: .monospaced)).foregroundColor(durationColor(store.stateDurationSeconds)) }
                if let a = store.claudeBubbleActivity { Text(a.title).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85)).lineLimit(1); if !a.subtitle.isEmpty { Text(a.subtitle).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.55)).lineLimit(1) } }
            } else {
                if let reading = store.codexContextReading {
                    HStack(spacing: 8) {
                        ContextRingView(reading: reading).scaleEffect(0.42).frame(width: 48, height: 48)
                            .help(reading.summary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.model.isEmpty ? "modelo no disponible" : reading.model).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                            Text(reading.pressureLabel).font(.system(size: 9, design: .monospaced)).foregroundColor(contextColor(reading.pressure))
                            Button("copiar modelo") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.model, forType: .string)
                            }.buttonStyle(.plain).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                        }
                    }
                    if !store.codexContextHistory.isEmpty {
                        ContextTrendView(samples: store.codexContextHistory, agent: "codex")
                            .frame(height: 30)
                    }
                }
                Text("codex · \(store.codexState.label.lowercased())").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(codexColor)
                    .contextMenu { Button("copiar estado", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("codex · \(store.codexState.label.lowercased()) · \(store.codexStateDurationLabel)", forType: .string) } }
                if store.codexState != .idle { Text("activo desde hace \(store.codexStateDurationLabel)").font(.system(size: 10, design: .monospaced)).foregroundColor(durationColor(store.codexStateDurationSeconds)) }
                Text("línea publicada por codex").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            Button("copiar resumen de sesión", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(store.sessionSummary) · \(agentTab.rawValue) · \(agentTab == .claude ? store.state.label.lowercased() : store.codexState.label.lowercased())", forType: .string)
            }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            if !store.mission.workspace.isEmpty {
                Button("abrir carpeta del proyecto", systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: store.mission.workspace))
                }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            }
            if store.mission.git.available {
                Button("rama: \(store.mission.git.branch.isEmpty ? "sin rama" : store.mission.git.branch)", systemImage: "arrow.triangle.branch") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.mission.git.branch, forType: .string)
                }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Text("\(store.mission.git.affected) cambios · \(store.mission.git.staged) staged · \(store.mission.git.conflicts) conflictos")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(store.mission.git.conflicts > 0 ? Color(hex: 0xD85C5C) : .white.opacity(0.5))
                    .onTapGesture { AppController.shared.showMissionDashboard() }
                    .help("abrir mission control: cambios, staged y conflictos")
                    .contextMenu {
                        Button("copiar estado git", systemImage: "doc.on.clipboard") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(store.mission.git.affected) cambios · \(store.mission.git.staged) staged · \(store.mission.git.conflicts) conflictos", forType: .string)
                        }
                    }
            }
            IslandTickerView(steps: agentSteps, openDiff: store.openLatestDiff)
            if store.terminalTargetAvailable {
                Button("saltar a terminal") { store.focusTerminal() }
                    .buttonStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: 0xE0824F))
            } else if store.state == .waiting || store.state == .error {
                Text("terminal no identificada").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            }
            HStack(spacing: 8) {
                Button("mission control") { AppController.shared.showMissionDashboard() }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Button("relevo") { AppController.shared.showRelay() }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            }
        }
    }

}

/// `ClaudePet --snapshot-island <ruta.png>`: dibuja la isla en sus cuatro modos sobre un fondo de escritorio, sin abrir ventanas.
@MainActor
enum IslandSnapshot {
    static func render(to path: String) {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 38, auxLeft: 664, auxRight: 664)
        let store = PetStore.shared
        let rows: [(IslandMode, PetState)] = [(.hidden, .idle), (.peek, .idle), (.compact, .thinking), (.expanded, .tool), (.expanded, .waiting)]
        let demoPermission = PermissionAsk(id: "demo", session: "abc", tool: "Bash", project: "claude-pet",
                                           detail: "rm -rf build && swift build -c release", canAlways: true, at: Date())
        let demoQuestion = QuestionAsk(id: "question-demo", session: "abc", project: "claude-pet", questions: [
            IslandQuestion(id: "q", header: "modo", question: "como quieres continuar?", options: [("rápido", "menos pasos"), ("seguro", "más revisión")], multiSelect: false)])
        let previousContext = store.contextReading
        store.setSnapshotContext(ContextReading(usedTokens: 112_000, compactAtTokens: 160_000, model: "claude"))
        defer { store.permissionAsks = []; store.questionAsks = []; store.setSnapshotContext(previousContext) }
        let cell = NotchGeometry.panelSize
        let view = VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let model = IslandModel()
                let _ = { store.permissionAsks = i == 4 ? [demoPermission] : []; store.questionAsks = i == 3 ? [demoQuestion] : [] }()
                let h: CGFloat = i >= 3 ? NotchGeometry.permissionHeight : 150
                let _ = { model.mode = row.0; model.size = NotchGeometry.islandSize(row.0, metrics: m, expandedHeight: h) }()
                IslandView(model: model, store: store)
                    .frame(width: cell.width, height: i == 4 ? 250 : 190, alignment: .top)
                    .clipped()
                    .background(Color(hex: 0x6C7A89))
            }
        }
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-poses <ruta.png>`: la mascota en reposo, mirando, parpadeando, molesta, mareada y saltando.
    static func poses(to path: String) {
        func look(_ dx: Int, _ dy: Int) -> PetPose { var q = PetPose(); q.eyeDX = dx; q.eyeDY = dy; return q }
        var blink = PetPose(); blink.blink = true; blink.scaleY = 1.04
        var annoyed = PetPose(); annoyed.blink = true; annoyed.dx = 1
        var dizzy = PetPose(); dizzy.dizzy = true; dizzy.rotation = 8
        var hop = PetPose(); hop.dy = -3
        var land = PetPose(); land.scaleY = 0.93; land.scaleX = 1.04
        let cells: [(String, PetPose)] = [("reposo", PetPose()), ("derecha", look(1, 0)), ("arriba", look(0, -1)), ("parpadeo", blink),
                                          ("molesta", annoyed), ("mareada", dizzy), ("salto", hop), ("caida", land)]
        let view = HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                VStack(spacing: 4) {
                    Canvas { gc, size in
                        let px = PetAnimator.apply(Sprite.block(.idle, tick: 0), pose: c.1)
                        PetFace.draw(&gc, size: size, pixels: px, pose: c.1)
                    }.frame(width: 96, height: 96).background(Color.black)
                    Text(c.0).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                }
            }
            ForEach(Array([(CodexAvatar.Face.dots(2), "codex pensando"), (CodexAvatar.Face.happy, "codex saludo")].enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Canvas { gc, size in
                        let u = min(size.width / 18, size.height / 21)
                        let ox = (size.width - 18 * u) / 2; let oy = (size.height - 21 * u) / 2
                        for c in CodexAvatar.cells(legs: .stand, face: item.0) { gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.5, height: u + 0.5)), with: .color(c.c)) }
                        if item.1 == "codex saludo" { for c in CodexAvatar.armCells(.wave(true), skin: .cloud) { gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.5, height: u + 0.5)), with: .color(c.c)) } }
                    }.frame(width: 108, height: 126).background(Color.black)
                    Text(item.1).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                }
            }
        }.padding(12).background(Color(hex: 0x2A2A2E))
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
