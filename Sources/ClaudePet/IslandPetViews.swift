import SwiftUI

struct PetFace: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    /// Suelo por el que pasea (celdas del sprite) y donde esta el otro agente; sin ellos queda quieta como siempre.
    var roam: ClosedRange<CGFloat>? = nil
    var mateSide = 0
    /// Celdas extra a cada lado del sprite en el lienzo, para que el paseo no se recorte.
    static func room(_ roam: ClosedRange<CGFloat>?) -> CGFloat { roam.map { max(abs($0.lowerBound), abs($0.upperBound)).rounded(.up) + 1 } ?? 0 }

    @ViewBuilder var body: some View {
        if model.mode == .hidden {
            Color.clear
        } else {
            // en reposo respira y parpadea despacio: a 6 cuadros por segundo se ve igual y gasta la mitad
            let calm = store.state == .idle && !model.dancing && model.dizzyLeft == nil && model.petHoverSince == nil && !model.dropHover && model.pokes.isEmpty
            TimelineView(.animation(minimumInterval: calm || store.energySaving ? 1.0 / 6.0 : 1.0 / 12.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let now = ProcessInfo.processInfo.systemUptime
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            var scene = Self.makeScene(model: model, store: store)
            let _ = Self.addCompany(to: &scene, roam: roam, mateSide: mateSide, mateState: store.codexState, motion: motion)
            let pose = PetAnimator.pose(at: now, gaze: model.gaze, pokes: model.pokes, hopStart: model.hopStart, motion: motion, hover: model.hover, scene: scene)
            Canvas { gc, size in
                let unit: CGFloat? = roam == nil ? nil : min(size.width / (16 + 2 * Self.room(roam)), size.height / 16)
                var cue = store.cue(at: ctx.date)
                if model.greetUntil > now { cue = (cue ?? PeerCue(state: store.state, greet: false, cheer: false, concern: false)); cue?.greet = true }
                // un archivo encima o recien soltado: la mascota es una caja
                if model.dropHover || model.swallowStart.map({ now - $0 < 0.7 }) == true {
                    var box = PetPose()
                    if let s = model.swallowStart, now - s < 0.7 { box.dx = CGFloat(sin((now - s) * 40)) * 0.5; box.scaleY = 0.96 }
                    PetFace.draw(&gc, size: size, pixels: FileDrop.boxPixels(open: model.dropHover), pose: box, unit: unit)
                    return
                }
                var px = Sprite.pixels(store.state, tick: tick, cue: cue)
                px = store.dress(px, state: store.state, tick: tick, at: ctx.date)
                if store.state != .error { px = PetAnimator.apply(px, pose: pose) }
                // las particulas no siguen al cuerpo: se dibujan antes de moverlo
                var overlay = gc
                PetFace.draw(&gc, size: size, pixels: px, pose: pose, unit: unit)
                if motion { PetFace.draw(&overlay, size: size, pixels: PetAnimator.particles(at: now, pose: pose, scene: scene), pose: PetPose(), unit: unit) }
            }
            }
        }
    }

    /// Momentos que cambian la pose: la entrada al abrir, tu decision sobre un permiso y la espera de uno pendiente.
    static func makeScene(model: IslandModel, store: PetStore) -> PetScene {
        var scene = PetScene(idleSeconds: model.idleSeconds, state: store.state, confettiStart: model.confettiStart, dancing: model.dancing)
        addMoments(to: &scene, model: model, store: store, now: 0)
        return scene
    }

    /// Paseo y compañia: el tramo de suelo, de que lado esta el otro agente y si ese esta trabajando.
    static func addCompany(to scene: inout PetScene, roam: ClosedRange<CGFloat>?, mateSide: Int, mateState: PetState, motion: Bool) {
        guard motion else { return }
        if let r = roam { scene.roamMin = r.lowerBound; scene.roamMax = r.upperBound }
        scene.mateSide = mateSide
        scene.mateWorking = mateState == .thinking || mateState == .tool || mateState == .starting
    }

    static func addMoments(to scene: inout PetScene, model: IslandModel, store: PetStore, now: TimeInterval) {
        scene.openedAt = model.expandStart
        if let d = store.lastDecision { scene.decisionAllow = d.allow; scene.decisionAt = d.at }
        if let ask = store.permissionAsks.first { scene.waitingFor = Date().timeIntervalSince(ask.at) }
        if let since = model.petHoverSince { scene.pettingFor = ProcessInfo.processInfo.systemUptime - since }
        let hour = Calendar.current.component(.hour, from: Date())
        scene.daytime = hour >= 6 && hour < 21
        scene.music = store.musicPulse(at: ProcessInfo.processInfo.systemUptime)
        scene.ambient = store.ambient
    }

    /// `unit` fija el tamano de la celda cuando el lienzo es mas ancho que el sprite (para poder pasear); sin el, el sprite llena el ancho.
    static func draw(_ gc: inout GraphicsContext, size: CGSize, pixels: [Px], pose: PetPose, unit: CGFloat? = nil) {
        let u = unit ?? size.width / 16
        let ox = unit == nil ? 0 : (size.width - 16 * u) / 2
        let oy = unit == nil ? 0 : size.height - 16 * u
        gc.translateBy(x: size.width / 2 + pose.dx * u, y: size.height + pose.dy * u)
        gc.rotate(by: .degrees(pose.rotation))
        gc.scaleBy(x: pose.scaleX, y: pose.scaleY)
        gc.translateBy(x: -size.width / 2, y: -size.height)
        for p in pixels { gc.fill(Path(CGRect(x: ox + CGFloat(p.x) * u, y: oy + CGFloat(p.y) * u, width: u + 0.5, height: u + 0.5)), with: .color(p.c)) }
    }
}

struct CodexMini: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    let greet: Bool
    var roam: ClosedRange<CGFloat>? = nil
    var mateSide = 0
    private func face(_ tick: Int, pose: PetPose) -> CodexAvatar.Face {
        // las expresiones de la pose mandan sobre el estado solo cuando no hay nada urgente que mostrar
        if pose.dizzy { return .dizzy(tick / 2) }
        if pose.annoyed { return .annoyed }
        switch store.codexState {
        case .waiting: return .alert(on: tick % 2 == 0)
        case .error: return .cross
        case .done: return .happy
        case .thinking, .starting: return .dots(tick % 4)
        case .tool: return .typing(tick)
        default:
            if pose.sleepy || pose.blink { return .closed }
            if pose.yawn || pose.happy { return .happy }
            if pose.wideEyes { return .wide }
            if pose.worried || pose.impatient { return .worried }
            return .prompt(cursor: tick % 2 == 0)
        }
    }
    @ViewBuilder var body: some View {
        if model.mode == .hidden {
            Color.clear
        } else {
            let calmCodex = store.codexState == .idle && !model.dancing && model.dizzyLeft == nil && model.petHoverSince == nil && model.codexPokes.isEmpty
            TimelineView(.animation(minimumInterval: calmCodex || store.energySaving ? 1.0 / 5.0 : 1.0 / 8.0)) { ctx in
            let motion = store.animationsEnabled && !store.reduceMotion
            let tick = motion ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
            let legs: CodexAvatar.Legs = motion && tick % 8 < 4 ? .step : .stand
            // la misma vida que claude: respira, se inclina al cursor, se estira, bosteza, se marea y saluda con la mano
            let now = ProcessInfo.processInfo.systemUptime
            let scene: PetScene = { var sc = PetScene(idleSeconds: model.idleSeconds, state: store.codexState, dancing: model.dancing); PetFace.addMoments(to: &sc, model: model, store: store, now: 0); PetFace.addCompany(to: &sc, roam: roam, mateSide: mateSide, mateState: store.state, motion: motion); return sc }()
            let pose = motion ? PetAnimator.pose(at: now, gaze: model.gaze, pokes: model.codexPokes, hopStart: model.codexDoneAt, motion: true, scene: scene) : PetPose()
            CodexMiniFrame(face: face(tick, pose: pose), legs: legs, tick: tick, skin: store.codexSkin, wave: (greet || pose.earLift) && motion, pose: pose,
                           outfits: store.outfitsNow(for: .codex, at: ctx.date), particles: motion ? PetAnimator.particles(at: now, pose: pose, scene: scene) : [])
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
    var outfits: Set<Outfit> = []
    var particles: [Px] = []
    var body: some View {
        Canvas { gc, size in
            let u = min(size.width / 18, size.height / 21)
            let ox = (size.width - 18 * u) / 2
            let oy = (size.height - 21 * u) / 2
            // la pose mueve el cuerpo entero desde los pies, igual que con claude
            // las particulas (estrellas del mareo, notas, confeti) no siguen al cuerpo
            for q in particles { gc.fill(Path(CGRect(x: ox + CGFloat(q.x + 1) * u, y: oy + CGFloat(q.y + 3) * u, width: u + 0.4, height: u + 0.4)), with: .color(q.c)) }
            gc.translateBy(x: size.width / 2 + pose.dx * u, y: oy + 21 * u + pose.dy * u)
            gc.rotate(by: .degrees(pose.rotation))
            gc.scaleBy(x: pose.scaleX, y: pose.scaleY)
            gc.translateBy(x: -size.width / 2, y: -(oy + 21 * u))
            for c in CodexAvatar.cells(legs: legs, face: face, skin: skin, outfits: outfits) {
                gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
            }
            if wave { for c in CodexAvatar.armCells(.wave(tick % 8 < 4), skin: skin) { gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c)) } }
        }
    }
}
