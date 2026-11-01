import Foundation
import CoreGraphics

/// Pantalla tactil con la webcam, al estilo de Project Sistine (Athalye, Kwok, Webster y Engstrom, MIT):
/// un espejo pequeno delante de la camara hace que esta vea la pantalla de lado; el dedo y su reflejo en el cristal
/// son dos manchas de piel, y cuando se juntan es un toque. La posicion se pasa de la camara a la pantalla con una
/// homografia calibrada tocando varios puntos. Sin espejo hay un modo "aire": la punta del indice mueve el cursor y
/// pellizcar con el pulgar hace clic.
/// Todo lo de este archivo es puro (sin camara ni ventanas) para poder probarlo con imagenes sinteticas.

// MARK: piel

enum SkinFilter {
    /// Piel en YCrCb, el umbral clasico: es mucho mas estable con la luz que el RGB.
    static func isSkin(r: Int, g: Int, b: Int, cr: ClosedRange<Double> = 133...175, cb: ClosedRange<Double> = 77...127) -> Bool {
        let y = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        guard y > 40 else { return false }
        let crv = (Double(r) - y) * 0.713 + 128, cbv = (Double(b) - y) * 0.564 + 128
        return cr.contains(crv) && cb.contains(cbv)
    }
}

// MARK: manchas

struct Blob: Equatable {
    var minX: Int, maxX: Int, minY: Int, maxY: Int
    var area: Int
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

enum BlobFinder {
    /// Componentes conexas (4 vecinos) de una mascara de 0 y 1. Devuelve las de al menos `minArea`, de mayor a menor.
    static func find(mask: [UInt8], width w: Int, height h: Int, minArea: Int) -> [Blob] {
        guard mask.count == w * h, w > 0, h > 0 else { return [] }
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Blob] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where mask[start] != 0 && !seen[start] {
            var b = Blob(minX: start % w, maxX: start % w, minY: start / w, maxY: start / w, area: 0)
            stack.removeAll(keepingCapacity: true)
            stack.append(start); seen[start] = true
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                b.area += 1
                b.minX = min(b.minX, x); b.maxX = max(b.maxX, x); b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
                if x > 0, mask[i - 1] != 0, !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
                if x < w - 1, mask[i + 1] != 0, !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
                if y > 0, mask[i - w] != 0, !seen[i - w] { seen[i - w] = true; stack.append(i - w) }
                if y < h - 1, mask[i + w] != 0, !seen[i + w] { seen[i + w] = true; stack.append(i + w) }
            }
            if b.area >= minArea { out.append(b) }
        }
        return out.sorted { $0.area > $1.area }
    }
}

// MARK: lectura del toque

enum TouchPhase: String, Equatable {
    case none, hover, touch
    var label: String { switch self { case .none: return "sin dedo"; case .hover: return "flotando"; case .touch: return "toque" } }
}

struct TouchParams: Codable, Equatable {
    /// Separacion entre el dedo y su reflejo (en pixeles de la imagen reducida) por debajo de la cual es un toque.
    var touchGap = 2.0
    /// Hasta aqui el dedo "flota" sobre la pantalla y solo mueve el cursor.
    var hoverGap = 14.0
    var minArea = 24
    /// Cuanto tienen que solaparse las dos manchas en horizontal (fraccion de la mas estrecha).
    var minOverlap = 0.3
    /// Si el dedo y el reflejo se funden en una sola mancha tras estar casi juntos, se sigue contando como toque.
    var mergeGap = 4.0
}

struct TouchReading: Equatable {
    var phase: TouchPhase = .none
    /// Punto en la imagen de la camara, de 0 a 1.
    var x = 0.0, y = 0.0
    var gap = 0.0
    var blobs: [Blob] = []
}

enum MirrorTouch {
    /// Sistine: se toman las dos manchas mas grandes que se solapan en horizontal; el punto es el medio del hueco
    /// entre la parte baja de la de arriba y la alta de la de abajo; la distancia decide toque o flotar.
    static func read(blobs: [Blob], width w: Int, height h: Int, params p: TouchParams, previous: TouchReading?) -> TouchReading {
        var r = TouchReading(blobs: Array(blobs.prefix(2)))
        if blobs.count >= 2 {
            let pair = blobs.prefix(2).sorted { $0.minY < $1.minY }
            let (up, low) = (pair[0], pair[1])
            let overlap = min(up.maxX, low.maxX) - max(up.minX, low.minX) + 1
            guard overlap > 0, Double(overlap) / Double(min(up.width, low.width)) >= p.minOverlap else { return r }
            let gap = max(0, Double(low.minY - up.maxY - 1))
            r.gap = gap
            r.x = (Double(max(up.minX, low.minX)) + Double(min(up.maxX, low.maxX))) / 2 / Double(w)
            r.y = (Double(up.maxY) + Double(low.minY)) / 2 / Double(h)
            r.phase = gap <= p.touchGap ? .touch : gap <= p.hoverGap ? .hover : .none
        } else if blobs.count == 1, let prev = previous, prev.phase != .none, prev.gap <= p.mergeGap {
            // se han fundido: el dedo esta pegado a su reflejo
            r.phase = .touch; r.x = prev.x; r.y = prev.y; r.gap = 0
        }
        return r
    }
}

// MARK: modo aire (pellizco)

enum Pinch {
    static let engage = 0.28, release = 0.42
    /// Pulgar e indice juntos, medidos respecto al tamano de la mano para que no dependa de la distancia a la camara.
    static func ratio(thumb: CGPoint, index: CGPoint, wrist: CGPoint, middleBase: CGPoint) -> Double {
        let size = max(0.001, hypot(Double(wrist.x - middleBase.x), Double(wrist.y - middleBase.y)))
        return hypot(Double(thumb.x - index.x), Double(thumb.y - index.y)) / size
    }
    /// Con histeresis: se cierra por debajo de `engage` y no se abre hasta pasar `release`.
    static func closed(ratio: Double, wasClosed: Bool) -> Bool { wasClosed ? ratio < release : ratio < engage }
}

// MARK: homografia

struct Homography: Codable, Equatable {
    var m: [Double]      // 3 x 3 por filas

    static let identity = Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let d = m[6] * x + m[7] * y + m[8]
        guard abs(d) > 1e-12 else { return (x, y) }
        return ((m[0] * x + m[1] * y + m[2]) / d, (m[3] * x + m[4] * y + m[5]) / d)
    }

    /// Minimos cuadrados (DLT) con h33 = 1. Hacen falta al menos 4 pares y que no esten todos alineados.
    static func fit(from: [(Double, Double)], to: [(Double, Double)]) -> Homography? {
        guard from.count == to.count, from.count >= 4 else { return nil }
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)       // 8 x (8 + b)
        func add(_ row: [Double], _ b: Double) {
            for i in 0..<8 { for j in 0..<8 { ata[i][j] += row[i] * row[j] }; ata[i][8] += row[i] * b }
        }
        for (f, t) in zip(from, to) {
            add([f.0, f.1, 1, 0, 0, 0, -f.0 * t.0, -f.1 * t.0], t.0)
            add([0, 0, 0, f.0, f.1, 1, -f.0 * t.1, -f.1 * t.1], t.1)
        }
        // eliminacion gaussiana con pivote parcial
        for c in 0..<8 {
            var piv = c
            for r in (c + 1)..<8 where abs(ata[r][c]) > abs(ata[piv][c]) { piv = r }
            guard abs(ata[piv][c]) > 1e-10 else { return nil }
            ata.swapAt(c, piv)
            for r in 0..<8 where r != c {
                let k = ata[r][c] / ata[c][c]
                if k != 0 { for j in c...8 { ata[r][j] -= k * ata[c][j] } }
            }
        }
        let h = (0..<8).map { ata[$0][8] / ata[$0][$0] }
        return Homography(m: h + [1])
    }

    /// Error medio (en unidades de destino) de la homografia sobre sus propios pares.
    func meanError(from: [(Double, Double)], to: [(Double, Double)]) -> Double {
        guard !from.isEmpty else { return 0 }
        return zip(from, to).map { f, t in let p = apply(f.0, f.1); return hypot(p.x - t.0, p.y - t.1) }.reduce(0, +) / Double(from.count)
    }
}

// MARK: calibracion

enum ScreenTouchCalibration {
    /// Nueve puntos: las cuatro esquinas, los cuatro lados y el centro, con margen. Tocar los cuatro cuadrantes
    /// de la pantalla no basta: con mas puntos el ajuste aguanta mejor el ruido.
    static let targets: [(Double, Double)] = {
        let a = 0.07, b = 0.5, c = 0.93
        return [(a, a), (b, a), (c, a), (a, b), (b, b), (c, b), (a, c), (b, c), (c, c)]
    }()

    static func screenPoints(in bounds: CGRect) -> [(Double, Double)] {
        targets.map { (Double(bounds.minX) + $0.0 * Double(bounds.width), Double(bounds.minY) + $0.1 * Double(bounds.height)) }
    }
}

// MARK: suavizado y antirrebote

/// Filtro exponencial que se vuelve mas rapido cuando el dedo se mueve rapido (como el 1 euro filter, simplificado):
/// quieto no tiembla y en movimiento no se queda atras.
struct PointSmoother {
    private(set) var x = 0.0, y = 0.0
    private var primed = false
    var slow = 0.25, fast = 0.85, speedForFast = 60.0

    mutating func reset() { primed = false }
    mutating func add(_ nx: Double, _ ny: Double) -> (x: Double, y: Double) {
        guard primed else { x = nx; y = ny; primed = true; return (x, y) }
        let speed = hypot(nx - x, ny - y)
        let a = slow + (fast - slow) * min(1, speed / speedForFast)
        x += (nx - x) * a; y += (ny - y) * a
        return (x, y)
    }
}

/// Un toque empieza tras `down` fotogramas seguidos y termina tras `up` sin el: un parpadeo del detector no suelta el boton.
struct TouchDebouncer {
    var down = 2, up = 3
    private(set) var pressed = false
    private var run = 0

    enum Edge: Equatable { case none, pressed, released }
    mutating func feed(_ touching: Bool) -> Edge {
        if touching == pressed { run = 0; return .none }
        run += 1
        if run >= (touching ? down : up) { pressed = touching; run = 0; return touching ? .pressed : .released }
        return .none
    }
}
