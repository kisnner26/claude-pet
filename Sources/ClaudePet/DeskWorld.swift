import SwiftUI
import AppKit

/// Escritorio vivo: decide donde esta cada mascota suelta en el escritorio segun lo que hace su agente y las ventanas que tienes abiertas.
/// - trabajando: se posa sobre el borde de la ventana del agente (y la acompana si la mueves);
/// - esperando un permiso: se asoma por detras de esa ventana;
/// - en calma: baja al suelo (encima del Dock);
/// - si arrastras una ventana encima de ella, se aparta.
/// El orden de ventanas lo pone el propio sistema (`order(.above/.below, relativeTo:)` funciona con ventanas de otras apps),
/// asi que cualquier ventana que pase por delante la tapa de verdad.
@MainActor
final class DeskWorld {
    static let shared = DeskWorld()

    /// Medidas del panel de la mascota: el sprite mide 96 sobre un panel de 112, con los pies a 8 del borde de abajo.
    static let feetOffset: CGFloat = 8
    static let centerAboveFeet: CGFloat = DeskMotion.size / 2 - feetOffset
    /// Cuanto queda por detras de la ventana cuando se asoma: solo la cabeza por encima del borde.
    static let peekDepth: CGFloat = 62

    struct Pet {
        var body = DeskPhysics.Body(x: 0, feetY: 0)
        var goal: DeskGoal = .rest
        var perchID: Int?
        var relX: CGFloat = 0
        var leap: DeskLeap?
        var lastBusy: TimeInterval = -1000
        var facing: CGFloat = 1
        var walking = false
        var needsInit = true
        var otherSpace = false
        var lastWindowFrame: CGRect?
    }

    struct Output {
        var center: CGPoint
        var walking: Bool
        var facing: CGFloat
        /// Ventana (id) respecto a la que hay que ordenar el panel y si va por encima; nil = flotando por encima de todo.
        var relativeTo: (id: Int, above: Bool)?
    }

    private let store = PetStore.shared
    private(set) var pets: [IslandAgentTab: Pet] = [:]
    private(set) var windows: [DeskWindow] = []
    private var windowsAt: TimeInterval = -10
    private var titlesAt: TimeInterval = -10
    private var titles: [Int: String] = [:]

    /// Las ventanas se releen unas 7 veces por segundo; los titulos (accesibilidad) cada par de segundos.
    private func refresh(now: TimeInterval) {
        guard now - windowsAt > 0.14 else { return }
        windowsAt = now
        var list = WindowCatalog.snapshot()
        if now - titlesAt > 2 {
            titlesAt = now
            titles = Dictionary(WindowCatalog.fillTitles(list).filter { !$0.title.isEmpty }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        }
        for i in list.indices where list[i].title.isEmpty { list[i].title = titles[list[i].id] ?? "" }
        windows = list
    }

    func reset(_ agent: IslandAgentTab) { pets[agent]?.needsInit = true }
    func forget(_ agent: IslandAgentTab) { pets[agent] = nil }

    private func screen(containing x: CGFloat) -> CGRect {
        let frames = NSScreen.screens.map(\.visibleFrame)
        return frames.first { $0.minX <= x && x <= $0.maxX } ?? frames.min { abs($0.midX - x) < abs($1.midX - x) } ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    func step(agent: IslandAgentTab, current center: CGPoint, dt: CGFloat, now: TimeInterval) -> Output {
        refresh(now: now)
        var pet = pets[agent] ?? Pet()
        if pet.needsInit {
            pet.body = DeskPhysics.Body(x: center.x, feetY: center.y - Self.centerAboveFeet)
            pet.needsInit = false; pet.leap = nil; pet.perchID = nil; pet.goal = .rest
        }

        // lo que hace el agente
        let state = agent == .claude ? store.state : store.codexState
        let waiting = state == .waiting || (agent == .claude && !store.permissionAsks.isEmpty)
        let effective: PetState = waiting ? .waiting : state
        if effective == .thinking || effective == .tool || effective == .starting || effective == .waiting { pet.lastBusy = now }
        let hostIndex = WindowCatalog.agentWindow(project: store.terminalProject, in: windows)
        let goal = DeskGoal.decide(state: effective, hasWindow: hostIndex != nil, secondsSinceBusy: now - pet.lastBusy)
        pet.otherSpace = hostIndex == nil && effective != .idle

        let screenFrame = screen(containing: pet.body.x)
        let floorY = screenFrame.minY
        let both = store.codexPresent
        var out = Output(center: center, walking: false, facing: pet.facing, relativeTo: nil)

        // el punto al que quiere ir
        var target: CGPoint
        var targetWindow: DeskWindow?
        switch goal {
        case .perch, .peek:
            let host = windows[hostIndex!]
            targetWindow = host
            let visible = DeskGeo.visibleTop(of: hostIndex!, in: windows)
            let preferred = host.frame.minX + host.frame.width * DeskGoal.perchFraction(claude: agent == .claude, both: both)
                + DeskGoal.pace(time: now + (agent == .codex ? 2.5 : 0), working: effective == .tool || effective == .thinking)
            if let x = DeskGeo.nearest(preferred, in: visible, margin: 44) {
                target = CGPoint(x: x, y: host.frame.maxY - (goal == .peek ? Self.peekDepth : 0))
            } else {
                // el borde esta tapado del todo por otras ventanas: no hay donde posarse
                targetWindow = nil
                target = CGPoint(x: pet.body.x, y: floorY)
            }
        case .rest:
            let side = agent == .claude ? 0.0 : 130.0
            target = CGPoint(x: screenFrame.maxX - 150 - side, y: floorY)
        }
        let effectiveGoal: DeskGoal = targetWindow == nil && goal != .rest ? .rest : goal

        // cambio de ventana o de nivel: salta
        let perchChanged = pet.perchID != targetWindow?.id || pet.goal != effectiveGoal
        let height = abs(target.y - pet.body.feetY)
        if perchChanged, pet.leap == nil, height > 28 || (pet.perchID != targetWindow?.id) {
            pet.leap = DeskLeap.make(from: CGPoint(x: pet.body.x, y: pet.body.feetY), to: target, now: now)
            pet.perchID = targetWindow?.id
            pet.goal = effectiveGoal
        } else if perchChanged {
            pet.perchID = targetWindow?.id; pet.goal = effectiveGoal
        }

        if let leap = pet.leap {
            let r = leap.position(at: now)
            let dx = r.point.x - pet.body.x
            pet.body.x = r.point.x; pet.body.feetY = r.point.y; pet.body.vy = 0
            pet.walking = false
            if abs(dx) > 0.5 { pet.facing = dx > 0 ? 1 : -1 }
            if r.done {
                pet.leap = nil
                if let w = targetWindow { pet.relX = pet.body.x - w.frame.minX }
            } else {
                // el destino se mueve si la ventana se mueve: se apunta de nuevo
                pet.leap?.to = target
            }
        } else if let w = targetWindow {
            // sobre la ventana: la acompana, y camina por su borde hacia donde le toca
            let wantRel = target.x - w.frame.minX
            let r = DeskPhysics.walk(x: pet.relX, toward: wantRel, dt: dt, speed: 160)
            pet.relX = r.x; pet.walking = r.walking
            if r.walking { pet.facing = r.facing }
            pet.body.x = w.frame.minX + pet.relX
            pet.body.feetY = target.y
            pet.body.vy = 0
            pet.lastWindowFrame = w.frame
        } else {
            // en el suelo: se aparta de lo que le cae encima y, si no, va a su sitio de descanso
            var goalX = target.x
            var speed: CGFloat = 130
            if let away = DeskPhysics.sidestep(centerX: pet.body.x, feetY: pet.body.feetY, height: 96, windows: windows, supporting: nil) { goalX = away; speed = 300 }
            let r = DeskPhysics.walk(x: pet.body.x, toward: goalX, dt: dt, speed: speed)
            pet.body.x = r.x; pet.walking = r.walking
            if r.walking { pet.facing = r.facing }
            // cae o sube segun lo que haya bajo sus pies (una ventana que se arrastra por debajo la sostiene)
            let ground = DeskPhysics.support(centerX: pet.body.x, feetY: pet.body.feetY, windows: windows, floorY: floorY).y
            pet.body = DeskPhysics.settle(pet.body, ground: ground, dt: dt)
        }

        // dentro de alguna pantalla (a lo ancho; en vertical la manda la fisica)
        let frames = NSScreen.screens.map(\.visibleFrame)
        if let f = frames.first(where: { $0.minX - 20 <= pet.body.x && pet.body.x <= $0.maxX + 20 }) ?? frames.first {
            pet.body.x = min(max(pet.body.x, f.minX + 40), f.maxX - 40)
        }

        out.center = CGPoint(x: pet.body.x, y: pet.body.feetY + Self.centerAboveFeet)
        out.walking = pet.walking || pet.leap != nil
        out.facing = pet.facing
        if let w = targetWindow, pet.goal != .rest { out.relativeTo = (w.id, pet.goal != .peek) }
        pets[agent] = pet
        return out
    }
}
