import SwiftUI

/// Escenario del partido: una ventana transparente (sin raton) pegada a la mascota donde se
/// dibuja el avatar de Codex en grande, la pelota con estela y sombra, los destellos y el confeti.
/// Sistema de coordenadas del escenario (px): la ventana de la mascota ocupa x 208...336, y 24...152,
/// y el lienzo del sprite de Claude empieza en (216, 32) con celdas de 7 px.
enum StageMetrics {
    static let width = 336.0, height = 160.0
    static let leftReach = 208.0           // cuanto sobresale el escenario por el lado del avatar
    static let petX = 216.0, petY = 32.0   // origen del lienzo de Claude dentro del escenario
    static let cell = 7.0
    static let ground = 144.0              // linea de los pies
    static let avatarX = 24.0
    static let avatarCell = 5.0            // px por celda del avatar de Codex
    static let ballSize = 24.0
    static let ballStart = CGPoint(x: 124, y: 120)     // junto a los pies de Codex
    static let ballEnd = CGPoint(x: 274, y: 36)        // sobre la cabeza de Claude
    static let arcHeight = 50.0
}

struct StageView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { gc, size in
                guard let start = store.gameStart else { return }
                let t = ctx.date.timeIntervalSince(start)
                StageRenderer.draw(&gc, elapsed: t, reduceMotion: store.reduceMotion, mirrored: store.stageMirrored)
            }
        }
        .frame(width: StageMetrics.width, height: StageMetrics.height)
    }
}

enum StageRenderer {
    private static let light = Color(hex: 0xEDE3DA)
    private static let ballW = Color(hex: 0xF2EBE3), ballS = Color(hex: 0x6E665F)

    private static func rect(_ g: inout GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
        g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
    }

    static func draw(_ g: inout GraphicsContext, elapsed t: Double, reduceMotion: Bool, mirrored: Bool) {
        guard let f = FootballChoreography.frame(elapsed: t, reduceMotion: reduceMotion) else { return }
        if mirrored {
            g.translateBy(x: StageMetrics.width, y: 0)
            g.scaleBy(x: -1, y: 1)
        }
        let M = StageMetrics.self

        // posicion de la pelota
        func ballPoint(_ bt: Double, _ arc: Double) -> CGPoint {
            CGPoint(x: M.ballStart.x + (M.ballEnd.x - M.ballStart.x) * bt,
                    y: M.ballStart.y + (M.ballEnd.y - M.ballStart.y) * bt - arc * M.arcHeight)
        }
        let restMid = M.ballStart.x + (M.ballEnd.x - M.ballStart.x) * f.ballT
        let bp = f.reduced ? CGPoint(x: restMid, y: M.ground - M.ballSize) : ballPoint(f.ballT, f.arc)

        // sombra bajo la pelota
        let lift = f.reduced ? 0 : f.arc
        let sw = M.ballSize * (1.1 - 0.4 * lift)
        g.fill(Path(ellipseIn: CGRect(x: bp.x + (M.ballSize - sw) / 2, y: M.ground + 1, width: sw, height: 5)),
               with: .color(Color.black.opacity(0.28 * f.ballOpacity)))

        // avatar de Codex (robot-nube azul, mira hacia Claude)
        let au = M.avatarCell
        let aw = CGFloat(CodexAvatar.width) * au
        let ease = 1 - pow(1 - f.avatarIn, 3)
        let ax = f.reduced ? M.avatarX : -(aw + 8) + (M.avatarX + aw + 8) * ease
        let walking = !f.reduced && f.avatarIn < 1
        let hop = f.avatarHop ? 10.0 : 0
        let ay = M.ground - CGFloat(CodexAvatar.height) * au - hop
        let step = walking && Int(t * 8) % 2 == 0
        let legs: CodexAvatar.Legs = f.kickFoot ? .kick : (step ? .step : .stand)
        let face: CodexAvatar.Face = f.celebrateMoving ? .happy : .prompt(cursor: f.reduced || Int(t * 2) % 2 == 0)
        for c in CodexAvatar.cells(legs: legs, face: face) { rect(&g, ax + Double(c.x) * au, ay + Double(c.y) * au, au, au, c.c) }

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

        // polvo al patear
        if f.kickPulse > 0 {
            let e = (1 - f.kickPulse) * 16 + 4
            for (dx, dy) in [(0.0, -1.0), (1.0, -0.5), (-1.0, -0.5), (0.7, -1.4), (-0.7, -1.4)] {
                rect(&g, ax + 16 * au + 2 + dx * e, M.ground - 8 + dy * e * 0.6, 4, 4, light.opacity(f.kickPulse))
            }
        }
        // destello al tocar la cabeza de Claude
        if f.headerPulse > 0 {
            let e = (1 - f.headerPulse) * 16 + 6
            let cx = M.ballEnd.x + M.ballSize / 2, cy = M.ballEnd.y + M.ballSize / 2
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, -1.0), (0.7, -0.7), (-0.7, -0.7)] {
                rect(&g, cx + dx * e - 2, cy + dy * e - 2, 5, 5, Color(hex: 0xEC9A6E).opacity(f.headerPulse))
            }
        }
        // confeti
        if f.confettiOpacity > 0 {
            let palette = [Color(hex: 0xE0824F), Color(hex: 0xEC9A6E), Color(hex: 0xEDE3DA), Color(hex: 0xB9603A)]
            let fall = max(0, t - FootballChoreography.celebrationStart)
            func rnd(_ i: Int, _ k: Double) -> Double { let v = sin(Double(i) * k) * 43758.5453; return v - v.rounded(.down) }
            for i in 0..<40 {
                let speed = 50 + rnd(i, 4.1) * 60
                let phase = rnd(i, 78.233) * M.height
                let x0 = 8 + rnd(i, 12.9898) * (M.width - 16)
                let sway = f.reduced ? 0 : sin(fall * 3 + Double(i)) * 6
                let y = f.reduced ? phase : (fall * speed + phase).truncatingRemainder(dividingBy: M.height + 10) - 10
                rect(&g, x0 + sway, y, 5, 5, palette[i % 4].opacity(f.confettiOpacity))
            }
        }
    }
}
