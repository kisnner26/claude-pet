import SwiftUI

/// Medidas (px) de las dos mascotas, que son ventanas independientes, y del partido que las une.
enum StageMetrics {
    // Ventana de Claude (128x128): su lienzo empieza en (8, 8) con celdas de 7 px.
    static let claudeSize = CGSize(width: 128, height: 128)
    static let petX = 8.0, petY = 8.0
    static let cell = 7.0
    static let claudeHeadTop = 36.0        // desde el borde superior de su ventana
    static let claudeFeetInset = 8.0       // pies sobre el borde inferior de su ventana

    // Ventana de Codex (128x152): hueco sobre la cabeza para los globos y los saltos.
    static let codexSize = CGSize(width: 128, height: 152)
    static let codexGround = 144.0         // linea de sus pies, desde el borde superior
    static let avatarCell = 5.0            // px por celda del avatar
    static var avatarLeft: CGFloat { (codexSize.width - CGFloat(CodexAvatar.width) * avatarCell) / 2 }

    // Partido
    static let ballSize = 24.0
    static let arcHeight = 50.0
    static let maxPairDX = 640.0, maxPairDY = 420.0   // mas lejos que esto no hay partido
    static let stageMarginSide = 24.0, stageMarginTop = 80.0, stageMarginBottom = 12.0
}

// MARK: ventana de Codex (independiente de la de Claude)

struct CodexPetView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            Canvas { gc, _ in
                CodexRenderer.draw(&gc, now: ctx.date, info: store.companionInfo(at: ctx.date), game: store.gameFrame(at: ctx.date),
                                   reduceMotion: store.reduceMotion, animate: store.animationsEnabled, facing: store.codexFacing)
            }
        }
        .frame(width: StageMetrics.codexSize.width, height: StageMetrics.codexSize.height)
        .background(Color.black.opacity(0.001))     // mantiene el arrastre sin dibujar ningun panel
        .accessibilityLabel("Codex, estado \(store.companionInfo(at: Date()).codex.label.lowercased())")
    }
}

enum CodexRenderer {
    private static let light = Color(hex: 0xEDE3DA)

    private static func rect(_ g: inout GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
    }

    /// Dibuja a Codex dentro de su propia ventana. `facing` +1: mira a la derecha (Claude esta a su derecha); -1: se refleja.
    /// Con `game`, juega desde su sitio: estira la pierna, salta y celebra, sin moverse de la ventana.
    static func draw(_ g: inout GraphicsContext, now: Date, info: CompanionInfo, game: GameFrame?, reduceMotion: Bool, animate: Bool, facing: Int) {
        let M = StageMetrics.self
        if facing < 0 {
            g.translateBy(x: M.codexSize.width, y: 0)
            g.scaleBy(x: -1, y: 1)
        }
        let motion = animate && !reduceMotion
        let t = animate ? now.timeIntervalSinceReferenceDate : 0
        var pose = CompanionPose.make(info: info, t: t, motion: motion)
        if let f = game {
            if f.kickFoot { pose.legs = .kick }
            if f.celebrateMoving { pose.face = .happy; pose.emote = nil }
            if f.avatarHop { pose.hop = 10 }
        }
        let au = M.avatarCell
        let aw = CGFloat(CodexAvatar.width) * au
        let lift = pose.hop - pose.bob
        // sombra
        let sw = aw * (0.62 - min(lift, 12) * 0.012)
        g.fill(Path(ellipseIn: CGRect(x: M.avatarLeft + (aw - sw) / 2 + pose.shake, y: M.codexGround + 1, width: sw, height: 5)),
               with: .color(Color.black.opacity(0.28)))
        // avatar
        let x = M.avatarLeft + pose.shake
        let top = M.codexGround - CGFloat(CodexAvatar.height) * au - lift
        for c in CodexAvatar.cells(legs: pose.legs, face: pose.face) { rect(&g, x + Double(c.x) * au, top + Double(c.y) * au, au, au, c.c) }
        if let e = pose.emote { for c in CodexAvatar.emote(e) { rect(&g, x + Double(c.x) * au, top + Double(c.y) * au, au, au, c.c) } }
        // polvo al patear
        if let f = game, f.kickPulse > 0 {
            let e = (1 - f.kickPulse) * 16 + 4
            for (dx, dy) in [(0.0, -1.0), (1.0, -0.5), (-1.0, -0.5), (0.7, -1.4), (-0.7, -1.4)] {
                rect(&g, x + 16 * au + 2 + dx * e, M.codexGround - 8 + dy * e * 0.6, 4, 4, light.opacity(f.kickPulse))
            }
        }
    }
}

// MARK: capa del partido: la pelota viaja entre las dos ventanas, esten donde esten

struct StageView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            Canvas { gc, _ in
                guard let start = store.gameStart, let geo = store.gameGeometry else { return }
                GameRenderer.draw(&gc, elapsed: ctx.date.timeIntervalSince(start), reduceMotion: store.reduceMotion, geo: geo)
            }
        }
    }
}

enum GameRenderer {
    private static let light = Color(hex: 0xEDE3DA)
    private static let ballW = Color(hex: 0xF2EBE3), ballS = Color(hex: 0x6E665F)

    private static func rect(_ g: inout GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
    }

    /// Pelota con estela y sombra, destello al tocar la cabeza de Claude y confeti. Devuelve false si no hay fotograma.
    @discardableResult
    static func draw(_ g: inout GraphicsContext, elapsed t: Double, reduceMotion: Bool, geo: GameGeometry) -> Bool {
        guard let f = FootballChoreography.frame(elapsed: t, reduceMotion: reduceMotion) else { return false }
        let M = StageMetrics.self
        let s = geo.ballStart, e = geo.ballEnd

        func ballPoint(_ bt: Double, _ arc: Double) -> CGPoint {
            CGPoint(x: s.x + (e.x - s.x) * bt, y: s.y + (e.y - s.y) * bt - arc * M.arcHeight)
        }
        func groundAt(_ bt: Double) -> Double { geo.groundStart + (geo.groundEnd - geo.groundStart) * bt }
        let bp = f.reduced
            ? CGPoint(x: s.x + (e.x - s.x) * f.ballT, y: groundAt(f.ballT) - M.ballSize)
            : ballPoint(f.ballT, f.arc)

        // sombra bajo la pelota
        let lift = f.reduced ? 0 : f.arc
        let sw = M.ballSize * (1.1 - 0.4 * lift)
        g.fill(Path(ellipseIn: CGRect(x: bp.x + (M.ballSize - sw) / 2, y: groundAt(f.ballT) + 1, width: sw, height: 5)),
               with: .color(Color.black.opacity(0.28 * f.ballOpacity)))

        // estela (solo con movimiento)
        if !f.reduced && f.ballOpacity > 0 && f.arc > 0.02 {
            for k in 1...3 {
                let past = FootballChoreography.ball(at: t - Double(k) * 0.06)
                let p = ballPoint(past.t, past.arc)
                rect(&g, p.x + 6, p.y + 6, M.ballSize - 12, M.ballSize - 12, ballW.opacity(0.22 * f.ballOpacity / Double(k)))
            }
        }

        // pelota 4x4 con parches que giran
        let c = M.ballSize / 4
        let flip = !f.reduced && Int(t * 12) % 2 == 0
        let rows: [[Int]] = [[0, 1, 1, 0], [1, flip ? 1 : 2, 1, 1], [1, 1, flip ? 2 : 1, 1], [0, 1, 1, 0]]
        for (ry, row) in rows.enumerated() {
            for (rx, v) in row.enumerated() where v != 0 {
                rect(&g, bp.x + Double(rx) * c, bp.y + Double(ry) * c, c, c, (v == 2 ? ballS : ballW).opacity(f.ballOpacity))
            }
        }

        // destello al tocar la cabeza de Claude
        if f.headerPulse > 0 {
            let r = (1 - f.headerPulse) * 16 + 6
            let cx = e.x + M.ballSize / 2, cy = e.y + M.ballSize / 2
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, -1.0), (0.7, -0.7), (-0.7, -0.7)] {
                rect(&g, cx + dx * r - 2, cy + dy * r - 2, 5, 5, Color(hex: 0xEC9A6E).opacity(f.headerPulse))
            }
        }

        // confeti sobre toda la escena
        if f.confettiOpacity > 0 {
            let palette = [Color(hex: 0xE0824F), Color(hex: 0xEC9A6E), Color(hex: 0xEDE3DA), Color(hex: 0xB9603A)]
            let fall = max(0, t - FootballChoreography.celebrationStart)
            let W = geo.size.width, H = geo.size.height
            func rnd(_ i: Int, _ k: Double) -> Double { let v = sin(Double(i) * k) * 43758.5453; return v - v.rounded(.down) }
            for i in 0..<40 {
                let speed = 50 + rnd(i, 4.1) * 60
                let phase = rnd(i, 78.233) * H
                let x0 = 8 + rnd(i, 12.9898) * (W - 16)
                let sway = f.reduced ? 0 : sin(fall * 3 + Double(i)) * 6
                let y = f.reduced ? phase : (fall * speed + phase).truncatingRemainder(dividingBy: H + 10) - 10
                rect(&g, x0 + sway, y, 5, 5, palette[i % 4].opacity(f.confettiOpacity))
            }
        }
        return true
    }
}
