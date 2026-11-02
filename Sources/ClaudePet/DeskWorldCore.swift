import Foundation
import CoreGraphics

/// Escritorio vivo: las mascotas se posan en tus ventanas reales, caminan por el Dock, se asoman por detras y se apartan si arrastras
/// una ventana encima. Esta parte es pura (geometria y fisica sin ventanas de verdad) para poder probarla con ventanas inventadas.

struct DeskWindow: Equatable {
    var id: Int
    var pid: Int32
    var owner: String
    var title: String
    /// En coordenadas de AppKit: el origen abajo a la izquierda de la pantalla principal.
    var frame: CGRect
}

enum DeskGeo {
    /// CGWindowList da las ventanas con el origen arriba a la izquierda de la pantalla principal; AppKit lo tiene abajo.
    static func appKit(_ cg: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// Solo cuentan ventanas normales y de un tamano con el que se pueda hacer algo: no barras, no sombras, no las nuestras.
    static func isUsable(layer: Int, frame: CGRect, alpha: Double, isOwn: Bool) -> Bool {
        !isOwn && layer == 0 && alpha > 0.05 && frame.width >= 160 && frame.height >= 80
    }

    /// Tramos del borde superior de `windows[index]` que ninguna ventana mas al frente tapa. `windows` va de mas al frente a mas al fondo.
    static func visibleTop(of index: Int, in windows: [DeskWindow], minLength: CGFloat = 24) -> [ClosedRange<CGFloat>] {
        guard windows.indices.contains(index) else { return [] }
        let w = windows[index].frame
        var segments: [ClosedRange<CGFloat>] = [w.minX...w.maxX]
        for front in windows[..<index] {
            let f = front.frame
            guard f.minY < w.maxY, f.maxY > w.maxY else { continue }          // esa ventana no cruza la linea del borde
            segments = segments.flatMap { s -> [ClosedRange<CGFloat>] in
                guard f.maxX > s.lowerBound, f.minX < s.upperBound else { return [s] }
                var out: [ClosedRange<CGFloat>] = []
                if f.minX > s.lowerBound { out.append(s.lowerBound...f.minX) }
                if f.maxX < s.upperBound { out.append(f.maxX...s.upperBound) }
                return out
            }
        }
        return segments.filter { $0.upperBound - $0.lowerBound >= minLength }
    }

    /// El punto de un tramo visible mas cercano a `x`, sin salirse por los lados (deja `margin` a cada lado si cabe).
    static func nearest(_ x: CGFloat, in segments: [ClosedRange<CGFloat>], margin: CGFloat = 0) -> CGFloat? {
        var best: (CGFloat, CGFloat)?
        for s in segments {
            let lo = s.lowerBound + min(margin, (s.upperBound - s.lowerBound) / 2), hi = s.upperBound - min(margin, (s.upperBound - s.lowerBound) / 2)
            let p = min(max(x, lo), hi)
            let d = abs(p - x)
            if best == nil || d < best!.1 { best = (p, d) }
        }
        return best?.0
    }
}

/// Donde pisa la mascota.
struct DeskSurface: Equatable {
    var y: CGFloat
    /// Indice de la ventana que la sostiene; nil es el suelo (la parte de arriba del Dock o de la pantalla).
    var window: Int?
}

enum DeskPhysics {
    /// Medio ancho con el que se apoya y cuanto puede subir de un salto sobre donde esta.
    static let half: CGFloat = 30
    static let reach: CGFloat = 26
    static let gravity: CGFloat = 2600

    /// El suelo mas alto bajo los pies: el borde superior visible de una ventana bajo el centro, a la altura de los pies o un poco por encima
    /// (puede subir de un salto); si no hay ninguna, el suelo de la pantalla.
    static func support(centerX: CGFloat, feetY: CGFloat, windows: [DeskWindow], floorY: CGFloat, reach: CGFloat = reach) -> DeskSurface {
        var best = DeskSurface(y: floorY, window: nil)
        for i in windows.indices {
            let top = windows[i].frame.maxY
            guard top > best.y, top <= feetY + reach else { continue }
            guard DeskGeo.visibleTop(of: i, in: windows).contains(where: { $0.contains(centerX) }) else { continue }
            best = DeskSurface(y: top, window: i)
        }
        return best
    }

    struct Body: Equatable {
        var x: CGFloat
        var feetY: CGFloat
        var vy: CGFloat = 0
        var grounded: Bool { vy == 0 }
    }

    /// Cae con gravedad hasta el suelo; si el suelo esta por encima (una ventana subio bajo ella) sube de un salto rapido.
    static func settle(_ b: Body, ground: CGFloat, dt: CGFloat) -> Body {
        var n = b
        if ground > b.feetY {
            n.feetY = min(ground, b.feetY + max(260, (ground - b.feetY) * 14) * dt)
            n.vy = n.feetY >= ground ? 0 : 1
            return n
        }
        n.vy = b.vy + gravity * dt
        n.feetY = b.feetY - n.vy * dt
        if n.feetY <= ground { n.feetY = ground; n.vy = 0 }
        return n
    }

    /// Camina hacia `target`: velocidad constante, frena al llegar y dice hacia donde mira (-1 izquierda, 1 derecha).
    static func walk(x: CGFloat, toward target: CGFloat, dt: CGFloat, speed: CGFloat = 150) -> (x: CGFloat, walking: Bool, facing: CGFloat) {
        let d = target - x
        guard abs(d) > 1.5 else { return (target, false, 0) }
        let step = min(abs(d), speed * dt)
        return (x + (d > 0 ? step : -step), true, d > 0 ? 1 : -1)
    }

    /// Si una ventana (que no es su suelo) le cae encima, a donde se aparta: el lado libre mas cercano. nil si nada le estorba.
    static func sidestep(centerX: CGFloat, feetY: CGFloat, height: CGFloat, windows: [DeskWindow], supporting: Int?, margin: CGFloat = 10) -> CGFloat? {
        let body = CGRect(x: centerX - half, y: feetY + 4, width: half * 2, height: max(1, height - 8))
        for i in windows.indices where i != supporting {
            let f = windows[i].frame
            // una ventana cuyo borde queda a sus pies o por debajo es un suelo posible, no un estorbo
            guard f.maxY > feetY + reach, f.intersects(body) else { continue }
            let left = f.minX - half - margin, right = f.maxX + half + margin
            return abs(centerX - left) <= abs(centerX - right) ? left : right
        }
        return nil
    }
}

/// Donde se coloca una mascota respecto a una ventana segun el sitio que haya alrededor.
enum DeskPlacement: Equatable {
    case above(feetY: CGFloat)                 // encima del borde superior
    case inside(feetY: CGFloat)                // dentro, bajo la barra de titulo: la ventana llega al tope de la pantalla
    case side(x: CGFloat, feetY: CGFloat)      // asomada por un lado: la mitad del cuerpo detras de la ventana

    static let bodyHeight: CGFloat = 96
    static let sideNeeded: CGFloat = 70

    /// Perchada: encima si cabe entera; si no, dentro, sin salirse por arriba de la pantalla.
    static func perch(window: CGRect, screen: CGRect) -> DeskPlacement {
        screen.maxY - window.maxY >= bodyHeight + 4 ? .above(feetY: window.maxY) : .inside(feetY: min(window.maxY, screen.maxY - bodyHeight - 4))
    }

    /// Asomada: la cabeza por encima del borde de arriba si cabe; si no, por el lado derecho o izquierdo con sitio; y si nada cabe, perchada dentro.
    static func peek(window: CGRect, screen: CGRect, depth: CGFloat) -> DeskPlacement {
        if screen.maxY - window.maxY >= bodyHeight - depth + 6 { return .above(feetY: window.maxY - depth) }
        let feet = max(window.minY + 24, window.maxY - 170)
        if screen.maxX - window.maxX >= sideNeeded { return .side(x: window.maxX + 10, feetY: feet) }
        if window.minX - screen.minX >= sideNeeded { return .side(x: window.minX - 10, feetY: feet) }
        return perch(window: window, screen: screen)
    }
}

/// Un salto en parabola de un punto a otro (para subirse a una ventana o bajar al suelo).
struct DeskLeap: Equatable {
    var from: CGPoint
    var to: CGPoint
    var start: TimeInterval
    var duration: TimeInterval
    var apex: CGFloat

    static func make(from: CGPoint, to: CGPoint, now: TimeInterval) -> DeskLeap {
        let distance = hypot(to.x - from.x, to.y - from.y)
        return DeskLeap(from: from, to: to, start: now, duration: 0.35 + min(0.5, Double(distance) / 1400), apex: 26 + min(80, distance / 6))
    }

    func position(at now: TimeInterval) -> (point: CGPoint, done: Bool) {
        let t = CGFloat(min(1, max(0, (now - start) / duration)))
        let ease = t * t * (3 - 2 * t)
        return (CGPoint(x: from.x + (to.x - from.x) * ease, y: from.y + (to.y - from.y) * t + 4 * apex * t * (1 - t)), t >= 1)
    }
}

/// Lo que quiere hacer una mascota segun lo que hace su agente.
enum DeskGoal: Equatable {
    case perch      // posada sobre la ventana donde trabaja el agente
    case peek       // asomada por detras de esa ventana: el agente espera tu permiso
    case rest       // en el suelo (encima del Dock), esperando

    /// `secondsSinceBusy`: cuanto lleva el agente sin trabajar; sigue posada un rato tras terminar antes de bajar.
    static func decide(state: PetState, hasWindow: Bool, secondsSinceBusy: TimeInterval, linger: TimeInterval = 8) -> DeskGoal {
        guard hasWindow else { return .rest }
        switch state {
        case .waiting: return .peek
        case .thinking, .tool, .starting, .error, .done: return .perch
        case .idle: return secondsSinceBusy < linger ? .perch : .rest
        }
    }

    /// Donde se coloca sobre el borde de la ventana (fraccion del ancho): claude a la derecha del centro y codex mas a la derecha, para que no se pisen.
    static func perchFraction(claude: Bool, both: Bool) -> CGFloat { both ? (claude ? 0.64 : 0.82) : 0.75 }

    /// Un vaiven suave mientras trabaja, para que se vea que esta ocupada y no clavada en la ventana.
    static func pace(time: TimeInterval, working: Bool, amplitude: CGFloat = 34) -> CGFloat { working ? CGFloat(sin(time * 2 * .pi / 9)) * amplitude : 0 }
}

/// Llevar el archivo: cuando el agente edita algo, la mascota lo muestra con el icono de su tipo y lo deja en la ventana del editor.
enum FileCarry {
    private static let editTools: Set<String> = ["edit", "write", "multiedit", "notebookedit", "apply_patch", "patch", "str_replace", "create"]

    /// El nombre y la extension del archivo si la herramienta lo modifica; nil para leer, buscar o ejecutar.
    static func editedFile(tool: String, target: String) -> (name: String, ext: String)? {
        guard editTools.contains(tool.lowercased()) else { return nil }
        let name = (target as NSString).lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return (name, (name as NSString).pathExtension.lowercased())
    }

    static let editors = ["xcode", "visual studio code", "code", "cursor", "zed", "sublime", "textmate", "nova", "bbedit", "intellij", "pycharm", "webstorm", "android studio", "windsurf", "textedit"]

    static func isEditor(_ owner: String) -> Bool { let o = owner.lowercased(); return editors.contains { o == $0 || o.contains($0) } }

    /// Donde cae el archivo: la ventana de un editor (mejor la que menciona el archivo o el proyecto) y, si no hay, la ventana del agente.
    static func destination(file: String, project: String, windows: [DeskWindow], host: Int?) -> CGPoint? {
        let editors = windows.indices.filter { isEditor(windows[$0].owner) }
        let named = editors.first { windows[$0].title.lowercased().contains(file.lowercased()) }
            ?? editors.first { !project.isEmpty && windows[$0].title.lowercased().contains(project.lowercased()) }
            ?? editors.first
        guard let i = named ?? host, windows.indices.contains(i) else { return nil }
        let f = windows[i].frame
        return CGPoint(x: f.midX, y: f.maxY - 24)
    }
}

/// El vuelo de un archivo: sube sobre la cabeza de la mascota, cruza en arco hasta su destino y se posa encogiendose.
struct FileFlight: Equatable {
    var from: CGPoint
    var to: CGPoint
    var start: TimeInterval
    static let hold: TimeInterval = 0.55, fly: TimeInterval = 0.85, land: TimeInterval = 0.3
    static var total: TimeInterval { hold + fly + land }

    struct Frame: Equatable { var point: CGPoint; var scale: CGFloat; var alpha: CGFloat; var done: Bool }

    func frame(at now: TimeInterval) -> Frame {
        let t = now - start
        if t >= Self.total { return Frame(point: to, scale: 0, alpha: 0, done: true) }
        if t < Self.hold {
            // aparece sobre la cabeza y crece
            let k = CGFloat(max(0, t) / Self.hold)
            return Frame(point: CGPoint(x: from.x, y: from.y + 6 * k), scale: 0.3 + 0.7 * k, alpha: min(1, k * 2.5), done: false)
        }
        if t < Self.hold + Self.fly {
            let k = CGFloat((t - Self.hold) / Self.fly), e = k * k * (3 - 2 * k)
            let arc = 4 * 70 * k * (1 - k)
            return Frame(point: CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + 6 + (to.y - from.y - 6) * e + arc), scale: 1, alpha: 1, done: false)
        }
        let k = CGFloat((t - Self.hold - Self.fly) / Self.land)
        return Frame(point: to, scale: 1 - 0.7 * k, alpha: 1 - k, done: false)
    }
}
