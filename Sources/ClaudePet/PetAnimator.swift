import SwiftUI

/// Pose de la mascota en un instante, en unidades del sprite (rejilla de 16 x 16).
struct PetPose: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0
    /// Desplazamiento de los ojos, de -1 a 1 celdas.
    var eyeDX = 0
    var eyeDY = 0
    var blink = false
    var dizzy = false
    var annoyed = false
    var wideEyes = false
}

/// Animacion de personaje de la isla: respiracion, parpadeo, mirada, reaccion al toque y salto al terminar.
/// Es pura: recibe el tiempo y devuelve la pose, asi se puede probar sin ventana.
enum PetAnimator {
    static let breathPeriod: TimeInterval = 4
    static let blinkLength: TimeInterval = 0.14
    static let pokeShake: TimeInterval = 0.35
    static let dizzyWindow: TimeInterval = 2
    static let dizzyPokes = 3
    static let dizzyLength: TimeInterval = 1.8
    static let pokeAnnoyed: TimeInterval = 0.6
    static let hopLength: TimeInterval = 0.6
    static let hopHeight: CGFloat = 3

    /// Numero pseudoaleatorio estable por ciclo (0...1), sin estado.
    private static func jitter(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }

    /// Parpadeo cada 2 a 5 s, con un parpadeo doble de vez en cuando.
    static func isBlinking(at t: TimeInterval) -> Bool {
        let cycle = 3.5
        let n = Int((t / cycle).rounded(.down))
        let local = t - Double(n) * cycle
        let start = jitter(n) * (cycle - 0.8)
        let d = local - start
        if d >= 0 && d < blinkLength { return true }
        if jitter(n + 7919) > 0.8 && d >= 0.3 && d < 0.3 + blinkLength { return true }
        return false
    }

    /// Mirada: la pupila se desplaza una celda hacia el cursor cuando esta lo bastante lejos del centro.
    static func eyes(gaze: CGPoint) -> (dx: Int, dy: Int) {
        let dx = gaze.x > 0.25 ? 1 : (gaze.x < -0.25 ? -1 : 0)
        // en AppKit y crece hacia arriba; en el sprite hacia abajo
        let dy = gaze.y > 0.35 ? -1 : (gaze.y < -0.35 ? 1 : 0)
        return (dx, dy)
    }

    static func pose(at t: TimeInterval, gaze: CGPoint, pokes: [TimeInterval], hopStart: TimeInterval?, motion: Bool, hover: Bool = false) -> PetPose {
        var p = PetPose()
        let look = eyes(gaze: gaze)
        p.eyeDX = look.dx; p.eyeDY = look.dy
        p.wideEyes = hover
        guard motion else { return p }

        // respiracion: el cuerpo se estira un 4 % desde los pies
        let breath = (sin(t * 2 * .pi / breathPeriod) + 1) / 2
        p.scaleY = 1 + 0.04 * CGFloat(breath)
        p.scaleX = 1 - 0.015 * CGFloat(breath)
        p.blink = isBlinking(at: t)

        // toque: sacudida corta; tres toques seguidos marean
        let recent = pokes.filter { t - $0 >= 0 && t - $0 < dizzyWindow }
        if recent.count >= dizzyPokes, let third = recent.sorted().dropFirst(dizzyPokes - 1).first, t - third < dizzyLength {
            p.dizzy = true
            p.rotation = 8 * sin((t - third) * 14) * (1 - (t - third) / dizzyLength)
            p.blink = false
        } else if let last = pokes.filter({ $0 <= t }).max(), t - last < pokeShake {
            let k = (t - last) / pokeShake
            p.dx = CGFloat(sin(k * 6 * .pi)) * (1 - CGFloat(k))
            p.blink = true     // entrecierra los ojos, molesta
        }
        if let last = pokes.filter({ $0 <= t }).max(), t - last < pokeAnnoyed {
            let k = (t - last) / pokeAnnoyed
            p.annoyed = true
            p.blink = true
            if k < 0.22 { p.scaleY *= 0.86; p.scaleX *= 1.06 }
            else { p.scaleY *= 0.96 + 0.04 * CGFloat(min(1, (k - 0.22) / 0.78)) }
        }

        // salto al terminar: arco con un pequeno aplastamiento al caer
        if let h = hopStart, t >= h, t - h < hopLength {
            let k = (t - h) / hopLength
            p.dy -= hopHeight * CGFloat(sin(k * .pi))
            if k > 0.85 { p.scaleY *= 0.93; p.scaleX *= 1.04 }
        }
        return p
    }

    /// Aplica la pose a los pixeles del sprite: ojos desplazados, parpadeo y ojos de mareo.
    /// Los ojos son los pixeles de tinta de la zona de la cara (filas 5 a 10).
    static func apply(_ pixels: [Px], pose: PetPose) -> [Px] {
        func isEye(_ q: Px) -> Bool { q.c == Pal.charcoal && q.y >= 5 && q.y <= 10 && q.x >= 3 && q.x <= 12 }
        let eyes = pixels.filter(isEye)
        guard !eyes.isEmpty, pose.eyeDX != 0 || pose.eyeDY != 0 || pose.blink || pose.dizzy || pose.wideEyes else { return pixels }
        var out = pixels.filter { !isEye($0) }
        let ink = Pal.charcoal
        if pose.dizzy {
            for (cx, cy) in [(5, 8), (10, 8)] {
                for (x, y) in [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)] { out.append(Px(x: cx + x, y: cy + y, c: ink)) }
            }
        } else if pose.blink {
            for x in Set(eyes.map(\.x)) { out.append(Px(x: x + pose.eyeDX, y: 8, c: ink)) }
        } else {
            for e in eyes {
                let x = min(12, max(3, e.x + pose.eyeDX)), y = min(11, max(5, e.y + pose.eyeDY))
                out.append(Px(x: x, y: y, c: ink))
                if pose.wideEyes { out.append(Px(x: x, y: min(11, y + 1), c: ink)) }
            }
        }
        return out
    }
}
