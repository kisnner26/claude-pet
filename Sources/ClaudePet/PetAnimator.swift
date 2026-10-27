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
    /// Las orejas se levantan un instante (tic o estiramiento).
    var earLift = false
    var yawn = false
    var impatient = false
    /// Ojos contentos (^ ^) mientras la acarician.
    var happy = false
}

/// Lo que la mascota sabe de su entorno para elegir una emocion. Todo llega ya calculado por el controlador.
struct PetScene: Equatable {
    /// Segundos sin que el usuario toque el raton ni el teclado.
    var idleSeconds: TimeInterval = 0
    var state: PetState = .idle
    /// Inicio de la fiesta de confeti tras una tarea larga.
    var confettiStart: TimeInterval?
    var dancing = false
    /// Cuando empezo a abrirse la isla: la mascota entra con un rebote.
    var openedAt: TimeInterval?
    /// Tu ultima decision sobre un permiso (para asentir o negar con la cabeza).
    var decisionAllow: Bool?
    var decisionAt: TimeInterval?
    /// Segundos que lleva esperando tu respuesta a un permiso.
    var waitingFor: TimeInterval = 0
    /// Segundos que el cursor lleva encima de la mascota (caricia).
    var pettingFor: TimeInterval = 0
    var daytime = true
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
    static let entranceLength: TimeInterval = 0.55
    static let decisionLength: TimeInterval = 0.8
    static let impatientAfter: TimeInterval = 15
    static let alarmedAfter: TimeInterval = 40
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

    /// Pequenas conductas propias de la mascota en reposo, sin que nadie las provoque. Deterministas: el tiempo decide.
    /// - mirar alrededor: ~cada 7 s, 1 s, a la izquierda, a la derecha o arriba
    /// - tic de orejas: ~cada 9 s, 0,2 s
    /// - estirarse: ~cada 31 s, 0,7 s; en uno de cada dos estiramientos le sigue un bostezo de 0,8 s
    struct IdleLife: Equatable {
        var look: (dx: Int, dy: Int)? = nil
        var stretch: Double? = nil      // 0...1 dentro del estiramiento
        var yawn = false
        var earLift = false
        static func == (a: IdleLife, b: IdleLife) -> Bool { a.look?.dx == b.look?.dx && a.look?.dy == b.look?.dy && a.stretch == b.stretch && a.yawn == b.yawn && a.earLift == b.earLift }
    }

    static func idleLife(at t: TimeInterval) -> IdleLife {
        var life = IdleLife()
        let lookCycle = 7.0, n = Int((t / lookCycle).rounded(.down))
        let lookStart = jitter(n + 101) * (lookCycle - 1.2), d = t - Double(n) * lookCycle - lookStart
        if d >= 0 && d < 1.0 { let r = jitter(n + 211); life.look = r < 0.4 ? (-1, 0) : r < 0.8 ? (1, 0) : (0, -1) }
        let earCycle = 9.0, m = Int((t / earCycle).rounded(.down))
        let earStart = jitter(m + 307) * (earCycle - 0.4), e = t - Double(m) * earCycle - earStart
        if e >= 0 && e < 0.2 { life.earLift = true }
        let stretchCycle = 31.0, q = Int((t / stretchCycle).rounded(.down))
        let stretchStart = 4 + jitter(q + 401) * (stretchCycle - 10), s = t - Double(q) * stretchCycle - stretchStart
        if s >= 0 && s < 0.7 { life.stretch = s / 0.7; if s > 0.14 && s < 0.56 { life.earLift = true } }
        else if jitter(q + 503) > 0.5, s >= 0.7 && s < 1.5 { life.yawn = true }
        return life
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
        // se inclina un poco hacia el cursor, como si lo siguiera con todo el cuerpo (no solo con los ojos)
        let lean = max(-1, min(1, Double(gaze.x)))
        p.rotation = lean * 3.5
        p.dx = CGFloat(lean) * 0.35

        // vida propia: solo cuando la mascota esta tranquila (en reposo y sin que el cursor la distraiga)
        if scene.state == .idle, scene.idleSeconds < sleepAfter, look.dx == 0, look.dy == 0 {
            let life = idleLife(at: t)
            if let l = life.look { p.eyeDX = l.dx; p.eyeDY = l.dy }
            if let k = life.stretch {
                let w = CGFloat(sin(k * .pi))
                p.scaleY *= 1 + 0.10 * w; p.scaleX *= 1 - 0.04 * w; p.dy -= 0.6 * w
            }
            p.earLift = life.earLift
            if life.yawn { p.yawn = true; p.blink = true }
        }

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

        // entrada: al abrirse la isla la mascota aparece pequeña y rebota hasta su tamaño
        if let o = scene.openedAt, t >= o, t - o < entranceLength {
            let k = (t - o) / entranceLength, c = 1.70158, e = 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2)   // easeOutBack
            let size = CGFloat(0.55 + 0.45 * e)
            p.scaleX *= size; p.scaleY *= size
            p.dy -= CGFloat(1.4 * sin(k * .pi) * (1 - k))
        }
        // decision: asiente al permitir y niega al denegar
        if let at = scene.decisionAt, let allow = scene.decisionAllow, t >= at, t - at < decisionLength {
            let k = (t - at) / decisionLength
            if allow { p.dy += CGFloat(0.9 * sin(k * 4 * .pi) * (1 - k)); p.scaleY *= 1 - 0.05 * CGFloat(abs(sin(k * 4 * .pi))) }
            else { p.dx += CGFloat(1.0 * sin(k * 6 * .pi) * (1 - k)); p.blink = true }
        }
        // impaciencia: si el permiso lleva rato esperando, golpetea el suelo y se balancea
        if scene.waitingFor >= impatientAfter, scene.decisionAt == nil || t - (scene.decisionAt ?? 0) > decisionLength {
            p.dy -= CGFloat(0.35 * abs(sin(t * 9)))
            p.rotation += 2.2 * sin(t * 4.5)
            p.impatient = true
        }

        // la mariposa: la sigue con los ojos mientras revolotea (solo si el cursor no la distrae)
        if scene.state == .idle, look.dx == 0, look.dy == 0, Butterfly.visible(idleSeconds: scene.idleSeconds, hour: scene.daytime ? 12 : 23) {
            let g = Butterfly.gaze(at: t)
            p.eyeDX = g.dx; p.eyeDY = g.dy
        }
        // caricia: si el cursor se queda encima, ronronea con los ojos contentos
        if scene.pettingFor >= Petting.after, !p.dizzy, !p.annoyed {
            p.happy = true; p.blink = false
            p.scaleY *= 1 + 0.015 * CGFloat(sin(t * 18))
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
        if scene.state == .done {
            // destellos que titilan alrededor de la cabeza mientras dura el "listo"
            let spots = [(1, 2), (13, 1), (14, 4), (3, 0)]
            for (i, spot) in spots.enumerated() where Int((t * 5).rounded(.down) + Double(i)) % 3 != 0 {
                for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] where clip(spot.0 + dx, spot.1 + dy) && (dx == 0 && dy == 0 || i % 2 == 0) { out.append(Px(x: spot.0 + dx, y: spot.1 + dy, c: dx == 0 && dy == 0 ? Color(hex: 0xFFF1B8) : light)) }
            }
        }
        if pose.happy { out += Petting.hearts(at: t) }
        if scene.waitingFor >= alarmedAfter, Int(t * 3) % 2 == 0 {
            for (x, y) in [(7, 0), (8, 0), (7, 1), (8, 1), (7, 2), (8, 2), (7, 4), (8, 4)] { out.append(Px(x: x, y: y, c: Color(hex: 0xE7B45B))) }
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
        // orejas: los laterales del cuerpo; un tic las sube una celda
        var pixels = pixels
        if pose.earLift { pixels = pixels.map { ($0.x <= 1 || $0.x >= 14) && $0.y <= 12 ? Px(x: $0.x, y: $0.y - 1, c: $0.c) : $0 } }
        let eyes = pixels.filter(isEye)
        guard !eyes.isEmpty, pose.eyeDX != 0 || pose.eyeDY != 0 || pose.blink || pose.dizzy || pose.wideEyes || pose.yawn || pose.happy else { return pixels }
        var out = pixels.filter { !isEye($0) }
        if pose.yawn { for (x, y) in [(7, 10), (8, 10), (7, 11), (8, 11)] { out.append(Px(x: x, y: y, c: Pal.charcoal)) } }
        let ink = Pal.charcoal
        if pose.happy {
            for cx in [5, 10] { for (x, y) in [(-1, 1), (0, 0), (1, 1)] { out.append(Px(x: cx + x, y: 8 + y, c: ink)) } }
        } else if pose.dizzy {
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
