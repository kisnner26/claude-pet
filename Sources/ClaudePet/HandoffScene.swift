import SwiftUI

/// Un relevo ocurre cuando un agente termina y el otro empieza a trabajar poco después.
struct Handoff: Equatable {
    let from: String        // "claude" | "codex"
    let to: String
    let at: Date

    static let window: TimeInterval = 45        // máximo entre "terminó" y "empezó"
    static let duration: TimeInterval = 2.2     // lo que dura la escena
}

/// Una chispa viaja de la mascota que terminó a la que retoma, con estela y un destello al llegar.
/// Con reducir movimiento no hay viaje: solo un resplandor suave sobre quien retoma.
enum HandoffRenderer {
    private static let claude = (r: 0.878, g: 0.51, b: 0.31)
    private static let codex = (r: 0.588, g: 0.922, b: 1.0)

    static func progress(elapsed t: Double) -> Double { min(1, max(0, (t - 0.15) / 1.1)) }
    static func eased(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    static func point(_ p: Double, from a: CGPoint, to b: CGPoint, lift: CGFloat) -> CGPoint {
        let c = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - lift)
        let q = 1 - p
        return CGPoint(x: q * q * a.x + 2 * q * p * c.x + p * p * b.x, y: q * q * a.y + 2 * q * p * c.y + p * p * b.y)
    }

    private static func tint(_ agent: String, _ opacity: Double = 1) -> Color {
        let c = agent == "claude" ? claude : codex
        return Color(red: c.r, green: c.g, blue: c.b).opacity(opacity)
    }

    private static func mix(_ p: Double, from: String, to: String) -> Color {
        let a = from == "claude" ? claude : codex, b = to == "claude" ? claude : codex
        return Color(red: a.r + (b.r - a.r) * p, green: a.g + (b.g - a.g) * p, blue: a.b + (b.b - a.b) * p)
    }

    /// Puntos de contacto (cuerpo de cada mascota) dentro de la capa del escenario.
    static func anchors(geo: GameGeometry) -> (claude: CGPoint, codex: CGPoint) {
        (CGPoint(x: geo.claudeOrigin.x + StageMetrics.claudeSize.width / 2, y: geo.groundEnd - 44),
         CGPoint(x: geo.codexOrigin.x + StageMetrics.codexSize.width / 2, y: geo.groundStart - 62))
    }

    static func draw(_ g: inout GraphicsContext, elapsed t: Double, reduceMotion: Bool, geo: GameGeometry, handoff: Handoff) {
        guard t >= 0, t <= Handoff.duration else { return }
        let a = anchors(geo: geo)
        let from = handoff.from == "claude" ? a.claude : a.codex
        let to = handoff.to == "claude" ? a.claude : a.codex

        if reduceMotion {
            let level = sin(min(1, t / Handoff.duration) * .pi)
            g.drawLayer { l in
                l.addFilter(.blur(radius: 14))
                l.fill(Path(ellipseIn: CGRect(x: to.x - 34, y: to.y - 34, width: 68, height: 68)), with: .color(tint(handoff.to, 0.55 * level)))
            }
            return
        }

        let p = eased(progress(elapsed: t))
        let lift: CGFloat = 56
        let head = point(p, from: from, to: to, lift: lift)
        let color = mix(p, from: handoff.from, to: handoff.to)
        let travelling = t >= 0.15 && t <= 1.25

        // estela: el recorrido ya hecho, que se apaga hacia atrás
        if p > 0 {
            g.drawLayer { l in
                l.addFilter(.blur(radius: 3))
                for k in 0..<18 {
                    let back = p - Double(k) * 0.028
                    guard back >= 0 else { break }
                    let pt = point(back, from: from, to: to, lift: lift)
                    let fade = (1 - Double(k) / 18) * (t > 1.25 ? max(0, 1 - (t - 1.25) / 0.5) : 1)
                    let r = 5.5 * (1 - Double(k) / 26)
                    l.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                           with: .color(mix(back, from: handoff.from, to: handoff.to).opacity(0.7 * fade)))
                }
            }
        }
        // destello de salida
        if t < 0.45 {
            let f = t / 0.45
            ring(&g, at: from, radius: 10 + 22 * f, opacity: (1 - f) * 0.9, color: tint(handoff.from), width: 2)
        }
        // chispa
        if travelling {
            g.drawLayer { l in
                l.addFilter(.blur(radius: 7))
                l.fill(Path(ellipseIn: CGRect(x: head.x - 11, y: head.y - 11, width: 22, height: 22)), with: .color(color.opacity(0.85)))
            }
            g.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.95)))
        }
        // llegada: dos ondas que se expanden
        if t > 1.25 {
            let f = min(1, (t - 1.25) / 0.85)
            ring(&g, at: to, radius: 12 + 46 * f, opacity: (1 - f) * 0.95, color: tint(handoff.to), width: 2.5)
            if f > 0.2 { ring(&g, at: to, radius: 8 + 30 * (f - 0.2) / 0.8, opacity: (1 - f) * 0.7, color: .white, width: 1.5) }
            g.drawLayer { l in
                l.addFilter(.blur(radius: 12))
                l.fill(Path(ellipseIn: CGRect(x: to.x - 26, y: to.y - 26, width: 52, height: 52)), with: .color(tint(handoff.to, 0.5 * (1 - f))))
            }
        }
    }

    private static func ring(_ g: inout GraphicsContext, at c: CGPoint, radius r: Double, opacity: Double, color: Color, width: CGFloat) {
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(max(0, opacity))), lineWidth: width)
    }
}
