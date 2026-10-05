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
    var onClick: (() -> Void)?
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
        if let onClick { onClick(); return }
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
    private var bubble: NSPanel!
    private var stage: NSPanel!
    private var codexPanel: PetPanel!
    private var presence: AppPresence?
    private var cancellables = Set<AnyCancellable>()
    private let server = EventServer()
    private let busServer = EventServer(path: PetBus.ownSocket)

    func applicationDidFinishLaunching(_ n: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-hero"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.run(into: CommandLine.arguments[i + 1]); exit(0)
        }
        if CommandLine.arguments.contains("--selftest-safety") { exit(SafetySelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-mission") { exit(MissionSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-companion") { exit(CompanionSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-football") { exit(FootballSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-football"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.footballSheet(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1]); exit(0)
        }
        NSApp.setActivationPolicy(.accessory)

        let host = DragHostingView(rootView: PetView(store: PetStore.shared))
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
        setUpBubble()
        setUpCodexWindow()
        setUpStage()
        PetStore.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.applyVisibility() } }.store(in: &cancellables)
        let watcher = AppPresence { claude, codex in PetStore.shared.setApps(claude: claude, codex: codex) }
        presence = watcher
        watcher.start()
        applyVisibility()

        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.claudepet.trigger"), object: nil, queue: .main) { n in
            guard let name = n.userInfo?["name"] as? String else { return }
            Task { @MainActor in if PetStore.triggerNames.contains(name) { PetStore.shared.trigger(name) } }
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

    /// Burbuja de actividad: ventana aparte que no captura el raton y sigue a la mascota.
    private func setUpBubble() {
        let b = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 76),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        b.contentView = NSHostingView(rootView: BubbleView(store: PetStore.shared))
        b.isOpaque = false
        b.backgroundColor = .clear
        b.hasShadow = false
        b.ignoresMouseEvents = true
        b.level = .statusBar
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        bubble = b
        let refresh: () -> Void = { [weak self] in self?.placeBubble() }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in refresh() }
        PetStore.shared.objectWillChange.sink { DispatchQueue.main.async { refresh() } }.store(in: &cancellables)
        placeBubble()
    }

    /// Ventana de Codex: una entidad independiente de la de Claude (su propia posicion, su propio arrastre, su propio clic).
    private func setUpCodexWindow() {
        let host = DragHostingView(rootView: CodexPetView(store: PetStore.shared))
        host.onClick = {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppPresence.codexBundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
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

    private func windowsMoved() { updatePair(); placeStage(); placeBubble() }

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
    }

    private func placeStage() {
        let store = PetStore.shared
        guard !store.userHidden, (store.gameActive || store.collaborationActive || store.hugActive), let geo = store.gameGeometry else { stage.orderOut(nil); return }
        if stage.frame != geo.stageFrame { stage.setFrame(geo.stageFrame, display: false) }
        if !stage.isVisible { stage.orderFrontRegardless() }
    }

    private func placeBubble() {
        let store = PetStore.shared
        let anchor = store.bubbleFollowsCodex ? codexPanel : panel
        guard store.showBubble, store.bubbleActivity != nil, anchor?.isVisible == true, let anchor else { bubble.orderOut(nil); return }
        let pf = anchor.frame
        let vis = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? pf
        var x = pf.midX - 180
        x = min(max(x, vis.minX + 4), vis.maxX - 364)
        // encima de la mascota; si no cabe, debajo
        var y = pf.maxY - 8
        if y + 76 > vis.maxY { y = pf.minY - 68 }
        bubble.setFrameOrigin(NSPoint(x: x, y: y))
        if !bubble.isVisible { bubble.orderFrontRegardless() }
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
        placeBubble()
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
    }

    @NSApplicationDelegateAdaptor(AppController.self) private var controller
    @ObservedObject private var store = PetStore.shared

    var body: some Scene {
        MenuBarExtra {
            Text("Estado: \(store.state.label.capitalized)")
            Text(store.bridgeOK ? "Puente local activo" : "Puente local caido")
            Text(store.claudePresent ? "Claude Code: en uso" : "Claude Code: sin usar")
            Text(store.codexPresent ? "Codex: en uso" : "Codex: sin usar")
            Toggle("Mostrar cada mascota solo cuando uso su herramienta", isOn: $store.autoVisibility)
            Text(store.peer.map { "Pet bus: \($0.id) presente" } ?? (store.busOK ? "Pet bus: sin otras mascotas" : "Pet bus caido"))
            Menu("panel de codex") { CodexControlMenu(store: store) }
            if let warning = store.safetyAlert { Text(warning.title) }
            if store.reviewReady { Button("codex listo para revision: abrir diff") { store.openReview() } }
            Menu("mission control") { MissionControlMenu(control: store.mission) }
            Toggle("Mostrar burbuja de actividad (ambas)", isOn: $store.showBubble)
            Toggle("Detalle en la burbuja de Claude (archivos, comandos)", isOn: $store.showDetail)
            Toggle("Avisar si claude o codex parecen bloqueados", isOn: $store.stallWatch)
            Toggle("Bloquear herramientas de Claude si el proyecto cambia", isOn: $store.blockOnChange)
            Toggle("Compartir nombre del proyecto de Claude", isOn: $store.shareProject)
            Divider()
            Button("Mostrar u ocultar mascotas") { AppController.shared.toggleWindow() }
            Menu("Animaciones") {
                Toggle("Activar animaciones (ambas)", isOn: $store.animationsEnabled)
                Toggle("Partido automatico con Codex", isOn: $store.footballEnabled)
                    .disabled(!store.animationsEnabled)
                Divider()
                Button("Partido de futbol ahora") { store.trigger("football") }
                    .disabled(!store.pairNear)
                Menu("Acciones de Claude") {
                    Button("Saludo") { store.trigger("greet") }
                    Button("Celebracion") { store.trigger("cheer") }
                    Button("Preocupacion") { store.trigger("concern") }
                }
                Menu("Acciones de Codex") {
                    ForEach(CodexGesture.allCases, id: \.self) { gesture in
                        Button(gesture.title) { store.triggerCodex(gesture) }
                    }
                }
            }
            Menu("Aspecto") {
                Picker("Claude", selection: $store.skin) {
                    ForEach(Skin.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Codex", selection: $store.codexSkin) {
                    ForEach(CodexSkin.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Menu("Probar estado") {
                Menu("Claude") {
                    ForEach(PetState.allCases, id: \.self) { s in
                        Button(s.label.capitalized) { store.preview(s) }
                    }
                }
                Menu("Codex") {
                    ForEach(PetState.allCases, id: \.self) { s in
                        Button(s.label.capitalized) { store.previewCodex(s) }
                    }
                }
            }
            Divider()
            Button("Salir") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: MenuIcon.image(claude: store.claudePresent, codex: store.codexPresent))
        }
    }
}
