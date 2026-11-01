import Foundation
import CoreGraphics

/// Trackpad como pantalla tactil: en vez de mover el cursor por desplazamiento, el trackpad se convierte en una
/// superficie absoluta (como una tableta grafica). Tocar la esquina de arriba a la izquierda del trackpad lleva el
/// cursor a la esquina de arriba a la izquierda de la pantalla. Sin camara y sin hardware extra.
/// Esta parte es pura (sin framework privado ni eventos) para poder probarla con datos sinteticos.

/// Un contacto tal como lo entrega MultitouchSupport. El orden y los tamanos son los del framework (96 bytes);
/// las pruebas comprueban el tamano y los desplazamientos de los campos que se leen.
struct MTTouchRaw {
    var frame: Int32 = 0
    var timestamp: Double = 0
    var identifier: Int32 = 0
    var state: Int32 = 0
    var fingerId: Int32 = 0
    var handId: Int32 = 0
    var nx: Float = 0, ny: Float = 0          // posicion normalizada, de 0 a 1, con el origen abajo a la izquierda
    var vx: Float = 0, vy: Float = 0
    var zTotal: Float = 0                     // presion / tamano del contacto
    var unknown3: Int32 = 0
    var angle: Float = 0
    var major: Float = 0, minor: Float = 0
    var ax: Float = 0, ay: Float = 0, avx: Float = 0, avy: Float = 0
    var unknown4a: Int32 = 0, unknown4b: Int32 = 0
    var zDensity: Float = 0
}

struct TrackpadFinger: Equatable {
    var id: Int
    var x: Double          // 0...1, origen abajo a la izquierda
    var y: Double
    var pressure: Double
}

enum TrackpadTouch {
    /// Estados de MultitouchSupport: 0 sin tocar, 1 empezando, 2 flotando, 3 apoyando, 4 tocando, 5 soltando, 6 quedando, 7 saliendo.
    /// Solo cuentan 3 y 4: un dedo flotando todavia no esta en el trackpad.
    static func isDown(state: Int32) -> Bool { state == 3 || state == 4 }

    static func fingers(from touches: UnsafePointer<MTTouchRaw>, count: Int) -> [TrackpadFinger] {
        (0..<max(0, count)).compactMap { i in
            let t = touches[i]
            guard isDown(state: t.state) else { return nil }
            return TrackpadFinger(id: Int(t.identifier), x: Double(t.nx), y: Double(t.ny), pressure: Double(t.zTotal))
        }
    }

    /// Un trackpad es casi 16:10 (entre 1:1 y 2:1); la Touch Bar mide mas de 10:1 y no debe mover el cursor.
    static func isTrackpadShape(width: Double, height: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        let ratio = width / height
        return ratio >= 1.0 && ratio <= 2.2
    }

    /// Un solo dedo apoyado mueve el cursor; con dos o mas se dejan los gestos del sistema (desplazar, zoom, girar).
    static func pointer(_ fingers: [TrackpadFinger]) -> TrackpadFinger? { fingers.count == 1 ? fingers[0] : nil }

    /// Del trackpad (0...1, origen abajo a la izquierda) a la pantalla (origen arriba a la izquierda).
    /// `margin` deja una franja util en los bordes: asi las esquinas de la pantalla se alcanzan sin tener que tocar el borde exacto.
    static func map(x: Double, y: Double, margin: Double, in screen: CGRect) -> CGPoint {
        let m = min(0.3, max(0, margin))
        func norm(_ v: Double) -> Double { min(1, max(0, (v - m) / (1 - 2 * m))) }
        return CGPoint(x: Double(screen.minX) + norm(x) * Double(screen.width - 1),
                       y: Double(screen.minY) + norm(1 - y) * Double(screen.height - 1))
    }
}

/// Suaviza el salto de un dedo a otro y el temblor del contacto: rapido cuando el dedo corre, firme cuando esta quieto.
struct TrackpadSmoother {
    private(set) var x = 0.0, y = 0.0
    private var primed = false
    var slow = 0.35, fast = 1.0, speedForFast = 40.0

    mutating func reset() { primed = false }
    mutating func add(_ nx: Double, _ ny: Double) -> (x: Double, y: Double) {
        guard primed else { x = nx; y = ny; primed = true; return (x, y) }
        let a = slow + (fast - slow) * min(1, hypot(nx - x, ny - y) / speedForFast)
        x += (nx - x) * a; y += (ny - y) * a
        return (x, y)
    }
}
