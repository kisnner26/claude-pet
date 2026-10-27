import SwiftUI

struct PetFace: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel

    @ViewBuilder var body: some View {
        if model.mode == .hidden {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let now = ProcessInfo.processInfo.systemUptime
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            let scene = Self.makeScene(model: model, store: store)
            let pose = PetAnimator.pose(at: now, gaze: model.gaze, pokes: model.pokes, hopStart: model.hopStart, motion: motion, hover: model.hover, scene: scene)
            Canvas { gc, size in
                var cue = store.cue(at: ctx.date)
                if model.greetUntil > now { cue = (cue ?? PeerCue(state: store.state, greet: false, cheer: false, concern: false)); cue?.greet = true }
                // un archivo encima o recien soltado: la mascota es una caja
                if model.dropHover || model.swallowStart.map({ now - $0 < 0.7 }) == true {
                    var box = PetPose()
                    if let s = model.swallowStart, now - s < 0.7 { box.dx = CGFloat(sin((now - s) * 40)) * 0.5; box.scaleY = 0.96 }
                    PetFace.draw(&gc, size: size, pixels: FileDrop.boxPixels(open: model.dropHover), pose: box)
                    return
                }
                var px = Sprite.pixels(store.state, tick: tick, cue: cue)
                if Sprite.skin == .block { px = Wardrobe.compose(px, outfits: store.outfitsNow(at: ctx.date), state: store.state, tick: tick) }
                if store.state != .error { px = PetAnimator.apply(px, pose: pose) }
                // las particulas no siguen al cuerpo: se dibujan antes de moverlo
                var overlay = gc
                PetFace.draw(&gc, size: size, pixels: px, pose: pose)
                if motion { PetFace.draw(&overlay, size: size, pixels: PetAnimator.particles(at: now, pose: pose, scene: scene), pose: PetPose()) }
            }
            }
        }
    }

    /// Momentos que cambian la pose: la entrada al abrir, tu decision sobre un permiso y la espera de uno pendiente.
    static func makeScene(model: IslandModel, store: PetStore) -> PetScene {
        var scene = PetScene(idleSeconds: model.idleSeconds, state: store.state, confettiStart: model.confettiStart, dancing: model.dancing && store.danceToMusic)
        addMoments(to: &scene, model: model, store: store, now: 0)
        return scene
    }

    static func addMoments(to scene: inout PetScene, model: IslandModel, store: PetStore, now: TimeInterval) {
        scene.openedAt = model.expandStart
        if let d = store.lastDecision { scene.decisionAllow = d.allow; scene.decisionAt = d.at }
        if let ask = store.permissionAsks.first { scene.waitingFor = Date().timeIntervalSince(ask.at) }
    }

    static func draw(_ gc: inout GraphicsContext, size: CGSize, pixels: [Px], pose: PetPose) {
        let u = size.width / 16
        gc.translateBy(x: size.width / 2 + pose.dx * u, y: size.height + pose.dy * u)
        gc.rotate(by: .degrees(pose.rotation))
        gc.scaleBy(x: pose.scaleX, y: pose.scaleY)
        gc.translateBy(x: -size.width / 2, y: -size.height)
        for p in pixels { gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u + 0.5, height: u + 0.5)), with: .color(p.c)) }
    }
}

struct CodexMini: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
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
    @ViewBuilder var body: some View {
        if model.mode == .hidden {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            let legs: CodexAvatar.Legs = motion && tick % 8 < 4 ? .step : .stand
            // la misma vida que claude: respira, se inclina al cursor, se estira, bosteza y saluda con la mano
            let pose = motion ? PetAnimator.pose(at: ProcessInfo.processInfo.systemUptime, gaze: model.gaze, pokes: model.codexPokes, hopStart: model.codexDoneAt, motion: true,
                                                 scene: { var sc = PetScene(idleSeconds: model.idleSeconds, state: store.codexState); PetFace.addMoments(to: &sc, model: model, store: store, now: 0); return sc }()) : PetPose()
            CodexMiniFrame(face: pose.yawn ? .happy : face(tick), legs: legs, tick: tick, skin: store.codexSkin, wave: (greet || pose.earLift) && motion, pose: pose)
            }
        }
    }
}

struct CodexMiniFrame: View {
    let face: CodexAvatar.Face
    let legs: CodexAvatar.Legs
    let tick: Int
    let skin: CodexSkin
    let wave: Bool
    var pose = PetPose()
    var body: some View {
        Canvas { gc, size in
            let u = min(size.width / 18, size.height / 21)
            let ox = (size.width - 18 * u) / 2
            let oy = (size.height - 21 * u) / 2
            // la pose mueve el cuerpo entero desde los pies, igual que con claude
            gc.translateBy(x: size.width / 2 + pose.dx * u, y: oy + 21 * u + pose.dy * u)
            gc.rotate(by: .degrees(pose.rotation))
            gc.scaleBy(x: pose.scaleX, y: pose.scaleY)
            gc.translateBy(x: -size.width / 2, y: -(oy + 21 * u))
            for c in CodexAvatar.cells(legs: legs, face: face, skin: skin) {
                gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
            }
            if wave { for c in CodexAvatar.armCells(.wave(tick % 8 < 4), skin: skin) { gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c)) } }
        }
    }
}
