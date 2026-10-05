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
    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        dragged = false
        grab = NSEvent.mouseLocation - (window?.frame.origin ?? .zero)
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if abs(p.x - downAt.x) > 3 || abs(p.y - downAt.y) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(p - grab) }
    }
    /// Un clic (sin arrastre) abre la app de Claude.
    override func mouseUp(with event: NSEvent) {
        guard !dragged else { return }
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
    private var cancellables = Set<AnyCancellable>()
    private let server = EventServer()
    private let busServer = EventServer(path: PetBus.ownSocket)

    func applicationDidFinishLaunching(_ n: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-hero"), i + 1 < CommandLine.arguments.count {
            HeroSnapshot.run(into: CommandLine.arguments[i + 1]); exit(0)
        }
        if CommandLine.arguments.contains("--selftest-safety") { exit(SafetySelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-football") { exit(FootballSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-football"), i + 1 < CommandLine.arguments.count {
            snapshotFootball(to: CommandLine.arguments[i + 1]); exit(0)
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
        p.orderFrontRegardless()
        panel = p
        setUpBubble()
        setUpStage()

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

    /// Fotogramas del partido (normal arriba, reducir movimiento abajo), con escenario y sprite de Claude.
    private func snapshotFootball(to path: String) {
        let times: [Double] = [0.6, 2.0, 3.0, 3.8, 4.8, 6.4, 7.3, 8.4, 9.0, 10.3, 11.2]
        func cell(_ tm: Double, _ reduce: Bool) -> some View {
            ZStack(alignment: .topLeading) {
                Canvas { gc, _ in
                    let u: CGFloat = 7
                    let g = FootballChoreography.frame(elapsed: tm, reduceMotion: reduce)
                    let cue = PeerCue(state: .idle, greet: false, cheer: false, concern: false, game: g)
                    for p in Sprite.pixels(.idle, tick: Int(tm * 8), cue: cue) {
                        gc.fill(Path(CGRect(x: StageMetrics.petX + CGFloat(p.x) * u, y: StageMetrics.petY + CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c))
                    }
                    var g2 = gc
                    StageRenderer.draw(&g2, elapsed: tm, reduceMotion: reduce, mirrored: false)
                }
            }.frame(width: StageMetrics.width, height: StageMetrics.height).background(Pal.charcoal)
        }
        let view = VStack(spacing: 2) {
            ForEach([false, true], id: \.self) { reduce in
                HStack(spacing: 2) { ForEach(times.prefix(6), id: \.self) { cell($0, reduce) } }
                HStack(spacing: 2) { ForEach(times.suffix(5), id: \.self) { cell($0, reduce) } }
            }
        }.background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
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

    /// Escenario del partido: ventana aparte, transparente y sin raton, pegada a la mascota.
    private func setUpStage() {
        let st = PetPanel(contentRect: NSRect(x: 0, y: 0, width: StageMetrics.width, height: StageMetrics.height),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        st.contentView = NSHostingView(rootView: StageView(store: PetStore.shared))
        st.isOpaque = false
        st.backgroundColor = .clear
        st.hasShadow = false
        st.ignoresMouseEvents = true
        st.level = .statusBar
        st.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        stage = st
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in Task { @MainActor in self?.placeStage() } }
        PetStore.shared.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.placeStage() } }.store(in: &cancellables)
    }

    private func placeStage() {
        guard PetStore.shared.gameActive, panel.isVisible else { stage.orderOut(nil); return }
        let pf = panel.frame
        let vis = (panel.screen ?? NSScreen.main)?.visibleFrame ?? pf
        // el avatar entra por la izquierda; si no hay sitio, la escena se refleja hacia la derecha
        let mirrored = pf.minX - StageMetrics.leftReach < vis.minX
        if PetStore.shared.stageMirrored != mirrored { PetStore.shared.stageMirrored = mirrored }
        let x = mirrored ? pf.minX : pf.minX - StageMetrics.leftReach
        stage.setFrameOrigin(NSPoint(x: x, y: pf.minY - 8))
        if !stage.isVisible { stage.orderFrontRegardless() }
    }

    private func placeBubble() {
        let store = PetStore.shared
        guard store.showBubble, store.activity != nil, panel.isVisible else { bubble.orderOut(nil); return }
        let pf = panel.frame
        let vis = (panel.screen ?? NSScreen.main)?.visibleFrame ?? pf
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
    func toggleWindow() { windowVisible ? panel.orderOut(nil) : panel.orderFrontRegardless(); placeBubble() }
}

enum MenuIcon {
    /// Silueta del bloque en 18x18 como imagen plantilla (se adapta a barra clara/oscura).
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            for p in Sprite.pixels(.idle, tick: 0) where p.c != Pal.charcoal {
                NSRect(x: CGFloat(p.x) * 1.125, y: CGFloat(p.y) * 1.125, width: 1.125, height: 1.125).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }()
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
            Text(store.peer.map { "Pet bus: \($0.id) presente" } ?? (store.busOK ? "Pet bus: sin otras mascotas" : "Pet bus caido"))
            if let warning = store.safetyAlert { Text(warning.title) }
            if store.reviewReady { Button("codex listo para revision: abrir diff") { store.openReview() } }
            Toggle("Mostrar burbuja de actividad", isOn: $store.showBubble)
            Toggle("Detalle en la burbuja (archivos, comandos)", isOn: $store.showDetail)
            Toggle("Avisar si claude o codex parecen bloqueados", isOn: $store.stallWatch)
            Toggle("Bloquear herramientas si el proyecto cambia", isOn: $store.blockOnChange)
            Toggle("Compartir nombre del proyecto con otras mascotas", isOn: $store.shareProject)
            Divider()
            Button("Mostrar u ocultar mascota") { AppController.shared.toggleWindow() }
            Menu("Animaciones") {
                Toggle("Activar animaciones", isOn: $store.animationsEnabled)
                Toggle("Partido automatico con Codex", isOn: $store.footballEnabled)
                    .disabled(!store.animationsEnabled)
                Divider()
                Button("Partido de futbol ahora") { store.trigger("football") }
                Button("Saludo") { store.trigger("greet") }
                Button("Celebracion del par") { store.trigger("cheer") }
                Button("Preocupacion") { store.trigger("concern") }
            }
            Picker("Aspecto", selection: $store.skin) {
                ForEach(Skin.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Menu("Probar estado") {
                ForEach(PetState.allCases, id: \.self) { s in
                    Button(s.label.capitalized) { store.preview(s) }
                }
            }
            Divider()
            Button("Salir") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: MenuIcon.image)
        }
    }
}
