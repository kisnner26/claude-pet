import SwiftUI
import AppKit

/// La mascota suelta por el escritorio: se arrastra fuera de la isla, se queda donde la sueltas, y si quieres sigue al cursor.
/// Lo que decide (movimiento, limites, persistencia, cuando vuelve a la isla) es puro y se prueba aparte.
enum DeskMotion {
    static let size: CGFloat = 112
    /// Distancia del cursor a partir de la cual la mascota echa a andar, y a la que se detiene.
    static let startFollowing: CGFloat = 230, stopFollowing: CGFloat = 150
    static let speed: CGFloat = 340

    /// Siguiente centro de la mascota: va hacia el cursor sin llegar a taparlo, con aceleracion suave y sin pasarse.
    static func follow(from p: CGPoint, mouse: CGPoint, dt: CGFloat, moving: Bool) -> (point: CGPoint, moving: Bool) {
        let dx = mouse.x - p.x, dy = mouse.y - p.y, d = hypot(dx, dy)
        let go = moving ? d > stopFollowing : d > startFollowing
        guard go, d > 0.5 else { return (p, false) }
        let remaining = d - stopFollowing
        let step = min(speed * dt, max(0, remaining) * min(1, 6 * dt) + 1)
        return (CGPoint(x: p.x + dx / d * step, y: p.y + dy / d * step), true)
    }

    /// Mantiene el centro dentro de alguna pantalla (zona visible); si esta fuera de todas, la lleva a la mas cercana.
    static func clamp(_ p: CGPoint, in frames: [CGRect], half: CGFloat = size / 2) -> CGPoint {
        guard !frames.isEmpty else { return p }
        func fit(_ f: CGRect) -> CGPoint { CGPoint(x: min(max(p.x, f.minX + half), f.maxX - half), y: min(max(p.y, f.minY + half), f.maxY - half)) }
        if let inside = frames.first(where: { $0.insetBy(dx: half, dy: half).contains(p) }) { _ = inside; return p }
        return frames.map(fit).min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }!
    }

    /// Soltarla sobre la zona de la isla (arriba y al centro de una pantalla) la devuelve a la isla.
    static func returnsToIsland(_ p: CGPoint, screens: [CGRect]) -> Bool {
        screens.contains { f in abs(p.x - f.midX) < 150 && p.y > f.maxY - 90 }
    }

    /// Posiciones guardadas: `{"claude":[x,y],"codex":[x,y]}`. Lo raro se descarta.
    static func encode(_ spots: [String: CGPoint]) -> String {
        let obj = spots.mapValues { [Double($0.x), Double($0.y)] }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func decode(_ text: String) -> [String: CGPoint] {
        guard text.utf8.count < 400, let d = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [Double]] else { return [:] }
        var out: [String: CGPoint] = [:]
        for (k, v) in obj where ["claude", "codex"].contains(k) && v.count == 2 && v.allSatisfy({ $0.isFinite && abs($0) < 100_000 }) { out[k] = CGPoint(x: v[0], y: v[1]) }
        return out
    }
}

@MainActor
final class DesktopPets {
    static let shared = DesktopPets()
    private var panels: [IslandAgentTab: NSPanel] = [:]
    private var models: [IslandAgentTab: IslandModel] = [:]
    private var carried: Set<IslandAgentTab> = []
    private var moving: Set<IslandAgentTab> = []
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private let store = PetStore.shared

    var out: Set<IslandAgentTab> { Set(panels.keys) }
    private var screens: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    /// Al arrancar: las que se dejaron fuera vuelven a su sitio.
    func restore() {
        for (k, p) in DeskMotion.decode(store.deskSpots) {
            guard let agent = IslandAgentTab(rawValue: k) else { continue }
            show(agent, at: DeskMotion.clamp(p, in: screens))
        }
        if store.deskWorld { showWorldPets() }
    }

    /// Enciende o apaga el escritorio vivo: encendido, las mascotas salen a tus ventanas; apagado, vuelven a la isla.
    func setWorld(_ on: Bool) {
        store.deskWorld = on
        if on { showWorldPets() } else { putBackAll(); FileFlights.shared.stop(); for a in IslandAgentTab.allCases { DeskWorld.shared.forget(a) } }
    }

    private func showWorldPets() {
        for agent in IslandAgentTab.allCases where panels[agent] == nil && (agent == .claude || store.codexPresent) { show(agent) }
    }

    /// La coge de la isla: aparece bajo el cursor y la lleva mientras el boton siga pulsado.
    func pickUp(_ agent: IslandAgentTab) {
        guard panels[agent] == nil else { return }
        show(agent, at: NSEvent.mouseLocation)
        carried.insert(agent)
    }

    /// Desde ajustes: la saca en una esquina libre de la pantalla principal, junto a donde la dejaron si ya estuvo fuera.
    func show(_ agent: IslandAgentTab) {
        guard panels[agent] == nil else { return }
        let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let saved = DeskMotion.decode(store.deskSpots)[agent.rawValue]
        show(agent, at: DeskMotion.clamp(saved ?? CGPoint(x: f.maxX - 120 - (agent == .codex ? 130 : 0), y: f.minY + 120), in: screens))
    }

    func putBack(_ agent: IslandAgentTab) {
        panels[agent]?.orderOut(nil); panels[agent] = nil; models[agent] = nil; carried.remove(agent); moving.remove(agent)
        store.deskOut = out; saveSpots(); stopTimerIfIdle()
    }

    func putBackAll() { for a in out { putBack(a) } }

    private func show(_ agent: IslandAgentTab, at center: CGPoint) {
        let model = IslandModel()
        model.mode = .expanded
        model.onRage = { a in Task { @MainActor in RageController.shared.start(agent: a, store: PetStore.shared) } }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: DeskMotion.size, height: DeskMotion.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.contentView = FirstMouseHostingView(rootView: DesktopPetView(agent: agent, store: store, model: model, onDrag: { [weak self] in self?.dragBegan(agent) },
                                                                            onDrop: { [weak self] in self?.dragEnded(agent) }, onBack: { [weak self] in if self?.store.deskWorld == true { self?.setWorld(false) } else { self?.putBack(agent) } }, onFocus: { DeskWorld.shared.focusHost() }))
        panel.setFrameOrigin(NSPoint(x: center.x - DeskMotion.size / 2, y: center.y - DeskMotion.size / 2))
        panel.orderFrontRegardless()
        panels[agent] = panel; models[agent] = model
        store.deskOut = out
        startTimer()
    }

    /// Para las pruebas en vivo: donde esta cada panel y su numero de ventana.
    func debugPanels() -> [(agent: IslandAgentTab, frame: CGRect, level: Int, number: Int)] {
        panels.map { ($0.key, $0.value.frame, $0.value.level.rawValue, $0.value.windowNumber) }.sorted { $0.agent.rawValue < $1.agent.rawValue }
    }

    private var lastOrder: [IslandAgentTab: (id: Int, above: Bool, at: TimeInterval)] = [:]

    /// Posada o asomada: la mascota pasa a ser una ventana normal colocada justo encima (o detras) de la del agente, y el sistema se
    /// encarga de taparla con lo que pase por delante. En el suelo vuelve a flotar sobre todo.
    private func applyOrder(_ agent: IslandAgentTab, _ panel: NSPanel, _ rel: (id: Int, above: Bool)?, now: TimeInterval) {
        guard let rel else {
            if panel.level != .floating { panel.level = .floating; panel.orderFrontRegardless() }
            lastOrder[agent] = nil
            return
        }
        if panel.level != .normal { panel.level = .normal }
        let last = lastOrder[agent]
        // se vuelve a ordenar si cambia la ventana o la relacion, y unas cuatro veces por segundo por si la ventana sube o baja
        if last == nil || last!.id != rel.id || last!.above != rel.above || now - last!.at > 0.25 {
            panel.order(rel.above ? .above : .below, relativeTo: rel.id)
            lastOrder[agent] = (rel.id, rel.above, now)
        }
    }

    private func dragBegan(_ agent: IslandAgentTab) { carried.insert(agent) }

    private func dragEnded(_ agent: IslandAgentTab) {
        carried.remove(agent)
        guard let panel = panels[agent] else { return }
        let c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if DeskMotion.returnsToIsland(c, screens: NSScreen.screens.map(\.frame)) { putBack(agent) } else { saveSpots() }
    }

    private func saveSpots() {
        var spots: [String: CGPoint] = [:]
        for (a, p) in panels { spots[a.rawValue] = CGPoint(x: p.frame.midX, y: p.frame.midY) }
        store.deskSpots = DeskMotion.encode(spots)
    }

    private var timerFast = true

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        schedule(fast: true)
    }

    private func schedule(fast: Bool) {
        timer?.invalidate()
        timerFast = fast
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 30.0 : 1.0 / 10.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    private func stopTimerIfIdle() { if panels.isEmpty { timer?.invalidate(); timer = nil } }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(0.1, now - lastTick)); lastTick = now
        let mouse = NSEvent.mouseLocation
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if store.deskWorld, store.codexPresent, panels[.codex] == nil { showWorldPets() }
        for (agent, panel) in panels {
            guard let model = models[agent] else { continue }
            var c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            if carried.contains(agent) {
                if buttonDown { c = mouse } else { dragEnded(agent) }
                if store.deskWorld { DeskWorld.shared.reset(agent) }       // al soltarla cae desde donde la sueltes
            } else if store.deskWorld {
                let r = DeskWorld.shared.step(agent: agent, current: c, dt: dt, now: now)
                c = r.center
                if r.walking { moving.insert(agent) } else { moving.remove(agent) }
                if r.walking, model.deskFlip != (r.facing < 0) { model.deskFlip = r.facing < 0 }
                applyOrder(agent, panel, r.relativeTo, now: now)
            } else if store.deskFollow {
                let r = DeskMotion.follow(from: c, mouse: mouse, dt: dt, moving: moving.contains(agent))
                c = r.point
                if r.moving { moving.insert(agent) } else { moving.remove(agent) }
            }
            // un saltito al andar: se nota que camina
            let bob: CGFloat = moving.contains(agent) ? abs(sin(CGFloat(now) * 11)) * 7 : 0
            if !store.deskWorld || carried.contains(agent) { c = DeskMotion.clamp(c, in: screens) }
            panel.setFrameOrigin(NSPoint(x: c.x - DeskMotion.size / 2, y: c.y - DeskMotion.size / 2 + bob))
            // la mirada sigue al cursor
            let dx = max(-1, min(1, (mouse.x - c.x) / 400)), dy = max(-1, min(1, (c.y - mouse.y) / 400))
            let g = CGPoint(x: dx, y: dy)
            if model.gaze != g { model.gaze = g }
            model.idleSeconds = store.idleForDesk
        }
        if store.deskWorld {
            // quieta del todo (nadie camina, salta, la llevan en la mano ni hay un archivo volando) basta con 10 Hz
            let calm = moving.isEmpty && carried.isEmpty && !DeskWorld.shared.anyLeaping && !FileFlights.shared.isBusy && !GhostCursor.shared.isBusy
            if calm == timerFast { schedule(fast: !calm) }
            let animated = store.animationsEnabled && !store.reduceMotion
            DeskWorld.shared.updateGlow(animated: animated)
            FileFlights.shared.tick(now: now, store: store, centers: Dictionary(uniqueKeysWithValues: panels.map { ($0.key, CGPoint(x: $0.value.frame.midX, y: $0.value.frame.midY)) }),
                                    windows: DeskWorld.shared.windows, animated: animated)
            GhostCursor.shared.tick(now: now)
            DeskNotes.shared.update(notes: DeskWorld.shared.noteWanted, centers: Dictionary(uniqueKeysWithValues: panels.map { ($0.key, CGPoint(x: $0.value.frame.midX, y: $0.value.frame.midY)) }))
        }
    }
}

struct DesktopPetView: View {
    let agent: IslandAgentTab
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    var onDrag: () -> Void
    var onDrop: () -> Void
    var onBack: () -> Void
    var onFocus: () -> Void = {}
    @State private var dragging = false

    var body: some View {
        Group {
            if agent == .claude { PetFace(store: store, model: model) } else { CodexMini(store: store, model: model, greet: false) }
        }
        .frame(width: DeskMotion.size * 0.86, height: DeskMotion.size * 0.86)
        .scaleEffect(x: model.deskFlip ? -1 : 1, y: 1)
        // salir y volver a la isla: giro y tamano desde el centro, y el aplastado al caer desde los pies
        .scaleEffect(x: 1 + model.deskSquash, y: 1 - model.deskSquash, anchor: .bottom)
        .rotationEffect(.degrees(model.deskSpin))
        .scaleEffect(model.deskScale)
        .opacity(model.deskAlpha)
        .frame(width: DeskMotion.size, height: DeskMotion.size)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if store.deskWorld { onFocus() } else { onBack() } }
        .onTapGesture { if agent == .claude { model.poke() } else { model.pokeCodex() } }
        .onHover { model.petHoverSince = $0 ? ProcessInfo.processInfo.systemUptime : nil }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in if !dragging { dragging = true; onDrag() } }
            .onEnded { _ in dragging = false })
        .contextMenu {
            if store.deskWorld { Button("ir a la ventana del agente", systemImage: "macwindow") { onFocus() } }
            Button("volver a la isla", systemImage: "arrow.uturn.backward") { onBack() }
            Toggle("seguir el cursor", isOn: $store.deskFollow)
            Divider()
            ForEach(Outfit.allCases) { outfit in
                let who: PetAgent = agent == .claude ? .claude : .codex
                let unlocked = Evolution.isUnlocked(outfit, level: store.weeklyRecap.level)
                Toggle(unlocked ? outfit.title : "\(outfit.title) · nivel \(Evolution.unlockLevel(outfit))", isOn: Binding(get: { store.worn(outfit, by: who) }, set: { _ in store.toggleOutfit(outfit, for: who) })).disabled(!unlocked)
            }
        }
        .accessibilityLabel(store.deskWorld ? "\(agent.rawValue) en el escritorio vivo: arrástrala o toca dos veces para ir a la ventana del agente" : "\(agent.rawValue) en el escritorio: arrástrala, toca dos veces para volver a la isla")
    }
}
