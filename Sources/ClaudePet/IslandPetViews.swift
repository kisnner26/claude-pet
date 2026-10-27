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
            let pose = PetAnimator.pose(at: now, gaze: model.gaze, pokes: model.pokes, hopStart: model.hopStart, motion: motion, hover: model.hover)
            Canvas { gc, size in
                var cue = store.cue(at: ctx.date)
                if model.greetUntil > now { cue = (cue ?? PeerCue(state: store.state, greet: false, cheer: false, concern: false)); cue?.greet = true }
                var px = Sprite.pixels(store.state, tick: tick, cue: cue)
                if store.state != .error { px = PetAnimator.apply(px, pose: pose) }
                PetFace.draw(&gc, size: size, pixels: px, pose: pose)
            }
            }
        }
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
            CodexMiniFrame(face: face(tick), legs: legs, tick: tick, skin: store.codexSkin, wave: greet && motion)
            }
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
