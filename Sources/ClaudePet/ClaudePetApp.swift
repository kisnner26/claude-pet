import SwiftUI
import AppKit
import Combine

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // sin esto macOS impide arrastrar la ventana sobre la barra de menu y fuera de los bordes
    override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }
}

/// Vista que captura el arrastre y mueve la ventana a mano (sin limites de pantalla).
final class DragHostingView<Content: View>: NSHostingView<Content> {
    private var grab: NSPoint = .zero
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    private var downAt: NSPoint = .zero
    private var dragged = false
    /// Accion del clic sin arrastre. Por omision abre la app de Claude.
    var onClick: ((NSPoint) -> Void)?
    var onDragChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        dragged = false
        grab = NSEvent.mouseLocation - (window?.frame.origin ?? .zero)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if abs(p.x - downAt.x) > 3 || abs(p.y - downAt.y) > 3 { dragged = true }
        if dragged {
            onDragChanged?(true)
            window?.setFrameOrigin(p - grab)
        }
    }
    override func mouseUp(with event: NSEvent) {
        onDragChanged?(false)
        guard !dragged else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let onClick { onClick(point); return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

private func - (a: NSPoint, b: NSPoint) -> NSPoint { NSPoint(x: a.x - b.x, y: a.y - b.y) }

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var shared: AppController!
    override init() { super.init(); AppController.shared = self }
    private var panel: PetPanel!
    private var claudeBubble: NSPanel!
    private var codexBubble: NSPanel!
    private var stage: NSPanel!
    private var missionPanel: NSPanel!
    private var relayPanel: NSPanel!
    private var codexPanel: PetPanel!
    private var presence: AppPresence?
    private var foreground: ForegroundAppMonitor?
    private var cancellables = Set<AnyCancellable>()
    private let server = EventServer()
    private let busServer = EventServer(path: PetBus.ownSocket)

    func applicationDidFinishLaunching(_ n: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-hero"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.run(into: CommandLine.arguments[i + 1]); exit(0)
        }
        if CommandLine.arguments.contains("--selftest-safety") { exit(SafetySelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-mission") { exit(MissionSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-handoff") { exit(HandoffSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-relay") {
            Task { exit(await SessionRelaySelfTest.run() ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--diagnose-relay") {
            Task.detached { exit(LocalAgentSessionReader.diagnose() ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--selftest-companion") { exit(CompanionSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-football") { exit(FootballSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-scout") { exit(WebScoutSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-football"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.footballSheet(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-overlay"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.overlayPreview(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-systems"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.systemsPreview(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1]); exit(0)
        }
        NSApp.setActivationPolicy(.accessory)

        let host = DragHostingView(rootView: PetView(store: PetStore.shared))
        host.onClick = { [weak self] point in self?.handleClaudePetClick(point) }
        let p = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 128, height: 128),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.setFrameAutosaveName("ClaudePetWindow")
        if !p.setFrameUsingName("ClaudePetWindow"), let s = NSScreen.main {
            p.setFrameTopLeftPoint(NSPoint(x: s.visibleFrame.maxX - 180, y: s.visibleFrame.maxY - 24))
        }
        panel = p                      // se muestra segun la presencia (applyVisibility)
        setUpCodexWindow()
        setUpBubbles()
        setUpStage()
        setUpMissionPanel()
        setUpRelayPanel()
        if CommandLine.arguments.contains("--open-mission") { DispatchQueue.main.async { [weak self] in self?.showMissionDashboard() } }
        if CommandLine.arguments.contains("--open-relay") { DispatchQueue.main.async { [weak self] in self?.showRelay() } }
        PetStore.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.applyVisibility() } }.store(in: &cancellables)
        let watcher = AppPresence { claude, codex in PetStore.shared.setApps(claude: claude, codex: codex) }
        presence = watcher
        watcher.start()
        let foregroundWatcher = ForegroundAppMonitor { PetStore.shared.setForegroundApp($0) }
        foreground = foregroundWatcher
        foregroundWatcher.start()
        applyVisibility()

        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.claudepet.trigger"), object: nil, queue: .main) { n in
            guard let name = n.userInfo?["name"] as? String else { return }
            Task { @MainActor in if PetStore.triggerNames.contains(name) { PetStore.shared.trigger(name) } }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.claudepet.webscout"), object: nil, queue: .main) { n in
            guard let action = n.userInfo?["action"] as? String else { return }
            Task { @MainActor in
                switch action {
                case "mark": PetStore.shared.webScout.markSelection()
                case "audit": PetStore.shared.webScout.auditVisibleControls()
                case "clear": PetStore.shared.webScout.clear()
                case "next": PetStore.shared.webScout.nextFinding()
                case "previous": PetStore.shared.webScout.previousFinding()
                default: break
                }
            }
        }

        server.onLine = { line in
            guard let ev = PetEvent.parse(line) else { return }
            Task { @MainActor in PetStore.shared.apply(ev) }
        }
        do { try server.start(); PetStore.shared.setBridge(true) }
        catch { PetStore.shared.setBridge(false); NSLog("ClaudePet: no se pudo abrir el socket: \(error)") }

        busServer.onLine = { line in Task { @MainActor in PetStore.shared.receive(line: line) } }
        do { try busServer.start(); PetStore.shared.setBus(true) }
        catch { PetStore.shared.setBus(false); NSLog("ClaudePet: pet bus no disponible: \(error)") }
    }

    /// Renderiza cada estado (4 fotogramas) a un PNG para revisar el sprite sin abrir la ventana.
    private func snapshot(to path: String) {
        let u: CGFloat = 6
        // CLAUDE_PET_SNAP_PEER=1 dibuja ademas al par (el estado del par = el de cada columna)
        let withPeer = ProcessInfo.processInfo.environment["CLAUDE_PET_SNAP_PEER"] == "1"
        func cue(_ st: PetState, _ t: Int) -> PeerCue? { withPeer ? PeerCue(state: st, greet: t == 0, cheer: t == 6, concern: false) : nil }
        let view = VStack(spacing: 8) { ForEach(Skin.allCases, id: \.self) { sk in HStack(spacing: 8) {
            ForEach(PetState.allCases, id: \.self) { st in
                VStack(spacing: 6) {
                    ForEach([0, 6], id: \.self) { t in
                        Canvas { gc, _ in
                            for p in (sk == .block ? Sprite.block(st, tick: t, cue: cue(st, t)) : Sprite.classic(st, tick: t, cue: cue(st, t))) {
                                gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c))
                            }
                        }.frame(width: 16 * u, height: 16 * u)
                    }
                }
            }
        } } }.padding(10).background(Pal.charcoal)
        let r = ImageRenderer(content: view)
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    /// Cada mascota tiene su propia burbuja. Separarlas impide que el estado de una esconda al de la otra.
    private func setUpBubbles() {
        claudeBubble = makeBubble(for: .claude)
        codexBubble = makeBubble(for: .codex)
        let refresh: () -> Void = { [weak self] in self?.placeBubbles() }
        for window in [panel as NSWindow, codexPanel as NSWindow] {
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in refresh() }
        }
        PetStore.shared.objectWillChange.sink { DispatchQueue.main.async { refresh() } }.store(in: &cancellables)
        placeBubbles()
    }

    private func makeBubble(for owner: BubbleOwner) -> NSPanel {
        let b = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 76),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        b.contentView = NSHostingView(rootView: BubbleView(store: PetStore.shared, owner: owner))
        b.isOpaque = false
        b.backgroundColor = .clear
        b.hasShadow = false
        b.ignoresMouseEvents = true
        b.level = .statusBar
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return b
    }

    /// Ventana de Codex: una entidad independiente de la de Claude (su propia posicion, su propio arrastre, su propio clic).
    private func setUpCodexWindow() {
        let host = DragHostingView(rootView: CodexPetView(store: PetStore.shared))
        host.onClick = { [weak self] point in self?.handleCodexPetClick(point) }
        host.onDragChanged = { dragging in
            Task { @MainActor in PetStore.shared.setCodexDragging(dragging) }
        }
        let p = PetPanel(contentRect: NSRect(origin: .zero, size: StageMetrics.codexSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.setFrameAutosaveName("CodexPetWindow")
        if !p.setFrameUsingName("CodexPetWindow") {
            // primera vez: junto a Claude, a su izquierda (o a su derecha si no hay sitio). Desde ahi cada una se mueve sola.
            let pf = panel.frame
            let vis = (panel.screen ?? NSScreen.main)?.visibleFrame ?? pf
            var x = pf.minX - StageMetrics.codexSize.width - 12
            if x < vis.minX { x = pf.maxX + 12 }
            p.setFrameOrigin(NSPoint(x: x, y: pf.minY))
        }
        codexPanel = p
        for w in [p, panel as NSWindow] {
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.windowsMoved() }
            }
        }
    }

    private func handleClaudePetClick(_ point: NSPoint) {
        let store = PetStore.shared
        if let file = PetOverlayLayout.file(at: point, files: store.mission.changes) {
            store.pullDiff(file)
            return
        }
        if store.contextReading != nil, PetOverlayLayout.hitsContextRing(point) {
            showRelay()
            return
        }
        if store.radarTarget != nil {
            store.activateRadarTarget()
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func handleCodexPetClick(_ point: NSPoint) {
        let store = PetStore.shared
        let overlayPoint = CGPoint(x: point.x, y: point.y - 12)
        if let file = PetOverlayLayout.file(at: overlayPoint, files: store.codexChanges) {
            store.pullCodexDiff(file)
            return
        }
        if store.codexContextReading != nil, PetOverlayLayout.hitsContextRing(overlayPoint) {
            showRelay()
            return
        }
        if store.codexRadarTarget != nil {
            store.activateCodexRadarTarget()
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppPresence.codexBundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func windowsMoved() { updatePair(); placeStage(); placeBubbles() }

    /// Recalcula si las dos mascotas se ven y estan lo bastante cerca para jugar, y de que lado esta cada una.
    private func updatePair() {
        guard panel != nil, codexPanel != nil else { return }
        let both = panel.isVisible && codexPanel.isVisible
        let geo = both ? GameLayout.make(claude: panel.frame, codex: codexPanel.frame) : nil
        PetStore.shared.setPair(geometry: geo, codexSide: codexPanel.frame.midX < panel.frame.midX ? -1 : 1)
    }

    /// Capa del partido: transparente y sin raton, cubre a las dos mascotas solo mientras se juega.
    private func setUpStage() {
        let st = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        st.contentView = NSHostingView(rootView: StageView(store: PetStore.shared))
        st.isOpaque = false
        st.backgroundColor = .clear
        st.hasShadow = false
        st.ignoresMouseEvents = true
        st.level = .statusBar
        st.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        stage = st
        PetStore.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.placeStage() } }.store(in: &cancellables)
        PetStore.shared.mission.$relay.sink { [weak self] _ in DispatchQueue.main.async { self?.placeStage() } }.store(in: &cancellables)
    }

    private func setUpMissionPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 590, height: 560),
                            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Mission Control"
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MissionDashboardView(store: PetStore.shared))
        missionPanel = panel
    }

    private func setUpRelayPanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 690),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "relevo de sesión"
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SessionRelayView(store: PetStore.shared))
        relayPanel = panel
    }

    func showRelay() {
        if !relayPanel.isVisible { relayPanel.center() }
        relayPanel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .relayPresented, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMissionDashboard() {
        if let view = missionPanel.contentView {
            view.layoutSubtreeIfNeeded()
            missionPanel.setContentSize(view.fittingSize)
        }
        let wasVisible = missionPanel.isVisible
        if !wasVisible { missionPanel.center() }
        let final = missionPanel.frame
        let animate = !wasVisible && !PetStore.shared.reduceMotion
        if animate {
            // se abre desde arriba, un poco más pequeño y transparente, y se asienta
            missionPanel.alphaValue = 0
            missionPanel.setFrame(final.insetBy(dx: final.width * 0.02, dy: final.height * 0.02).offsetBy(dx: 0, dy: 10), display: false)
        }
        missionPanel.makeKeyAndOrderFront(nil)
        if animate {
            NotificationCenter.default.post(name: .dashboardRevealed, object: nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                missionPanel.animator().setFrame(final, display: true)
                missionPanel.animator().alphaValue = 1
            }
        } else {
            missionPanel.alphaValue = 1
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeStage() {
        let store = PetStore.shared
        guard !store.userHidden, (store.gameActive || store.collaborationActive || store.hugActive || (store.animationsEnabled && store.mission.relay != nil)), let geo = store.gameGeometry else { stage.orderOut(nil); return }
        if stage.frame != geo.stageFrame { stage.setFrame(geo.stageFrame, display: false) }
        if !stage.isVisible { stage.orderFrontRegardless() }
    }

    private func placeBubbles() {
        let store = PetStore.shared
        let claude = bubbleRect(for: panel, above: true)
        var codex = bubbleRect(for: codexPanel, above: true)
        // Si ambas mascotas están cerca, la segunda burbuja prueba abajo para que las dos sigan legibles.
        if let claude, let candidate = codex, claude.intersects(candidate) {
            codex = bubbleRect(for: codexPanel, above: false)
            if let placedCodex = codex, claude.intersects(placedCodex) { codex = offsetBubble(placedCodex, awayFrom: claude, screen: codexPanel.screen) }
        }
        placeBubble(claudeBubble, rect: claude, visible: store.showBubble && store.claudeBubbleActivity != nil, owner: .claude)
        placeBubble(codexBubble, rect: codex, visible: store.showBubble && store.codexBubbleActivity != nil, owner: .codex)
    }

    private func bubbleRect(for anchor: NSWindow?, above: Bool) -> NSRect? {
        guard let anchor else { return nil }
        let frame = anchor.frame
        let visible = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let width: CGFloat = 360, height: CGFloat = 76
        let x = min(max(frame.midX - width / 2, visible.minX + 4), visible.maxX - width - 4)
        var y = above ? frame.maxY - 8 : frame.minY - height + 8
        if y + height > visible.maxY { y = frame.minY - height + 8 }
        if y < visible.minY { y = frame.maxY - 8 }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func offsetBubble(_ rect: NSRect, awayFrom other: NSRect, screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? rect
        let direction: CGFloat = rect.midX <= other.midX ? -1 : 1
        let x = min(max(rect.origin.x + direction * (rect.width + 10), visible.minX + 4), visible.maxX - rect.width - 4)
        return NSRect(x: x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    private func placeBubble(_ bubble: NSPanel?, rect: NSRect?, visible: Bool, owner: BubbleOwner) {
        guard let bubble, let rect, visible else { bubble?.orderOut(nil); return }
        if bubble.frame != rect { bubble.setFrame(rect, display: false) }
        if !bubble.isVisible {
            bubble.orderFrontRegardless()
            NotificationCenter.default.post(name: .bubbleRevealed(owner), object: nil)
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        PetStore.shared.shutdownBus()
        server.stop(); busServer.stop()
    }

    var windowVisible: Bool { panel?.isVisible ?? false }
    func toggleWindow() { PetStore.shared.userHidden.toggle() }

    /// Cada mascota se muestra u oculta por su cuenta segun la presencia de su herramienta (y lo que se oculto desde el menu).
    private func applyVisibility() {
        guard panel != nil, codexPanel != nil else { return }
        let v = PetStore.shared.visibility
        if v.claudeWindow != panel.isVisible { v.claudeWindow ? panel.orderFrontRegardless() : panel.orderOut(nil) }
        if v.codexWindow != codexPanel.isVisible { v.codexWindow ? codexPanel.orderFrontRegardless() : codexPanel.orderOut(nil) }
        updatePair()
        placeBubbles()
        placeStage()
    }
}

enum MenuIcon {
    enum Mode: Equatable { case idle, claude, codex, both }

    static func mode(claude: Bool, codex: Bool) -> Mode {
        switch (claude, codex) {
        case (true, true): .both
        case (true, false): .claude
        case (false, true): .codex
        case (false, false): .idle
        }
    }

    /// Icono plantilla para la barra: una mascota por herramienta; las dos juntas si colaboran.
    static func image(claude: Bool, codex: Bool) -> NSImage {
        let current = mode(claude: claude, codex: codex)
        let isPair = current == .both
        let size = NSSize(width: isPair ? 36 : 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            func claude(at origin: CGFloat) {
                for p in Sprite.pixels(.idle, tick: 0) where p.c != Pal.charcoal {
                    NSRect(x: origin + CGFloat(p.x) * 1.0, y: 1 + CGFloat(p.y) * 1.0, width: 1, height: 1).fill()
                }
            }
            func codex(at origin: CGFloat) {
                // Robot-nube de 12 x 15 con el visor recortado y su `>_`; celdas de 1 pt enteras para que quede nitido en pantallas retina.
                let rows = ["...111111...",
                            ".1111111111.",
                            "111111111111",
                            "11........11",
                            "11.1......11",
                            "11..1.....11",
                            "11.1..111.11",
                            "11........11",
                            ".1111111111.",
                            "..11111111..",
                            "...111111...",
                            "..11111111..",
                            "...111111...",
                            "...11..11...",
                            "...11..11..."]
                for (y, row) in rows.enumerated() {
                    for (x, cell) in row.enumerated() where cell == "1" {
                        NSRect(x: origin + CGFloat(x), y: 2 + CGFloat(y), width: 1, height: 1).fill()
                    }
                }
            }
            switch current {
            case .claude, .idle: claude(at: 1)
            case .codex: codex(at: 3)
            case .both:
                claude(at: 1)
                codex(at: 20)
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

@main
struct ClaudePetApp: App {
    init() {
        // `ClaudePet --trigger football|greet|cheer|concern`: avisa a la app abierta y sale, sin abrir otra mascota
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--trigger"), i + 1 < a.count {
            guard PetStore.triggerNames.contains(a[i + 1]) else {
                print("nombres validos: \(PetStore.triggerNames.joined(separator: ", "))"); exit(1)
            }
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("local.claudepet.trigger"), object: nil, userInfo: ["name": a[i + 1]], deliverImmediately: true)
            exit(0)
        }
        if let i = a.firstIndex(of: "--web-scout"), i + 1 < a.count {
            let action = a[i + 1]
            guard ["mark", "audit", "clear", "next", "previous"].contains(action) else {
                print("acciones válidas: mark, audit, clear, next, previous"); exit(1)
            }
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("local.claudepet.webscout"), object: nil, userInfo: ["action": action], deliverImmediately: true)
            exit(0)
        }
    }

    @NSApplicationDelegateAdaptor(AppController.self) private var controller
    @ObservedObject private var store = PetStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(store: store)
        } label: {
            Image(nsImage: MenuIcon.image(claude: store.claudePresent, codex: store.codexPresent))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("continuar en otro agente…") { AppController.shared.showRelay() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
