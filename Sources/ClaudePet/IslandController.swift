import SwiftUI
import AppKit
import Combine

/// Lo que la vista de la isla dibuja; la actualiza el controlador a 60 Hz.
@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .hidden
    @Published var reason: IslandReason = .none
    @Published var size = CGSize(width: 184, height: 38)
    @Published var hasNotch = true
    @Published var countdown: Double?
    /// Posicion del cursor respecto al centro de la isla, de -1 a 1; los ojos de la mascota lo siguen.
    @Published var gaze = CGPoint.zero
    /// Instantes (systemUptime) de los ultimos toques a la mascota y del ultimo fin de tarea.
    var pokes: [TimeInterval] = []
    var hopStart: TimeInterval?
    var greetUntil: TimeInterval = 0
    var onPetClick: () -> Void = {}

    func poke() {
        pokes.append(ProcessInfo.processInfo.systemUptime)
        if pokes.count > 6 { pokes.removeFirst(pokes.count - 6) }
        onPetClick()
    }
}

/// El primer clic sobre la isla debe pulsar el boton, no solo activar la ventana.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

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
        relocate()
        p.orderFrontRegardless()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.relocate() }
        })
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        model.gaze = CGPoint(x: max(-1, min(1, (mouse.x - f.midX) / 400)), y: max(-1, min(1, (mouse.y - f.midY) / 300)))

        // clics traversantes: la ventana solo recibe el raton sobre la forma visible de la isla
        let interactive = mode != .hidden && NotchGeometry.contains(mouse, mode: mode, metrics: m, expandedHeight: eh)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }
}

/// Forma de la isla: esquinas de arriba cuadradas (se funde con el borde) y de abajo redondeadas.
struct IslandShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var store: PetStore
    @State private var agentTab: IslandAgentTab = .claude

    private var open: Animation { .spring(response: 0.5, dampingFraction: 0.72) }
    private var close: Animation { .timingCurve(0.45, 0, 0.2, 1, duration: 0.34) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island.frame(width: model.size.width, height: model.size.height)
        }
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
        .animation(model.mode == .expanded ? open : close, value: model.size)
        .animation(model.mode == .expanded ? open : close, value: model.mode)
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
            if compact, let reading = store.contextReading {
                Text("\(reading.remainingPercent)%")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(contextColor(reading.pressure))
                    .accessibilityLabel("contexto: \(reading.remainingPercent) por ciento restante")
            }
            if !compact { if let ask = store.permissionAsks.first { permissionCard(ask) } else if let ask = store.questionAsks.first { questionCard(ask) } else { details } }
            Spacer(minLength: 0)
            if compact && store.codexPresent { CodexMini(store: store, greet: false).frame(width: 22, height: 24) }
        }
        .padding(.leading, compact ? 8 : 24)
        .padding(.trailing, compact ? 10 : 24)
        .padding(.top, compact ? 0 : 38)
        .frame(maxHeight: .infinity, alignment: compact ? .center : .top)
        .transition(.opacity)
    }

    /// Tarjeta de permiso: que quiere hacer Claude y tres botones.
    private func permissionCard(_ ask: PermissionAsk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("claude pide permiso").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xEC9A6E))
                if store.permissionAsks.count > 1 {
                    Text("+\(store.permissionAsks.count - 1) en espera").font(.system(size: 11, design: .monospaced)).foregroundColor(Color.white.opacity(0.5))
                }
            }
            Text(ask.project.isEmpty ? ask.tool : "\(ask.tool) · \(ask.project)")
                .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.6)).lineLimit(1)
            if !ask.detail.isEmpty {
                Text(ask.detail).font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                    .lineLimit(3).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            }
            HStack(spacing: 8) {
                permissionButton("denegar", fill: Color.white.opacity(0.1), ink: .white) { store.answerPermission(ask.id, .deny) }
                Spacer(minLength: 0)
                if ask.canAlways { permissionButton("siempre", fill: Color.white.opacity(0.1), ink: .white) { store.answerPermission(ask.id, .always) } }
                permissionButton("permitir", fill: Color(hex: 0xE0824F), ink: .black) { store.answerPermission(ask.id, .allow) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionButton(_ title: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(ink)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func questionCard(_ ask: QuestionAsk) -> some View {
        let q = ask.questions[0]
        return VStack(alignment: .leading, spacing: 8) {
            Text("claude pregunta").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xEC9A6E))
            Text(q.question).font(.system(size: 13)).foregroundColor(.white).lineLimit(2)
            HStack(spacing: 6) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { _, option in
                    permissionButton(option.label, fill: Color.white.opacity(0.1), ink: .white) {
                        let answers = Dictionary(uniqueKeysWithValues: ask.questions.enumerated().map { index, item in
                            (item.question, index == 0 ? option.label : "")
                        })
                        store.answerQuestion(ask.id, answers)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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

    private func contextColor(_ pressure: ContextPressure) -> Color {
        switch pressure {
        case .normal: return Color(hex: 0x5270E8)
        case .caution: return Color(hex: 0xE7B45B)
        case .critical: return Color(hex: 0xD85C5C)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.contextReading != nil || !store.mission.changes.isEmpty {
                HStack(spacing: 8) {
                    if let reading = store.contextReading { ContextRingView(reading: reading).scaleEffect(0.42).frame(width: 48, height: 48) }
                    if !store.mission.changes.isEmpty { FileOrbitView(files: store.mission.changes).scaleEffect(0.52).frame(width: 66, height: 66) }
                }
            }
            if store.codexPresent { Picker("agente", selection: $agentTab) { ForEach(IslandAgentTabs.available(codex: true), id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of: store.codexPresent) { agentTab = IslandAgentTabs.keep(agentTab, codex: $0) } }
            if agentTab == .claude {
                Text("claude · \(store.state.label.lowercased())").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(.white)
                if let a = store.claudeBubbleActivity { Text(a.title).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85)).lineLimit(1); if !a.subtitle.isEmpty { Text(a.subtitle).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.55)).lineLimit(1) } }
            } else {
                Text("codex · \(store.codexState.label.lowercased())").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(codexColor)
                Text("línea publicada por codex").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            ForEach(store.recentIslandSteps.prefix(3)) { step in
                Button { store.openLatestDiff() } label: {
                    HStack { Text(step.label).lineLimit(1); Spacer(); if !step.delta.isEmpty { Text(step.delta).foregroundColor(Color(hex: 0xE0824F)) } }
                }.buttonStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            }
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

/// La mascota de Claude en miniatura, con respiracion, parpadeo, mirada, reaccion al toque y salto al terminar.
struct PetFace: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let now = ProcessInfo.processInfo.systemUptime
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            let pose = PetAnimator.pose(at: now, gaze: model.gaze, pokes: model.pokes, hopStart: model.hopStart, motion: motion)
            Canvas { gc, size in
                var cue = store.cue(at: ctx.date)
                if model.greetUntil > now { cue = (cue ?? PeerCue(state: store.state, greet: false, cheer: false, concern: false)); cue?.greet = true }
                var px = Sprite.pixels(store.state, tick: tick, cue: cue)
                if store.state != .error { px = PetAnimator.apply(px, pose: pose) }
                PetFace.draw(&gc, size: size, pixels: px, pose: pose)
            }
        }
    }

    /// Dibuja el sprite con su pose: el cuerpo se mueve y se estira desde los pies.
    static func draw(_ gc: inout GraphicsContext, size: CGSize, pixels: [Px], pose: PetPose) {
        let u = size.width / 16
        gc.translateBy(x: size.width / 2 + pose.dx * u, y: size.height + pose.dy * u)
        gc.rotate(by: .degrees(pose.rotation))
        gc.scaleBy(x: pose.scaleX, y: pose.scaleY)
        gc.translateBy(x: -size.width / 2, y: -size.height)
        for p in pixels {
            gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u + 0.5, height: u + 0.5)), with: .color(p.c))   // +0,5 evita costuras al escalar o girar
        }
    }
}

struct CodexMini: View {
    @ObservedObject var store: PetStore
    let greet: Bool
    private func face(_ tick: Int) -> CodexAvatar.Face {
        switch store.codexState {
        case .waiting: return .alert(on: tick % 2 == 0)
        case .error: return .cross
        case .done: return .happy
        case .thinking, .starting: return .dots(tick % 4)
        case .tool: return .typing(tick)
        default: return .prompt(cursor: tick % 2 == 0)
        }
    }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 12.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            let face = self.face(tick)
            let legs: CodexAvatar.Legs = motion && tick % 8 < 4 ? .step : .stand
            CodexMiniFrame(face: face, legs: legs, tick: tick, skin: store.codexSkin, wave: greet && motion)
        }
    }
}

private struct CodexMiniFrame: View {
    let face: CodexAvatar.Face
    let legs: CodexAvatar.Legs
    let tick: Int
    let skin: CodexSkin
    let wave: Bool
    var body: some View {
        Canvas { gc, size in
                let u = min(size.width / 18, size.height / 21)
                let ox = (size.width - 18 * u) / 2
                let oy = (size.height - 21 * u) / 2
                for c in CodexAvatar.cells(legs: legs, face: face, skin: skin) {
                    gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
                }
                if wave { for c in CodexAvatar.armCells(.wave(tick % 8 < 4), skin: skin) { gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c)) } }
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
