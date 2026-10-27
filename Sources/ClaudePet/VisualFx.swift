import Foundation
import CoreGraphics

/// Un punto de un efecto visual. Coordenadas normalizadas (0...1) salvo que se diga otra cosa; color en hexadecimal.
struct FxPixel: Equatable {
    var x: Double
    var y: Double
    var size: Double = 1
    var color: UInt32
    var alpha: Double = 1
}

/// Nucleo puro de los efectos visuales de la isla: todo recibe el tiempo y devuelve datos. Asi se prueba sin ventana.
enum VisualFx {
    /// Numero pseudoaleatorio estable (0...1) por indice.
    static func rnd(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 100_000) / 100_000
    }
}

// MARK: pulso de alerta

enum AlertPulse {
    static let hookTimeout: TimeInterval = 110

    /// Ondas concentricas que salen de la mascota: progreso 0...1 y opacidad que se apaga al alejarse.
    static func rings(at t: TimeInterval, count: Int = 3, period: TimeInterval = 1.6) -> [(progress: Double, alpha: Double)] {
        (0..<count).map { i in
            let p = ((t / period) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            return (p, (1 - p) * 0.55)
        }
    }

    /// Fraccion de tiempo que queda para que el hook se rinda y Claude Code pregunte en la terminal (1 = recien llegado).
    static func remaining(since askedAt: Date, now: Date, timeout: TimeInterval = hookTimeout) -> Double {
        max(0, min(1, 1 - now.timeIntervalSince(askedAt) / timeout))
    }

    static func riskColor(_ risk: PermissionRisk) -> UInt32 {
        switch risk { case .low: return 0x6CCB8A; case .medium: return 0xE7B45B; case .high: return 0xD85C5C }
    }
}

// MARK: reloj de arena

enum Hourglass {
    static let columns = 9, rows = 13
    private static let glass: UInt32 = 0xDCD6CC, sand: UInt32 = 0xE7B45B

    /// Reloj de arena pixel-art en una rejilla de 9x13. `top` es la arena que queda arriba (1 = recien girado, 0 = vacio).
    static func pixels(top: Double) -> [FxPixel] {
        let t = max(0, min(1, top))
        var out: [FxPixel] = []
        func cell(_ x: Int, _ y: Int, _ c: UInt32) { out.append(FxPixel(x: Double(x), y: Double(y), color: c)) }
        for x in 0..<columns { cell(x, 0, glass); cell(x, rows - 1, glass) }
        // cuerpo: se estrecha hacia el centro
        for y in 1..<(rows - 1) {
            let half = y <= 5 ? 4 - (y - 1) : 4 - (rows - 2 - y)
            let w = max(0, half)
            cell(4 - w - 1 < 0 ? 0 : 4 - w - 1 + (w == 0 ? 1 : 0), y, glass); cell(min(8, 4 + w + 1 - (w == 0 ? 1 : 0)), y, glass)
        }
        // arena arriba: de abajo hacia arriba segun lo que queda; abajo: lo contrario
        let topRows = Int((t * 5).rounded()), bottomRows = Int(((1 - t) * 5).rounded())
        for i in 0..<topRows { let y = 5 - i; let w = max(0, 3 - (5 - y)); for x in (4 - w)...(4 + w) { cell(x, y, sand) } }
        for i in 0..<bottomRows { let y = rows - 2 - i; let w = max(0, 3 - (y - 7)); for x in (4 - w)...(4 + w) { cell(x, y, sand) } }
        if t > 0 && t < 1 { for y in 6...7 { cell(4, y, sand) } }       // el hilo de arena que cae
        return out
    }
}

// MARK: nivel de contexto como liquido

enum LiquidModel {
    static func level(used: Int, compactAt: Int) -> Double {
        guard compactAt > 0 else { return 0 }
        return max(0, min(1, Double(used) / Double(compactAt)))
    }

    static func colorHex(_ pressure: ContextPressure) -> UInt32 {
        switch pressure { case .normal: return 0x2966ED; case .caution: return 0xE7B45B; case .critical: return 0xD85C5C }
    }

    /// Olas mas altas cuando el agente trabaja.
    static func amplitude(_ state: PetState) -> Double {
        switch state { case .tool, .thinking, .starting: return 5; case .waiting, .error: return 3.5; case .done, .idle: return 2 }
    }

    /// Linea de la superficie del liquido: `samples` puntos de izquierda a derecha, siempre dentro de [0, height].
    static func surface(at t: TimeInterval, level: Double, amplitude: Double, width: Double, height: Double, samples: Int = 40) -> [CGPoint] {
        let base = height * (1 - max(0, min(1, level)))
        return (0...samples).map { i in
            let x = width * Double(i) / Double(samples)
            let u = x / max(1, width)
            let wave = sin(2 * .pi * (u * 1.5 + t * 0.35)) + 0.5 * sin(2 * .pi * (u * 2.3 - t * 0.5))
            return CGPoint(x: x, y: max(0, min(height, base + amplitude * wave)))
        }
    }
}

// MARK: escenarios pixel-art por estado

enum StageScene {
    /// Particulas del mundo de la mascota en una caja normalizada (0...1). `hour` decide si es de noche.
    static func particles(at t: TimeInterval, state: PetState, hour: Int) -> [FxPixel] {
        var out: [FxPixel] = []
        switch state {
        case .error:
            for x in [0.14, 0.22, 0.3, 0.18, 0.26] { out.append(FxPixel(x: x, y: 0.08 + (x * 7).truncatingRemainder(dividingBy: 0.06), size: 3, color: 0x6B7080, alpha: 0.9)) }   // nube
            for i in 0..<14 {
                let y = (t * (0.8 + VisualFx.rnd(i) * 0.6) + VisualFx.rnd(i + 50)).truncatingRemainder(dividingBy: 1.0)
                if y > 0.16 { out.append(FxPixel(x: 0.1 + VisualFx.rnd(i + 99) * 0.3, y: y, size: 1.5, color: 0x8FB0FF, alpha: 0.8)) }
            }
        case .done:
            let cx = 0.82, cy = 0.2
            for dx in -2...2 { for dy in -2...2 where dx * dx + dy * dy <= 5 { out.append(FxPixel(x: cx + Double(dx) * 0.018, y: cy + Double(dy) * 0.018, size: 2, color: 0xFFD166)) } }
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi + t * 0.8
                out.append(FxPixel(x: cx + cos(a) * 0.09, y: cy + sin(a) * 0.09, size: 1.5, color: 0xFFE9A8, alpha: 0.8))
            }
        case .tool:
            for i in 0..<8 {
                let phase = (t * 2.2 + VisualFx.rnd(i) * 3).truncatingRemainder(dividingBy: 1)
                let dir = (VisualFx.rnd(i + 20) - 0.5) * 0.8
                out.append(FxPixel(x: 0.5 + dir * phase * 0.5, y: 0.82 - phase * 0.45 + phase * phase * 0.5, size: 1.5, color: 0xFF9F43, alpha: 1 - phase))
            }
        case .thinking, .starting:
            for i in 0..<3 {
                let p = (t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                out.append(FxPixel(x: 0.82 + sin(p * 6 + Double(i)) * 0.03, y: 0.5 - p * 0.42, size: 1.5 + p * 2.5, color: 0xDCD6CC, alpha: 0.75 * (1 - p)))
            }
        case .waiting:
            for i in 0..<3 {
                let on = Int(t * 2 + Double(i)) % 3 == 0
                out.append(FxPixel(x: 0.8 + Double(i) * 0.05, y: 0.18, size: 2, color: 0xE7B45B, alpha: on ? 1 : 0.25))
            }
        case .idle:
            if hour < 6 || hour >= 21 {
                for i in 0..<12 {
                    let tw = 0.35 + 0.65 * abs(sin(t * (0.6 + VisualFx.rnd(i) * 0.8) + VisualFx.rnd(i + 7) * 6))
                    out.append(FxPixel(x: 0.08 + VisualFx.rnd(i + 30) * 0.84, y: 0.05 + VisualFx.rnd(i + 60) * 0.4, size: 1 + (i % 3 == 0 ? 1 : 0), color: 0xFFF1B8, alpha: tw))
                }
            }
        }
        return out
    }
}

// MARK: lluvia de lineas

enum LineRain {
    static let duration: TimeInterval = 2.2

    /// Lineas añadidas (verde) y quitadas (rojo) que caen hacia la mascota tras una edicion. Vacio fuera de la ventana de tiempo.
    static func drops(at t: TimeInterval, since: TimeInterval, added: Int, deleted: Int) -> [FxPixel] {
        let age = t - since
        guard age >= 0, age < duration, added + deleted > 0 else { return [] }
        let count = min(24, max(4, (added + deleted) / 2 + 3))
        let greens = Int((Double(added) / Double(added + deleted) * Double(count)).rounded())
        var out: [FxPixel] = []
        for i in 0..<count {
            let y = age * 0.5 - VisualFx.rnd(i + 5) * 0.4          // la ultima gota llega abajo justo al acabar la ventana
            guard y >= 0, y < 0.92 else { continue }
            out.append(FxPixel(x: 0.05 + VisualFx.rnd(i + 11) * 0.9, y: y, size: 1.5, color: i < greens ? 0x6CCB8A : 0xD85C5C, alpha: min(1, (0.92 - y) * 4)))
        }
        return out
    }

    /// Contadores que suben hasta el total en 1,2 s.
    static func counters(age: TimeInterval, added: Int, deleted: Int) -> (added: Int, deleted: Int) {
        let k = max(0, min(1, age / 1.2))
        let eased = 1 - pow(1 - k, 3)
        return (Int((Double(added) * eased).rounded()), Int((Double(deleted) * eased).rounded()))
    }
}

// MARK: evolucion

enum Evolution {
    static func tier(level: Int) -> Int { level >= 8 ? 3 : level >= 5 ? 2 : level >= 3 ? 1 : 0 }
    static func auraAlpha(tier: Int) -> Double { [0, 0.10, 0.16, 0.22][max(0, min(3, tier))] }

    /// Estrellitas que orbitan a la mascota: una por nivel de evolucion.
    static func orbit(at t: TimeInterval, tier: Int) -> [FxPixel] {
        (0..<max(0, min(3, tier))).map { i in
            let a = t * (0.9 + Double(i) * 0.25) + Double(i) * 2.1
            return FxPixel(x: 0.5 + cos(a) * 0.46, y: 0.5 + sin(a) * 0.2 - 0.05, size: 2, color: i == 0 ? 0xFFE9A8 : i == 1 ? 0x9DE3FF : 0xFFB3D1, alpha: 0.5 + 0.5 * abs(sin(a * 1.7)))
        }
    }

    /// Nivel que desbloquea cada atuendo: los primeros desde el principio y la corona para quien lleva tiempo.
    static func unlockLevel(_ outfit: Outfit) -> Int {
        switch outfit { case .beanie, .scarf: return 1; case .bow: return 2; case .glasses: return 3; case .headphones: return 4; case .crown: return 6 }
    }
    static func isUnlocked(_ outfit: Outfit, level: Int) -> Bool { level >= unlockLevel(outfit) }
}

// MARK: trailer de la tarea

enum Trailer {
    struct File: Equatable { let name: String; let added: Int; let deleted: Int }
    enum Phase: Equatable { case intro, files(index: Int), total, finished }
    struct Frame: Equatable { var phase: Phase; var zoom: Double; var added: Int; var deleted: Int; var caption: String }

    static let duration: TimeInterval = 3.0
    static let maxFiles = 5

    /// Los archivos con mas cambios primero, y como mucho cinco.
    static func pick(_ files: [File]) -> [File] { Array(files.sorted { ($0.added + $0.deleted) > ($1.added + $1.deleted) }.prefix(maxFiles)) }

    /// Linea de tiempo de 3 s: presentacion, un archivo tras otro con un zoom lento, y el total que sube.
    static func frame(at t: TimeInterval, files all: [File]) -> Frame {
        let files = pick(all)
        let totalAdded = all.reduce(0) { $0 + $1.added }, totalDeleted = all.reduce(0) { $0 + $1.deleted }
        if t >= duration || all.isEmpty { return Frame(phase: .finished, zoom: 1, added: totalAdded, deleted: totalDeleted, caption: "") }
        if t < 0.4 { return Frame(phase: .intro, zoom: 1, added: 0, deleted: 0, caption: "listo") }
        if t < 2.2 {
            let per = 1.8 / Double(files.count)
            let i = min(files.count - 1, Int((t - 0.4) / per))
            let k = ((t - 0.4) - Double(i) * per) / per
            let runningAdded = files.prefix(i).reduce(0) { $0 + $1.added } + Int(Double(files[i].added) * k)
            let runningDeleted = files.prefix(i).reduce(0) { $0 + $1.deleted } + Int(Double(files[i].deleted) * k)
            return Frame(phase: .files(index: i), zoom: 1 + 0.08 * k, added: runningAdded, deleted: runningDeleted, caption: files[i].name)
        }
        // el total arranca donde acabo la pasada por los archivos (sin bajar) y sube hasta la suma de todos
        let k = (t - 2.2) / 0.8, eased = 1 - pow(1 - k, 3)
        let baseAdded = files.reduce(0) { $0 + $1.added }, baseDeleted = files.reduce(0) { $0 + $1.deleted }
        let shownAdded = baseAdded + Int(Double(totalAdded - baseAdded) * eased), shownDeleted = baseDeleted + Int(Double(totalDeleted - baseDeleted) * eased)
        return Frame(phase: .total, zoom: 1.08, added: shownAdded, deleted: shownDeleted, caption: "\(all.count) \(all.count == 1 ? "archivo" : "archivos")")
    }
}

// MARK: duo

enum DuoScene {
    static let window: TimeInterval = 6
    static let length: TimeInterval = 1.4

    /// Progreso (0...1) del "choca esos cinco" cuando claude y codex terminan con menos de 6 s de diferencia; nil si no toca.
    static func highFive(claudeDoneAt: TimeInterval?, codexDoneAt: TimeInterval?, now: TimeInterval) -> Double? {
        guard let a = claudeDoneAt, let b = codexDoneAt, abs(a - b) <= window else { return nil }
        let start = max(a, b), age = now - start
        guard age >= 0, age < length else { return nil }
        return age / length
    }
}

// MARK: isla liquida

enum Gooey {
    static let duration: TimeInterval = 0.9
    static let delay: TimeInterval = 0.12
    struct Blob: Equatable { var x: Double; var drop: Double; var radius: Double }

    /// Gotas que cuelgan del borde inferior de la isla al abrirse y se reabsorben: con desenfoque y umbral se funden con ella.
    /// `age` en segundos desde que empezo a abrirse. Vacio fuera de la ventana de tiempo.
    static func blobs(age: TimeInterval, count: Int = 4) -> [Blob] {
        let p = (age - delay) / (duration - delay)
        guard p >= 0, p < 1 else { return [] }
        let swing = sin(p * .pi)
        return (0..<count).map { i in
            let jitter = VisualFx.rnd(i + 700)
            return Blob(x: 0.14 + 0.72 * (Double(i) + 0.5 * jitter) / Double(count),
                        drop: (9 + 16 * VisualFx.rnd(i + 710)) * swing,
                        radius: (5 + 4 * VisualFx.rnd(i + 720)) * (0.55 + 0.45 * swing))
        }
    }
}

// MARK: llama de racha

enum StreakFire {
    /// Tamaño de la llama segun los dias seguidos: 0 = nada, 1 = brasa, 2 = llama, 3 = hoguera, 4 = hoguera con chispas.
    static func tier(streak: Int) -> Int { streak <= 0 ? 0 : streak < 3 ? 1 : streak < 7 ? 2 : streak < 14 ? 3 : 4 }

    /// Pixeles de la llama en una rejilla normalizada. Parpadea con el tiempo; arde desde abajo y se afina hacia arriba.
    static func pixels(at t: TimeInterval, streak: Int) -> [FxPixel] {
        let tier = tier(streak: streak)
        guard tier > 0 else { return [] }
        let height = [0, 3, 6, 9, 11][tier], baseWidth = [0, 2, 4, 6, 7][tier]
        var out: [FxPixel] = []
        for row in 0..<height {
            let k = Double(row) / Double(height)                       // 0 abajo, 1 arriba
            // silueta de gota: panza abajo, cuello fino y punta que se mece; el ancho respira con el tiempo
            let profile = pow(1 - pow(k, 1.7), 0.8) * (0.88 + 0.12 * sin(t * 6 + k * 5))
            let width = max(1, Int((Double(baseWidth) * profile).rounded()))
            let sway = sin(t * 5 + Double(row) * 0.7) * 1.1 * k * k
            for col in 0..<width {
                let flicker = VisualFx.rnd(row * 31 + col * 7 + Int(t * 9))
                if k > 0.35 && flicker < 0.18 { continue }              // la punta chisporrotea
                let edge = width > 1 ? abs(Double(col) - Double(width - 1) / 2) / (Double(width - 1) / 2) : 0
                let heat = (1 - k) * 0.6 + (1 - edge) * 0.55            // el centro y la base arden mas
                let color: UInt32 = heat > 0.75 ? 0xFFE08A : heat > 0.5 ? 0xFFB347 : heat > 0.3 ? 0xFF7A33 : 0xD94A2B
                let x = 0.5 + (Double(col) - Double(width - 1) / 2 + sway) / 9
                let y = 1 - (Double(row) + 0.5) / 12
                out.append(FxPixel(x: x, y: y, size: 1, color: color, alpha: 0.95 - k * 0.2))
            }
        }
        if tier >= 4 {
            for i in 0..<3 {
                let p = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                out.append(FxPixel(x: 0.5 + sin(p * 5 + Double(i) * 2) * 0.28, y: 0.18 - p * 0.2, size: 0.7, color: 0xFFE9A8, alpha: 1 - p))
            }
        }
        return out
    }
}
