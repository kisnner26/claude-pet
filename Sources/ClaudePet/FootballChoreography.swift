import Foundation

/// Fotograma del partido en magnitudes continuas; el dibujo (escenario y sprite de Claude) las interpreta.
struct GameFrame: Equatable {
    var ballT = 0.0            // 0 = junto a Codex, 1 = sobre la cabeza de Claude
    var arc = 0.0              // 0...1, altura del vuelo
    var ballOpacity = 1.0
    var avatarIn = 1.0         // 0...1, entrada del avatar de Codex
    var kickFoot = false       // Codex levanta la pierna
    var kickPulse = 0.0        // 1 -> 0 tras patear (polvo)
    var headerPulse = 0.0      // 1 -> 0 tras tocar la cabeza de Claude (destello)
    var claudeHop = false      // Claude cabecea
    var avatarHop = false      // Codex salta (recibe o celebra)
    var celebrateMoving = false
    var confettiOpacity = 0.0
    var reduced = false        // true: sin desplazamientos
}

/// Coreografia pura: tiempo transcurrido -> fotograma. Sin estado ni dependencias.
///
/// Normal (12 s): Codex entra caminando, patea a Claude (1.6 s de vuelo), Claude cabecea y la
/// devuelve, segunda vuelta, y celebracion (saltos, brazos arriba, confeti).
/// Reducir movimiento: la pelota y el avatar aparecen con un fundido y quedan quietos; el confeti
/// es fijo. Ningun elemento se desplaza.
enum FootballChoreography {
    static let duration: TimeInterval = 12.0
    static let celebrationStart = 9.6
    static let reducedBallT = 0.5

    /// (inicio, fin, direccion): +1 Codex -> Claude, -1 Claude -> Codex.
    static let passes: [(Double, Double, Int)] = [
        (1.6, 3.2, 1), (3.6, 5.2, -1), (5.6, 7.2, 1), (7.6, 9.2, -1),
    ]

    /// Posicion de la pelota en el instante t (tambien se usa para dibujar la estela).
    static func ball(at t: Double) -> (t: Double, arc: Double) {
        var pos = 0.0
        for (a, b, dir) in passes {
            if t >= b { pos = dir > 0 ? 1 : 0 }
            else if t >= a {
                let s = (t - a) / (b - a)
                return (dir > 0 ? s : 1 - s, 4 * s * (1 - s))
            } else { break }
        }
        return (pos, 0)
    }

    static func frame(elapsed t: TimeInterval, reduceMotion: Bool) -> GameFrame? {
        guard t >= 0, t < duration else { return nil }
        var f = GameFrame()

        if reduceMotion {
            let edge = 1.0
            f.reduced = true
            f.ballT = reducedBallT
            f.ballOpacity = max(0, min(1, min(t / edge, (duration - t) / edge)))
            f.confettiOpacity = max(0, min(1, min((t - 7.5) / 1.0, (10.5 - t) / 1.0)))
            return f
        }

        let b = ball(at: t)
        f.ballT = b.t
        f.arc = b.arc
        f.ballOpacity = max(0, min(1, min((t - 0.8) / 0.4, (duration - t) / 0.4)))
        f.avatarIn = min(1, t / 1.2)

        for (a, e, dir) in passes {
            if dir > 0 {
                if t >= a - 0.25, t < a + 0.1 { f.kickFoot = true }
                if t >= a, t < a + 0.4 { f.kickPulse = max(f.kickPulse, 1 - (t - a) / 0.4) }
                if t >= e - 0.1, t < e + 0.25 { f.claudeHop = true }
                if t >= e, t < e + 0.4 { f.headerPulse = max(f.headerPulse, 1 - (t - e) / 0.4) }
            } else {
                if t >= a - 0.1, t < a + 0.25 { f.claudeHop = true }
                if t >= a, t < a + 0.4 { f.headerPulse = max(f.headerPulse, 1 - (t - a) / 0.4) }
                if t >= e - 0.1, t < e + 0.3 { f.avatarHop = true }
            }
        }
        if t >= celebrationStart {
            f.celebrateMoving = true
            f.confettiOpacity = min(1, (t - celebrationStart) / 0.3)
            f.avatarHop = Int(t * 4) % 2 == 0
        }
        return f
    }
}
