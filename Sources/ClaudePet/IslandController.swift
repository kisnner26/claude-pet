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
        guard let m = NotchGeometry.pick(NSScreen.screens.map(Self.metrics)) else { return }
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
        let asking = !store.permissionAsks.isEmpty
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
        if model.mode != mode { model.mode = mode }
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
                .contentShape(Rectangle())
                .onTapGesture { model.poke() }
            if !compact { if let ask = store.permissionAsks.first { permissionCard(ask) } else { details } }
            Spacer(minLength: 0)
            if compact && store.codexPresent { Circle().fill(codexColor).frame(width: 8, height: 8) }
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

    private var codexColor: Color { store.codexState == .idle ? Color.white.opacity(0.35) : Color(hex: 0x5270E8) }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("claude · \(store.state.label.lowercased())").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(.white)
            if let a = store.claudeBubbleActivity {
                Text(a.title).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85)).lineLimit(1)
                if !a.subtitle.isEmpty { Text(a.subtitle).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.55)).lineLimit(1) }
            }
            if store.codexPresent {
                Text("codex · \(store.codexState.label.lowercased())").font(.system(size: 12, design: .monospaced)).foregroundColor(codexColor)
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
                var px = Sprite.pixels(store.state, tick: tick, cue: store.cue(at: ctx.date))
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

/// `ClaudePet --snapshot-island <ruta.png>`: dibuja la isla en sus cuatro modos sobre un fondo de escritorio, sin abrir ventanas.
@MainActor
enum IslandSnapshot {
    static func render(to path: String) {
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 38, auxLeft: 664, auxRight: 664)
        let store = PetStore.shared
        let rows: [(IslandMode, PetState)] = [(.hidden, .idle), (.peek, .idle), (.compact, .thinking), (.expanded, .tool), (.expanded, .waiting)]
        store.permissionAsks = [PermissionAsk(id: "demo", session: "abc", tool: "Bash", project: "claude-pet",
                                              detail: "rm -rf build && swift build -c release", canAlways: true, at: Date()),
                                PermissionAsk(id: "demo2", session: "abc", tool: "Edit", project: "claude-pet", detail: "", canAlways: false, at: Date())]
        defer { store.permissionAsks = [] }
        let cell = NotchGeometry.panelSize
        let view = VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let model = IslandModel()
                let h: CGFloat = i == 4 ? NotchGeometry.permissionHeight : 150
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
        }.padding(12).background(Color(hex: 0x2A2A2E))
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
