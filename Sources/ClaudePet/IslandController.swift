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
    var onPetClick: () -> Void = {}
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
        p.contentView = NSHostingView(rootView: IslandView(model: model, store: store))
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
        if doneNow { finishedAt = now }
        lastClaude = c; lastCodex = x
        let finishedPending = finishedAt.map { now - $0 < 0.1 } ?? false

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let input = IslandInput(now: now,
                                overNotch: NotchGeometry.overNotch(mouse, metrics: m),
                                overIsland: NotchGeometry.contains(mouse, mode: machine.mode, metrics: m),
                                tasksRunning: tasksRunning(),
                                alertPending: c == .waiting || c == .error || x == .waiting || x == .error,
                                finishedPending: finishedPending,
                                idleSeconds: idle,
                                clickedPet: clicked)
        clicked = false
        let mode = machine.tick(input)

        let size = NotchGeometry.islandSize(mode, metrics: m)
        if model.mode != mode { model.mode = mode }
        if model.reason != machine.reason { model.reason = machine.reason }
        if model.countdown != machine.countdown { model.countdown = machine.countdown }
        if model.size != size { model.size = size }

        // los ojos siguen al cursor por toda la pantalla
        let f = NotchGeometry.islandFrame(mode, metrics: m)
        model.gaze = CGPoint(x: max(-1, min(1, (mouse.x - f.midX) / 400)), y: max(-1, min(1, (mouse.y - f.midY) / 300)))

        // clics traversantes: la ventana solo recibe el raton sobre la forma visible de la isla
        let interactive = mode != .hidden && NotchGeometry.contains(mouse, mode: mode, metrics: m)
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
            PetFace(store: store, gaze: model.gaze)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { model.onPetClick() }
            if !compact { details }
            Spacer(minLength: 0)
            if compact && store.codexPresent { Circle().fill(codexColor).frame(width: 8, height: 8) }
        }
        .padding(.leading, compact ? 8 : 24)
        .padding(.trailing, compact ? 10 : 24)
        .padding(.top, compact ? 0 : 38)
        .frame(maxHeight: .infinity, alignment: compact ? .center : .top)
        .transition(.opacity)
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

/// La mascota de Claude en miniatura. `gaze` queda disponible para que las pupilas sigan al cursor (siguiente paso).
struct PetFace: View {
    @ObservedObject var store: PetStore
    var gaze: CGPoint

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { ctx in
            let tick = store.animationsEnabled && !store.reduceMotion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            Canvas { gc, size in
                let u = size.width / 16
                for p in Sprite.pixels(store.state, tick: tick, cue: store.cue(at: ctx.date)) {
                    gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c))
                }
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
        let rows: [(IslandMode, PetState)] = [(.hidden, .idle), (.peek, .idle), (.compact, .thinking), (.expanded, .tool)]
        let cell = NotchGeometry.panelSize
        let view = VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let model = IslandModel()
                let _ = { model.mode = row.0; model.size = NotchGeometry.islandSize(row.0, metrics: m, expandedHeight: 150) }()
                IslandView(model: model, store: store)
                    .frame(width: cell.width, height: 190, alignment: .top)
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
