import Foundation
import CoreGraphics

/// Las animaciones de sacar a una mascota de la isla y de volver a meterla. Es solo matematica (posicion, escala, giro, particulas):
/// quien las dibuja es el escritorio. Todo es determinista, asi que se prueba sin ventanas.
enum DeskPortal {
    static let emergeDuration: TimeInterval = 0.85
    static let diveDuration: TimeInterval = 0.62
    static let popDuration: TimeInterval = 0.55

    /// Como se ve la mascota en un instante.
    struct Frame: Equatable {
        var center: CGPoint
        var scale: CGFloat = 1
        /// Aplastado al caer: >0 ensancha y achata, <0 estira.
        var squash: CGFloat = 0
        var rotation: Double = 0
        var alpha: CGFloat = 1
        var done = false
    }

    static func clamp01(_ x: Double) -> CGFloat { CGFloat(min(1, max(0, x))) }
    static func easeOut(_ k: CGFloat) -> CGFloat { 1 - (1 - k) * (1 - k) * (1 - k) }
    static func easeIn(_ k: CGFloat) -> CGFloat { k * k * k }
    static func easeInOut(_ k: CGFloat) -> CGFloat { k * k * (3 - 2 * k) }

    /// Curva de Bezier cuadratica.
    static func bezier(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    /// El punto de control del arco: por encima de la recta, mas alto cuanto mas lejos va.
    static func arcControl(from a: CGPoint, to b: CGPoint, lift: CGFloat? = nil, side: CGFloat = 0) -> CGPoint {
        let d = hypot(b.x - a.x, b.y - a.y)
        let up = lift ?? (110 + d / 5)
        return CGPoint(x: (a.x + b.x) / 2 + side * d * 0.18, y: max(a.y, b.y) + up)
    }

    // MARK: salir de la isla

    /// Emerge del resplandor de la isla (0 a 14 %), vuela en arco (14 a 66 %) y cae con un aplastado y un rebote (66 a 100 %).
    static func emerge(from: CGPoint, to: CGPoint, at t: TimeInterval) -> Frame {
        let p = clamp01(t / emergeDuration)
        if t >= emergeDuration { return Frame(center: to, done: true) }
        let launch: CGFloat = 0.14, landAt: CGFloat = 0.66
        if p < launch {
            let k = p / launch
            return Frame(center: CGPoint(x: from.x, y: from.y - 6 + 8 * easeOut(k)), scale: 0.12 + 0.4 * easeOut(k), rotation: 0, alpha: min(1, k * 3))
        }
        if p < landAt {
            let k = (p - launch) / (landAt - launch)
            let e = easeInOut(k)
            let c = bezier(from, arcControl(from: from, to: to), to, e)
            return Frame(center: c, scale: 0.52 + 0.58 * easeOut(k), rotation: 14 * sin(Double(k) * 2 * .pi) * Double(1 - k * 0.4), alpha: 1)
        }
        let k = (p - landAt) / (1 - landAt)
        // al caer se aplasta, rebota una vez y se asienta
        let squash = 0.26 * sin(k * .pi) * (1 - 0.55 * k)
        let hop = 16 * max(0, sin((k - 0.25) * .pi / 0.75)) * (1 - k)
        return Frame(center: CGPoint(x: to.x, y: to.y + (k > 0.25 ? hop : 0)), scale: 1.1 - 0.1 * easeOut(k), squash: squash, rotation: 0, alpha: 1)
    }

    // MARK: sacarla arrastrando

    /// Aparece bajo el cursor con un "pop" elastico: se pasa de tamano y se asienta.
    static func pop(at t: TimeInterval) -> Frame {
        if t >= popDuration { return Frame(center: .zero, done: true) }
        let k = t / popDuration
        let spring = 1 + (0.28 - 1) * exp(-6.5 * k) * cos(12.5 * k)
        return Frame(center: .zero, scale: CGFloat(spring), squash: CGFloat(0.12 * exp(-5 * k) * sin(14 * k)), rotation: 8 * exp(-4 * k) * sin(16 * k), alpha: min(1, CGFloat(k * 7)))
    }

    // MARK: volver a la isla

    /// Se lanza hacia la isla en una curva, girando y encogiendose cada vez mas rapido, y se apaga al entrar.
    static func dive(from: CGPoint, to: CGPoint, at t: TimeInterval) -> Frame {
        if t >= diveDuration { return Frame(center: to, scale: 0.12, rotation: 540, alpha: 0, done: true) }
        let p = clamp01(t / diveDuration)
        let e = easeIn(p) * 0.85 + easeInOut(p) * 0.15
        let side: CGFloat = from.x < to.x ? -1 : 1
        let c = bezier(from, arcControl(from: from, to: to, lift: 40 + hypot(to.x - from.x, to.y - from.y) / 6, side: side), to, e)
        return Frame(center: c, scale: 1 - 0.88 * e, squash: -0.22 * sin(e * .pi), rotation: Double(540 * e), alpha: p < 0.82 ? 1 : max(0, (1 - p) / 0.18))
    }

    // MARK: efectos

    struct Spark: Equatable {
        var point: CGPoint
        var size: CGFloat
        var alpha: CGFloat
        /// 0 = color de la mascota, 1 = blanco, 2 = dorado.
        var tone: Int
    }

    /// Chispas que salen en todas direcciones y se apagan. `t` va de 0 a 1.
    static func burst(center: CGPoint, t: Double, seed: Int, count: Int = 14, radius: CGFloat = 70) -> [Spark] {
        let k = clamp01(t)
        guard k < 1 else { return [] }
        return (0..<count).map { i in
            let h = hash(seed &* 31 &+ i)
            let angle = (Double(i) / Double(count) + (h - 0.5) * 0.35) * 2 * .pi
            let reach = radius * CGFloat(0.55 + 0.45 * hash(seed &* 17 &+ i &+ 99))
            let d = reach * easeOut(k)
            let rise = 14 * k   // un poco de gravedad al reves: las chispas suben
            return Spark(point: CGPoint(x: center.x + CGFloat(cos(angle)) * d, y: center.y + CGFloat(sin(angle)) * d + rise),
                         size: CGFloat(3 + 4 * (1 - Double(k)) * (0.5 + hash(seed &+ i &+ 7))), alpha: (1 - k) * (1 - k), tone: i % 3)
        }
    }

    /// Onda de choque: radio y opacidad.
    static func ring(t: Double, max radius: CGFloat = 64, delay: Double = 0) -> (radius: CGFloat, alpha: CGFloat)? {
        let k = clamp01((t - delay) / 0.45)
        guard t >= delay, k < 1 else { return nil }
        return (radius * easeOut(k), (1 - k) * 0.85)
    }

    /// Estela: puntos del camino ya recorrido, cada vez mas tenues. `path` da la posicion en un instante.
    static func trail(path: (TimeInterval) -> CGPoint, t: TimeInterval, count: Int = 9, spacing: TimeInterval = 0.035) -> [Spark] {
        (1...count).compactMap { i in
            let tt = t - Double(i) * spacing
            guard tt > 0 else { return nil }
            let fade = 1 - CGFloat(i) / CGFloat(count + 1)
            return Spark(point: path(tt), size: 11 * fade, alpha: 0.5 * fade, tone: 0)
        }
    }

    /// Numero pseudoaleatorio estable (0...1) a partir de un entero.
    static func hash(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}
