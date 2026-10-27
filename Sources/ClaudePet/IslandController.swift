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
    private var follower = ScreenFollower()
    private var lastSoundMode: IslandMode = .hidden
    private var taskStartedAt: TimeInterval?
    private let music = MusicMonitor()
    private var lastAskCount = 0
    private var lastQuestionCount = 0
    private var lastScreenPreference: IslandScreenPreference?
    private var lastFixedScreen = ""

    init(store: PetStore) { self.store = store }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let p = PetPanel(contentRect: NSRect(origin: .zero, size: NotchGeometry.panelSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = DropHostingView(rootView: IslandView(model: model, store: store))
        host.onHover = { [weak self] over in self?.model.dropHover = over }
        host.onFiles = { [weak self] urls in
            guard let self, let text = FileDrop.text(for: urls) else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            let now = ProcessInfo.processInfo.systemUptime
            self.model.swallowStart = now
            // despues de tragar, un saltito de alegria
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.model.hopStart = ProcessInfo.processInfo.systemUptime }
            SoundEngine.shared.play(.allowed)
        }
        p.contentView = host
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
        SoundEngine.shared.enabled = store.soundsEnabled; SoundEngine.shared.volume = Float(store.soundVolume)
        SoundEngine.shared.play(.greeting)
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

    static func screenID(_ s: NSScreen) -> String {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { String($0.uint32Value) } ?? s.localizedName
    }

    private static func metrics(of s: NSScreen) -> ScreenMetrics {
        ScreenMetrics(frame: s.frame, safeTop: s.safeAreaInsets.top,
                      auxLeft: s.auxiliaryTopLeftArea?.width ?? 0, auxRight: s.auxiliaryTopRightArea?.width ?? 0,
                      menuBarHeight: NSStatusBar.system.thickness,
                      visibleFrame: s.visibleFrame,
                      menuBarHidden: s.safeAreaInsets.top == 0 && s.visibleFrame.maxY >= s.frame.maxY - 1,
                      id: screenID(s), name: s.localizedName)
    }

    /// Recalcula la pantalla elegida cada vez que se conecta, desconecta o cambia una pantalla.
    private func relocate() {
        guard let m = NotchGeometry.pick(NSScreen.screens.map(Self.metrics), preference: store.islandScreenPreference, mouse: NSEvent.mouseLocation,
                                         fixedID: store.islandFixedScreenID, followedID: follower.current) else { return }
        metrics = m
        let placement = store.islandPlacement
        model.hasNotch = placement == .top && NotchGeometry.hasNotch(m)
        model.placement = placement
        model.menuBarHidden = placement == .top && m.menuBarHidden
        panel?.setFrame(NotchGeometry.panelFrame(m, placement: placement), display: false)
    }

    private func tasksRunning() -> Bool {
        [store.state, store.codexState].contains { $0 != .idle && $0 != .done }
    }

    private func tick() {
        guard var m = metrics, let panel else { return }
        // la barra de menus se oculta y aparece sin avisar: se relee en cada tick, barato
        if let screen = NSScreen.screens.first(where: { $0.frame == m.frame }) {
            let hidden = screen.safeAreaInsets.top == 0 && screen.visibleFrame.maxY >= screen.frame.maxY - 1
            if hidden != m.menuBarHidden || screen.visibleFrame != m.visibleFrame { m.menuBarHidden = hidden; m.visibleFrame = screen.visibleFrame; metrics = m }
        }
        let placement = store.islandPlacement
        // seguir al raton con histeresis, o cambio de preferencia / pantalla fija desde el menu
        var moved = false
        if store.islandScreenPreference == .mouse {
            let under = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }).map(Self.screenID)
            let before = follower.current
            follower.update(now: ProcessInfo.processInfo.systemUptime, under: under)
            moved = follower.current != before
        }
        if lastScreenPreference != store.islandScreenPreference || lastFixedScreen != store.islandFixedScreenID {
            lastScreenPreference = store.islandScreenPreference; lastFixedScreen = store.islandFixedScreenID; moved = true
        }
        if model.placement != placement || moved { relocate(); m = metrics ?? m }
        machine.activationDelay = store.islandActivationDelay
        machine.closeDelay = store.islandCloseDelay > 0 ? store.islandCloseDelay : nil
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation

        // transiciones de estado: terminar de trabajar dispara la vista de fin
        let c = store.state, x = store.codexState
        let doneNow = (c == .done && lastClaude != .done) || (x == .done && lastCodex != .done)
        let errorNow = (c == .error && lastClaude != .error) || (x == .error && lastCodex != .error)
        let sound = SoundEngine.shared
        sound.enabled = store.soundsEnabled; sound.volume = Float(store.soundVolume)
        // modo foco: con el foco activo solo suenan las alertas
        let focusNow = store.focusMode.isActive(at: Date())
        sound.focus = focusNow
        if model.focusActive != focusNow { model.focusActive = focusNow }
        // pomodoro: al cambiar de fase suena; en el descanso la mascota se duerme
        if let phase = store.tickPomodoro(now: now) { sound.play(phase == .work ? .greeting : .rest) }
        let timerLabel = store.pomodoroLabel(now: now)
        if model.pomodoroLabel != timerLabel { model.pomodoroLabel = timerLabel }
        // una tarea larga que termina se celebra con confeti
        if tasksRunning() { if taskStartedAt == nil { taskStartedAt = now } }
        if doneNow {
            if let started = taskStartedAt, now - started >= PetAnimator.longTask { model.confettiStart = now }
            taskStartedAt = tasksRunning() ? now : nil
            finishedAt = now; model.hopStart = now; sound.play(.done)
            if c == .done && lastClaude != .done { ActivityStats.shared.recordFinished(agent: "claude", project: store.terminalProject) }
            if x == .done && lastCodex != .done { ActivityStats.shared.recordFinished(agent: "codex", project: store.terminalProject) }
            ActivityStats.shared.save()
            store.refreshWeeklyRecap()
        }
        if errorNow { sound.play(.error); ActivityStats.shared.recordError() }
        if store.permissionAsks.count > lastAskCount { sound.play(.permission) }
        if store.questionAsks.count > lastQuestionCount { sound.play(.question) }
        lastAskCount = store.permissionAsks.count; lastQuestionCount = store.questionAsks.count
        lastClaude = c; lastCodex = x
        let finishedPending = finishedAt.map { now - $0 < 0.1 } ?? false

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let asking = !store.permissionAsks.isEmpty || !store.questionAsks.isEmpty
        let eh = asking ? NotchGeometry.permissionHeight : NotchGeometry.expandedHeight
        // arrastrando archivos: la isla asoma y deja de ser transparente a los clics para poder recibirlos
        let dragging = NSEvent.pressedMouseButtons & 1 != 0 && NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let overZone = NotchGeometry.overNotch(mouse, metrics: m, placement: placement, activationWidth: store.islandActivationWidth)
        let input = IslandInput(now: now,
                                overNotch: overZone,
                                overIsland: NotchGeometry.contains(mouse, mode: machine.mode, metrics: m, placement: placement, expandedHeight: eh) || RunLoop.current.currentMode == .eventTracking,
                                tasksRunning: tasksRunning(),
                                alertPending: asking || c == .waiting || c == .error || x == .waiting || x == .error,
                                finishedPending: finishedPending,
                                idleSeconds: idle,
                                clickedPet: clicked || (dragging && overZone),
                                dismissFinished: model.dismissRequested)
        clicked = false; model.dismissRequested = false
        let dizzyLeft = PetAnimator.dizzyRemaining(pokes: model.pokes, at: now).map { Int($0.rounded(.up)) }
        if model.dizzyLeft != dizzyLeft { model.dizzyLeft = dizzyLeft }
        model.idleSeconds = store.pomodoro.onBreak ? max(idle, PetAnimator.sleepAfter + 1) : idle
        model.dancing = store.danceToMusic && music.isPlaying(enabled: true, now: now)
        let mode = machine.tick(input)
        if model.hover != input.overIsland { model.hover = input.overIsland }
        let desiredInterval = IslandPollingPolicy.interval(hidden: mode == .hidden, tasksRunning: tasksRunning(), attention: asking)
        if desiredInterval != timerInterval { scheduleTimer(interval: desiredInterval) }

        let size = NotchGeometry.islandSize(mode, metrics: m, placement: placement, expandedHeight: eh,
                                            compactContentWidth: store.islandCompactMode.contentWidth(clock: store.islandShowClock))
        if model.mode != mode {
            if mode == .peek && model.mode == .hidden { model.greetUntil = now + 1.4 }
            if mode == .peek && lastSoundMode == .hidden { sound.play(.peek) }
            else if mode == .expanded && lastSoundMode != .expanded { sound.play(.open) }
            else if lastSoundMode == .expanded && mode != .expanded { sound.play(.fold) }
            lastSoundMode = mode
            model.mode = mode
        }
        if model.reason != machine.reason { model.reason = machine.reason }
        if model.countdown != machine.countdown { model.countdown = machine.countdown }
        if model.size != size { model.size = size }

        // los ojos siguen al cursor por toda la pantalla
        let f = NotchGeometry.islandFrame(mode, metrics: m, placement: placement, expandedHeight: eh)
        let cursorGaze = CGPoint(x: max(-1, min(1, (mouse.x - f.midX) / 400)), y: max(-1, min(1, (mouse.y - f.midY) / 300)))
        // la tarjeta aparece a la izquierda de la mascota en la vista abierta.
        model.gaze = asking && mode == .expanded ? CGPoint(x: -0.8, y: 0) : cursorGaze

        // clics traversantes: la ventana solo recibe el raton sobre la forma visible de la isla
        let interactive = (mode != .hidden && NotchGeometry.contains(mouse, mode: mode, metrics: m, placement: placement, expandedHeight: eh)) || (dragging && overZone)
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
        ZStack(alignment: anchor) {
            Color.clear
            island.frame(width: model.size.width, height: model.size.height)
        }
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: anchor)
        .animation(transition, value: model.size)
        .animation(transition, value: model.mode)
    }

    private var anchor: Alignment {
        switch model.placement { case .top, .floating: return .top; case .bottom: return .bottom; case .side: return .trailing }
    }

    /// Sin notch no hay silueta que se funda con el borde: borde interior fino y sombra suave hacia dentro de la pantalla.
    private var drawsOwnEdge: Bool { !model.hasNotch }
    private var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    private var shadowY: CGFloat { model.placement == .bottom ? -3 : 3 }

    private var island: some View {
        let shape = IslandShape(radius: NotchGeometry.cornerRadius(model.mode), corners: model.placement.corners)
        return ZStack(alignment: .topLeading) {
            shape
                .fill(Color.black)
                // el brillo va como superposicion: no puede cambiar el tamaño de la isla
                .overlay(alignment: .topLeading) {
                    IslandGlowView(glow: glow).animation(store.reduceMotion ? nil : .easeInOut(duration: 0.45), value: glow)
                }
                .opacity(model.mode == .hidden && (model.hasNotch || model.menuBarHidden) ? 0 : 1)
            if drawsOwnEdge && model.mode != .hidden || (drawsOwnEdge && !model.menuBarHidden) {
                // el recorte deja visible solo la mitad interior del trazo
                shape.stroke(Color.white.opacity(highContrast ? 0.7 : 0.14), lineWidth: highContrast ? 2 : 1)
            }
            if model.mode != .hidden { content }
            if let c = model.countdown {
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 160 * c, height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(drawsOwnEdge && model.mode != .hidden ? 0.35 : 0), radius: 6, x: 0, y: shadowY)
    }

    @ViewBuilder private var content: some View {
        let compact = model.mode != .expanded
        let items = store.islandCompactMode.items
        let side: CGFloat = compact ? 20 : 56
        HStack(alignment: compact ? .center : .top, spacing: compact ? 6 : 16) {
            PetFace(store: store, model: model)
                .frame(width: side, height: side)
                .overlay(Circle().stroke(statusColor, lineWidth: compact ? 1.5 : 2.5).opacity(store.state == .idle ? 0 : 0.9))
                .overlay(alignment: .topLeading) {
                    // punto de estado en la esquina de la mascota, solo con la isla abierta
                    if !compact, let dot = dotColor {
                        Circle().fill(dot).frame(width: 9, height: 9).overlay(Circle().stroke(Color.black, lineWidth: 1.5)).offset(x: -3, y: -3)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.poke() }
                .accessibilityLabel("claude: \(store.state.label.lowercased()), \(store.stateDurationLabel)")
                .accessibilityHint("pulsa para abrir el detalle")
                .contextMenu {
                    ForEach(Outfit.allCases) { outfit in
                        Toggle(outfit.title, isOn: Binding(get: { store.wardrobe.contains(outfit) }, set: { _ in store.toggleOutfit(outfit) }))
                    }
                    Divider()
                    Toggle("atuendos de temporada", isOn: $store.seasonalOutfits)
                }
            if compact && store.state != .idle {
                Image(systemName: statusSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(statusColor)
                    .accessibilityHidden(true)
                    .help("estado claude: \(store.state.label.lowercased())")
            }
            if compact, items.context, let reading = store.contextReading {
                IslandContextMeter(reading: reading, label: "contexto", onOpen: { model.poke() })
                if reading.pressure == .critical { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundColor(contextColor(reading.pressure)).accessibilityHidden(true).onTapGesture { model.poke() }.contextMenu { Button("copiar contexto", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.summary, forType: .string) } } }
            }
            if compact, items.badge, let badge = store.attentionBadgeLabel {
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
            if !compact { expandedBody }
            Spacer(minLength: 0)
            if compact, items.duration, store.state != .idle {
                Text(store.stateDurationLabel).font(.system(size: 9, design: .monospaced)).foregroundColor(durationColor(store.stateDurationSeconds))
                    .accessibilityLabel("activo desde hace \(store.stateDurationLabel)")
            }
            if compact, items.branch, !store.mission.git.branch.isEmpty {
                Label(store.mission.git.branch, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon)
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    .accessibilityLabel("rama \(store.mission.git.branch)")
            }
            if compact, let loop = store.loopAlert {
                Button { model.poke() } label: { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0xE7B45B)) }
                    .buttonStyle(.plain).help("\(loop.title) · pulsa para abrir").accessibilityLabel(loop.title)
            }
            if compact, let timer = model.pomodoroLabel {
                Text(timer).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(store.pomodoro.onBreak ? Color(hex: 0x6CCB8A) : Color(hex: 0xE0824F))
                    .accessibilityLabel("temporizador: \(timer)")
            }
            if compact, model.focusActive {
                Image(systemName: "moon.fill").font(.system(size: 9)).foregroundColor(.white.opacity(0.5)).help("modo foco activo").accessibilityLabel("modo foco activo")
            }
            if compact, store.islandShowClock { IslandClock() }
            if compact && store.codexPresent {
                if items.context, let reading = store.codexContextReading {
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
        .padding(.top, compact ? 0 : (model.hasNotch ? 38 : 14))
        .frame(maxHeight: .infinity, alignment: compact ? .center : .top)
        .transition(.opacity)
    }

    @ViewBuilder private var expandedBody: some View {
        if model.dropHover || model.swallowStart.map({ ProcessInfo.processInfo.systemUptime - $0 < 0.8 }) == true {
            IslandDropZone(model: model)
        } else if let left = model.dizzyLeft {
            IslandDizzyNotice(seconds: left)
        } else if let ask = store.permissionAsks.first {
            PermissionCardView(store: store, ask: ask)
        } else if let ask = store.questionAsks.first {
            QuestionCardView(store: store, ask: ask, selections: $questionSelections, index: $questionIndex, freeText: $questionFreeText, commit: commitQuestion)
        } else if model.reason == .finished {
            IslandFinishedCard(store: store) { model.dismissRequested = true }
        } else {
            IslandOverviewView(store: store, agentTab: $agentTab)
        }
    }

    private var glow: IslandGlow.Glow? {
        // solo con la isla abierta: el desenfoque cuesta y en compacta no se ve
        guard model.mode == .expanded else { return nil }
        return IslandGlow.glow(state: store.state, codex: store.codexState, reason: model.reason,
                               asking: !store.permissionAsks.isEmpty || !store.questionAsks.isEmpty, dizzy: model.dizzyLeft != nil)
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

    private var dotColor: Color? {
        if !store.permissionAsks.isEmpty || !store.questionAsks.isEmpty { return Color(hex: 0xE7B45B) }
        if model.reason == .finished { return Color(hex: 0x6CCB8A) }
        return store.state == .idle ? nil : statusColor
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
        r.scale = scale
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

extension IslandSnapshot {
    /// Escala de las capturas: `CLAUDE_PET_SNAPSHOT_SCALE` (1 o 2), por defecto 2.
    static var scale: CGFloat {
        let v = Double(ProcessInfo.processInfo.environment["CLAUDE_PET_SNAPSHOT_SCALE"] ?? "") ?? 2
        return v <= 1 ? 1 : 2
    }

    /// `ClaudePet --snapshot-gallery <carpeta>`: la isla en cada ubicacion y sobre barras clara, oscura y de color.
    static func gallery(to dir: String) {
        let store = PetStore.shared
        let previousContext = store.contextReading, previousState = store.state
        store.setSnapshotState(.thinking)
        defer { store.setSnapshotContext(previousContext); store.setSnapshotState(previousState) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cases: [(String, IslandPlacement, Bool, IslandMode, Color)] = [
            ("sin-notch-barra-oscura", .top, false, .compact, Color(hex: 0x1F1F24)),
            ("sin-notch-barra-clara", .top, false, .compact, Color(hex: 0xE9E9EE)),
            ("sin-notch-fondo-color", .top, false, .compact, Color(hex: 0x3E6FB0)),
            ("sin-notch-abierta", .top, false, .expanded, Color(hex: 0x6C7A89)),
            ("con-notch", .top, true, .compact, Color(hex: 0x6C7A89)),
            ("abajo", .bottom, false, .compact, Color(hex: 0x6C7A89)),
            ("lateral", .side, false, .compact, Color(hex: 0x6C7A89)),
            ("flotante", .floating, false, .compact, Color(hex: 0x6C7A89)),
        ]
        for (name, placement, notch, mode, bg) in cases {
            var m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: notch ? 38 : 0, auxLeft: notch ? 628 : 0, auxRight: notch ? 628 : 0, menuBarHeight: notch ? 38 : 24)
            m.visibleFrame = CGRect(x: 0, y: 70, width: 1440, height: 806)
            let model = IslandModel()
            model.mode = mode; model.placement = placement; model.hasNotch = notch && placement == .top
            model.size = NotchGeometry.islandSize(mode, metrics: m, placement: placement, expandedHeight: 150, compactContentWidth: 150)
            let size = CGSize(width: 440, height: 190)
            let view = IslandView(model: model, store: store)
                .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
                .frame(width: size.width, height: size.height, alignment: placement == .bottom ? .bottom : (placement == .side ? .trailing : .top))
                .clipped().background(bg)
            let r = ImageRenderer(content: view)
            r.scale = scale
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: dir + "/\(name)-\(Int(scale))x.png"))
        }
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-wardrobe <ruta.png>`: la mascota con cada atuendo y con todos a la vez.
    static func wardrobe(to path: String) {
        let sets: [(String, Set<Outfit>)] = [("sin nada", [])] + Outfit.allCases.map { ($0.title, [$0]) } + [("todos", Set(Outfit.allCases))]
        let view = HStack(spacing: 12) {
            ForEach(Array(sets.enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 6) {
                    Canvas { gc, size in
                        var px = Sprite.block(.idle, tick: 3)
                        px = Wardrobe.compose(px, outfits: entry.1, state: .idle, tick: 3)
                        PetFace.draw(&gc, size: size, pixels: px, pose: PetPose())
                    }.frame(width: 96, height: 96)
                    Text(entry.0).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                }
            }
        }.padding(16).background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// Imagen compartible del resumen semanal. Sin nombres de proyecto salvo que el usuario lo pida.
struct RecapCard: View {
    let recap: WeeklyRecap
    var showProject = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Canvas { gc, size in PetFace.draw(&gc, size: size, pixels: Sprite.block(.done, tick: 0), pose: PetPose()) }.frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MI SEMANA").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(Color(hex: 0xE0824F))
                    Text("nivel \(recap.level) · racha de \(recap.streak) \(recap.streak == 1 ? "dia" : "dias")").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                }
            }
            HStack(spacing: 10) {
                stat("\(recap.sessions)", "sesiones")
                stat("\(recap.tools)", "herramientas")
                stat("\(recap.permissions)", "permisos")
                stat("\(recap.activeDays)/7", "dias activos")
            }
            if let a = recap.topAgent { Text("agente mas usado: \(a)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.7)) }
            if showProject, let p = recap.topProject { Text("proyecto mas usado: \(p)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.7)) }
            if let d = recap.busiestDay { Text("dia mas activo: \(d)").font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.7)) }
        }
        .padding(22).frame(width: 420, alignment: .leading).background(Color.black)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @MainActor static func png(_ recap: WeeklyRecap, showProject: Bool) -> Data? {
        let r = ImageRenderer(content: RecapCard(recap: recap, showProject: showProject))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-emotes <ruta.png>`: dormida, preocupada, bailando y con confeti.
    static func emotes(to path: String) {
        let t: TimeInterval = 3.2
        let cases: [(String, PetState, PetScene)] = [
            ("dormida", .idle, PetScene(idleSeconds: 400, state: .idle)),
            ("preocupada", .error, PetScene(state: .error)),
            ("bailando", .idle, PetScene(state: .idle, dancing: true)),
            ("confeti", .done, PetScene(state: .done, confettiStart: t - 1.0)),
        ]
        let view = HStack(spacing: 14) {
            ForEach(Array(cases.enumerated()), id: \.offset) { _, c in
                VStack(spacing: 6) {
                    Canvas { gc, size in
                        let pose = PetAnimator.pose(at: t, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: c.2)
                        var overlay = gc
                        let px = PetAnimator.apply(Sprite.block(c.1, tick: 3), pose: pose)
                        PetFace.draw(&gc, size: size, pixels: px, pose: pose)
                        PetFace.draw(&overlay, size: size, pixels: PetAnimator.particles(at: t, pose: pose, scene: c.2), pose: PetPose())
                    }.frame(width: 112, height: 112)
                    Text(c.0).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                }
            }
        }.padding(16).background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-style <ruta.png>`: permiso, terminado, mareo y zona de archivos con el brillo de cada estado.
    static func style(to path: String) {
        let store = PetStore.shared
        let previousState = store.state
        defer { store.permissionAsks = []; store.setSnapshotState(previousState) }
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: 0, auxLeft: 0, auxRight: 0)
        let ask = PermissionAsk(id: "d", session: "s", tool: "Bash", project: "korus", detail: "git push origin main", canAlways: true, at: Date())
        let scenes: [(String, (IslandModel, PetStore) -> Void)] = [
            ("trabajando", { _, s in
                s.permissionAsks = []; s.setSnapshotState(.tool)
                s.setSnapshotContext(ContextReading(usedTokens: 112_000, compactAtTokens: 160_000, model: "claude"))
                let now = Date()
                s.setSnapshotSteps([IslandStep(agent: "claude", tool: "Read", target: "src/billing.ts", added: 0, deleted: 0, workspace: "", at: now.addingTimeInterval(-42)),
                                    IslandStep(agent: "claude", tool: "Edit", target: "src/billing.ts", added: 3, deleted: 1, workspace: "", at: now.addingTimeInterval(-18)),
                                    IslandStep(agent: "claude", tool: "Bash", target: "npm test", added: 0, deleted: 0, workspace: "", at: now.addingTimeInterval(-3))])
            }),
            ("permiso", { _, s in s.setSnapshotState(.waiting); s.permissionAsks = [ask] }),
            ("terminado", { mo, s in s.permissionAsks = []; s.setSnapshotState(.done); mo.reason = .finished }),
            ("mareo", { mo, s in s.permissionAsks = []; s.setSnapshotState(.idle); mo.dizzyLeft = 3 }),
            ("archivos", { mo, s in s.permissionAsks = []; s.setSnapshotState(.idle); mo.dropHover = true }),
        ]
        // una imagen por escena: todas comparten el PetStore, asi que se dibujan de una en una
        for (name, apply) in scenes {
            let model = IslandModel()
            model.mode = .expanded; model.placement = .top; model.hasNotch = false
            apply(model, store)
            model.size = NotchGeometry.islandSize(.expanded, metrics: m, placement: .top, expandedHeight: name == "permiso" ? NotchGeometry.permissionHeight : NotchGeometry.expandedHeight)
            let view = IslandView(model: model, store: store)
                .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
                .background(Color(hex: 0x1B2A4A))
            let r = ImageRenderer(content: view)
            r.scale = scale
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let base = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
            try? png.write(to: URL(fileURLWithPath: "\(base)-\(name).png"))
        }
    }
}
