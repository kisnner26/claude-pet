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
    /// Dormida: ojos cerrados y respiracion lenta.
    var sleepy = false
    var worried = false
    var dancing = false
}

/// Lo que la mascota sabe de su entorno para elegir una emocion. Todo llega ya calculado por el controlador.
struct PetScene: Equatable {
    /// Segundos sin que el usuario toque el raton ni el teclado.
    var idleSeconds: TimeInterval = 0
    var state: PetState = .idle
    /// Inicio de la fiesta de confeti tras una tarea larga.
    var confettiStart: TimeInterval?
    var dancing = false
}

/// Animacion de personaje de la isla: respiracion, parpadeo, mirada, reaccion al toque y salto al terminar.
/// Es pura: recibe el tiempo y devuelve la pose, asi se puede probar sin ventana.
enum PetAnimator {
    static let breathPeriod: TimeInterval = 4
    static let blinkLength: TimeInterval = 0.14
    static let pokeShake: TimeInterval = 0.35
    static let dizzyWindow: TimeInterval = 2
    static let dizzyPokes = 3
    static let dizzyLength: TimeInterval = 3
    static let pokeAnnoyed: TimeInterval = 0.6
    static let hopLength: TimeInterval = 0.6
    static let hopHeight: CGFloat = 3
    /// Anticipacion: se agacha antes de saltar; despues rebota un poco al caer.
    static let crouchLength: TimeInterval = 0.12
    static let bounceLength: TimeInterval = 0.28
    static let sleepAfter: TimeInterval = 300
    static let confettiLength: TimeInterval = 2.6
    static let longTask: TimeInterval = 300

    /// Numero pseudoaleatorio estable por ciclo (0...1), sin estado.
    private static func jitter(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }

    /// El toque que la mareo: el ultimo con otros dos en los 2 s anteriores, mientras el mareo dure.
    static func dizzyTrigger(pokes: [TimeInterval], at t: TimeInterval) -> TimeInterval? {
        let past = pokes.filter { $0 <= t }.sorted()
        for p in past.reversed() where t - p < dizzyLength {
            if past.filter({ p - $0 >= 0 && p - $0 < dizzyWindow }).count >= dizzyPokes { return p }
        }
        return nil
    }

    /// Segundos que le quedan de mareo, o nil si no esta mareada: tres toques en menos de 2 s.
    static func dizzyRemaining(pokes: [TimeInterval], at t: TimeInterval) -> TimeInterval? {
        dizzyTrigger(pokes: pokes, at: t).map { dizzyLength - (t - $0) }
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

    static func pose(at t: TimeInterval, gaze: CGPoint, pokes: [TimeInterval], hopStart: TimeInterval?, motion: Bool, hover: Bool = false, scene: PetScene = PetScene()) -> PetPose {
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
        if let third = dizzyTrigger(pokes: pokes, at: t) {
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

        // salto al terminar: se agacha, salta en arco, cae aplastada y rebota una vez mas pequeno
        if let h = hopStart, t >= h {
            let e = t - h
            if e < crouchLength {
                let k = CGFloat(e / crouchLength)
                p.scaleY *= 1 - 0.13 * k; p.scaleX *= 1 + 0.07 * k
            } else if e < crouchLength + hopLength {
                let k = (e - crouchLength) / hopLength
                p.dy -= hopHeight * CGFloat(sin(k * .pi))
                if k > 0.85 { p.scaleY *= 0.93; p.scaleX *= 1.04 }
            } else if e < crouchLength + hopLength + bounceLength {
                let k = (e - crouchLength - hopLength) / bounceLength
                p.dy -= 1 * CGFloat(sin(k * .pi))
                if k < 0.25 { p.scaleY *= 0.95; p.scaleX *= 1.03 }
            }
        }

        // emociones de fondo: solo cuando nada mas reclama a la mascota
        let busy = p.dizzy || p.annoyed || hopStart.map { t >= $0 && t - $0 < crouchLength + hopLength + bounceLength } == true
        if !busy {
            if scene.state == .idle, scene.idleSeconds >= sleepAfter {
                p.sleepy = true; p.blink = true
                p.scaleY = 1 + 0.03 * CGFloat((sin(t * 2 * .pi / 6) + 1) / 2)     // respira mas despacio y mas hondo
            } else if scene.state == .error {
                p.worried = true
                p.dx += CGFloat(sin(t * 50)) * 0.25                              // tiembla de preocupacion
            } else if scene.dancing, scene.state == .idle || scene.state == .done {
                p.dancing = true
                p.rotation = 6 * sin(t * 2 * .pi * 2)
                p.dy -= 0.8 * CGFloat(abs(sin(t * 2 * .pi * 2)))
            }
        }
        return p
    }

    /// Particulas pixel-art de las emociones, en la rejilla 16x16 del sprite, siempre dentro del lienzo.
    static func particles(at t: TimeInterval, pose: PetPose, scene: PetScene) -> [Px] {
        var out: [Px] = []
        let cream = Pal.cream, light = Pal.light
        func clip(_ x: Int, _ y: Int) -> Bool { (0..<16).contains(x) && (0..<16).contains(y) }
        if pose.sleepy {
            // tres "z" que suben y se desvanecen, desfasadas
            for i in 0..<3 {
                let k = (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let size = k < 0.4 ? 2 : 3
                let x = 10 + Int(k * 4) + i % 2, y = 3 - Int(k * 3)
                let cells: [(Int, Int)] = size == 2 ? [(0, 0), (1, 0), (0, 1), (1, 1)] : [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)]
                for (cx, cy) in cells where clip(x + cx, max(0, y) + cy) && k < 0.9 { out.append(Px(x: x + cx, y: max(0, y) + cy, c: cream)) }
            }
        }
        if pose.worried {
            // gota de sudor que resbala por la frente
            let k = (t * 1.2).truncatingRemainder(dividingBy: 1)
            let y = 4 + Int(k * 4)
            for (cx, cy) in [(0, 0), (0, 1)] where clip(13 + cx, y + cy) { out.append(Px(x: 13 + cx, y: y + cy, c: Color(hex: 0x8CC8F0))) }
        }
        if pose.dancing {
            // notas que suben a los lados
            for i in 0..<2 {
                let k = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let x = i == 0 ? 1 : 13, y = 5 - Int(k * 5)
                for (cx, cy) in [(0, 2), (1, 2), (1, 1), (1, 0)] where clip(x + cx, y + cy) && k < 0.85 { out.append(Px(x: x + cx, y: y + cy, c: light)) }
            }
        }
        if let start = scene.confettiStart, t >= start, t - start < confettiLength {
            let k = (t - start) / confettiLength
            let palette = [Color(hex: 0xE7B45B), Color(hex: 0xC84B4B), Color(hex: 0x6CCB8A), Color(hex: 0x5270E8), Color(hex: 0xE58BB0)]
            for i in 0..<16 {
                let x = Int(jitter(i + 100) * 15.99)
                let speed = 0.6 + jitter(i + 200) * 0.8
                let y = Int((k * speed * 18) - jitter(i + 300) * 6) % 40
                if clip(x, y) && k < 0.95 { out.append(Px(x: x, y: y, c: palette[i % palette.count])) }
            }
        }
        return out
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
