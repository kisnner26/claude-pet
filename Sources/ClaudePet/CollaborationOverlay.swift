import SwiftUI

/// Capa visual para el trabajo simultaneo: no transmite ni infiere datos nuevos.
enum CollaborationRenderer {
    static func draw(_ g: inout GraphicsContext, elapsed: TimeInterval, reduceMotion: Bool, geo: GameGeometry) {
        let start = CGPoint(x: geo.ballStart.x + StageMetrics.ballSize / 2, y: geo.groundStart - 38)
        let end = CGPoint(x: geo.ballEnd.x + StageMetrics.ballSize / 2, y: geo.groundEnd - 58)
        let blue = Color(hex: 0x96EBFF)
        let coral = Color(hex: 0xEC9A6E)
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        g.stroke(line, with: .color(blue.opacity(0.32)), style: StrokeStyle(lineWidth: 2, dash: [5, 7]))

        let progress: CGFloat
        if reduceMotion {
            progress = 0.5
        } else {
            progress = CGFloat((elapsed * 0.45).truncatingRemainder(dividingBy: 1))
        }
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress
        let packet = Path(CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
        g.fill(packet, with: .color(progress < 0.5 ? blue : coral))

        let reverse = reduceMotion ? 0.5 : 1 - progress
        let rx = start.x + (end.x - start.x) * reverse
        let ry = start.y + (end.y - start.y) * reverse
        g.fill(Path(CGRect(x: rx - 3, y: ry - 3, width: 6, height: 6)), with: .color(coral.opacity(0.85)))
    }
}

/// Abrazo en la capa comun: las dos mascotas quedan juntas, con los pies en la misma linea, y cada una rodea con un brazo
/// el cuerpo de la otra (el brazo cruza su torso y la mano asoma por detras). Las ventanas no se mueven.
enum HugRenderer {
    static func draw(_ g: inout GraphicsContext, elapsed: TimeInterval, reduceMotion: Bool, geo: GameGeometry,
                     claudeSkin: Skin, codexSkin: CodexSkin) {
        let u = StageMetrics.cell, au = StageMetrics.avatarCell
        let claudeMid = geo.claudeOrigin.x + StageMetrics.claudeSize.width / 2
        let codexMid = geo.codexOrigin.x + StageMetrics.codexSize.width / 2
        let dir: CGFloat = claudeMid >= codexMid ? 1 : -1                 // +1: Claude a la derecha de Codex
        let cx = (claudeMid + codexMid) / 2
        let ground = (geo.groundStart + geo.groundEnd) / 2                // una sola linea de suelo para los dos
        let bob: CGFloat = reduceMotion ? 0 : (sin(elapsed * 3) > 0 ? -2 : 0)   // se mecen a saltitos de 2 px

        // La cabeza de Codex roza el cuerpo de Claude: los torsos quedan a un brazo de distancia.
        let half: CGFloat = 43.5
        let codexCx = cx - dir * half, claudeCx = cx + dir * half
        let codexHalfTorso = 4 * au
        let blockSkin = claudeSkin == .block
        let claudeHalfBody: CGFloat = blockSkin ? 6 * u : 4 * u           // mitad del cuerpo sin orejas / brazos
        let claudeBottomCells: CGFloat = blockSkin ? 16 : 13              // el sprite termina antes en el aspecto clasico

        // Claude (cuerpo en reposo, de pie sobre el suelo comun)
        let claudeX = claudeCx - 8 * u
        let claudeY = ground - claudeBottomCells * u + bob
        for p in (blockSkin ? Sprite.block(.idle, tick: 28) : Sprite.classic(.idle, tick: 28)) {      // tick 28: ojos cerrados y contentos
            g.fill(Path(CGRect(x: claudeX + CGFloat(p.x) * u, y: claudeY + CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c))
        }
        // Codex (cara feliz, de pie sobre el mismo suelo)
        let codexX = codexCx - CGFloat(CodexAvatar.width) * au / 2
        let codexCells = CodexAvatar.cells(legs: .stand, face: .happy, skin: codexSkin)
        // sus pies terminan antes del final de la rejilla: se apoya la ultima fila con color, no el borde del lienzo
        let codexBottom = CGFloat((codexCells.map { $0.y }.max() ?? CodexAvatar.height - 1) + 1) * au
        let codexY = ground - codexBottom + bob
        for c in codexCells {
            g.fill(Path(CGRect(x: codexX + CGFloat(c.x) * au, y: codexY + CGFloat(c.y) * au, width: au, height: au)), with: .color(c.c))
        }

        // Brazo grueso en pixeles: del costado de quien abraza, cruzando el torso del otro, hasta la espalda.
        func arm(fromX: CGFloat, toX: CGFloat, top: CGFloat, fill: Color, edge: Color, hand: Color) {
            let x0 = min(fromX, toX), w = abs(toX - fromX)
            g.fill(Path(CGRect(x: x0 - 2, y: top - 2, width: w + 4, height: 14)), with: .color(edge))
            g.fill(Path(CGRect(x: x0, y: top, width: w, height: 10)), with: .color(fill))
            let handX = toX > fromX ? toX - 6 : toX - 6
            g.fill(Path(CGRect(x: handX - 2, y: top - 4, width: 16, height: 18)), with: .color(edge))
            g.fill(Path(CGRect(x: handX, y: top - 2, width: 12, height: 14)), with: .color(hand))
        }
        // Codex rodea a Claude por la espalda: su brazo cruza la barriga de Claude (nunca su cara) y la mano asoma por el otro lado.
        arm(fromX: codexCx + dir * codexHalfTorso, toX: claudeCx + dir * (claudeHalfBody + 6),
            top: ground - 32 + bob,
            fill: CodexAvatar.color("B", skin: codexSkin) ?? .blue, edge: CodexAvatar.color("O", skin: codexSkin) ?? .black,
            hand: CodexAvatar.color("L", skin: codexSkin) ?? .white)
        // Claude rodea a Codex: su brazo cruza el torso de Codex, un poco mas arriba, y asoma por detras.
        arm(fromX: claudeCx - dir * claudeHalfBody, toX: codexCx - dir * (codexHalfTorso + 6),
            top: ground - 46 + bob,
            fill: Pal.body, edge: Pal.dark, hand: Pal.light)

        // Corazon sobre las cabezas
        let pulse: CGFloat = reduceMotion ? 0.9 : 0.9 + 0.1 * sin(elapsed * 4)
        let h: CGFloat = 5 * pulse
        let pixels: [(CGFloat, CGFloat)] = [(-2, 0), (-1, 0), (1, 0), (2, 0),
                                            (-3, 1), (-2, 1), (-1, 1), (0, 1), (1, 1), (2, 1), (3, 1),
                                            (-2, 2), (-1, 2), (0, 2), (1, 2), (2, 2),
                                            (-1, 3), (0, 3), (1, 3), (0, 4)]
        let top = codexY - 34
        for (x, y) in pixels {
            g.fill(Path(CGRect(x: cx + x * h - h / 2, y: top + y * h, width: h, height: h)), with: .color(Pal.body))
        }
    }
}
