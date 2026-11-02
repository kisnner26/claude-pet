import Foundation

/// Cronotipo de humano e IA: a que horas trabajas mas y a cuales fallas mas. Los eventos de memoria solo guardan los ultimos 400
/// (un par de dias), asi que aqui se resume por hora del dia y esto si dura. No guarda proyectos ni contenido, solo contadores.
struct HourBucket: Codable, Equatable {
    var tools = 0
    var errors = 0
    var sessions = 0
    var permissions = 0
    /// Pulsaciones (solo el recuento, de `TypingMonitor`). No entra en `activity` para no mover los umbrales del resto.
    var typed = 0

    init() {}
    // los archivos de antes no tienen `typed`: se leen igual
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tools = try c.decodeIfPresent(Int.self, forKey: .tools) ?? 0
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        permissions = try c.decodeIfPresent(Int.self, forKey: .permissions) ?? 0
        typed = try c.decodeIfPresent(Int.self, forKey: .typed) ?? 0
    }

    var activity: Int { tools + errors + sessions }
    /// Fallos sobre intentos (herramientas y fallos).
    var errorRate: Double { tools + errors == 0 ? 0 : Double(errors) / Double(tools + errors) }
}

struct Chronotype: Codable, Equatable {
    static let maxDays = 60
    static let minEvents = 40
    static let minDays = 2
    static let blockHours = 3
    static let minTyped = 500

    var hours = [HourBucket](repeating: HourBucket(), count: 24)
    /// Dias distintos con actividad (aaaa-mm-dd), los mas recientes.
    var days: [String] = []

    private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func add(_ kind: PetMemoryEvent.Kind, at date: Date, calendar: Calendar = .current) {
        let h = min(23, max(0, calendar.component(.hour, from: date)))
        switch kind {
        case .tool: hours[h].tools += 1
        case .error: hours[h].errors += 1
        case .session: hours[h].sessions += 1
        case .permission: hours[h].permissions += 1
        }
        let key = Self.dayKey(date, calendar)
        if !days.contains(key) { days.append(key); days.sort(); if days.count > Self.maxDays { days.removeFirst(days.count - Self.maxDays) } }
    }

    mutating func addTyped(_ n: Int, at date: Date, calendar: Calendar = .current) {
        guard n > 0 else { return }
        hours[min(23, max(0, calendar.component(.hour, from: date)))].typed += n
    }

    var totalTyped: Int { hours.reduce(0) { $0 + $1.typed } }

    var totalEvents: Int { hours.reduce(0) { $0 + $1.activity } }
    var overallErrorRate: Double {
        let tools = hours.reduce(0) { $0 + $1.tools }, errors = hours.reduce(0) { $0 + $1.errors }
        return tools + errors == 0 ? 0 : Double(errors) / Double(tools + errors)
    }

    struct Block: Equatable {
        let start: Int          // hora de inicio, 0...21
        let end: Int            // hora de fin, 3...24
        let bucket: HourBucket
        var label: String { "\(start)–\(end) h" }
    }

    /// Las horas agrupadas en franjas de tres: una hora suelta tiene demasiado ruido para hablar de ella.
    var blocks: [Block] {
        stride(from: 0, to: 24, by: Self.blockHours).map { start in
            var b = HourBucket()
            for h in start..<(start + Self.blockHours) {
                b.tools += hours[h].tools; b.errors += hours[h].errors; b.sessions += hours[h].sessions; b.permissions += hours[h].permissions; b.typed += hours[h].typed
            }
            return Block(start: start, end: start + Self.blockHours, bucket: b)
        }
    }

    struct Insight: Equatable {
        var peak: Block?
        var best: Block?
        var typingPeak: Block?
        var hard: Block?
        var hardRatio = 0.0
        var lines: [String] = []
    }

    /// nil mientras haya pocos datos: con 12 eventos cualquier "patron" es casualidad.
    func insight() -> Insight? {
        guard totalEvents >= Self.minEvents, days.count >= Self.minDays else { return nil }
        let all = blocks
        var out = Insight()
        out.peak = all.max { $0.bucket.activity < $1.bucket.activity }
        let overall = overallErrorRate
        let solid = all.filter { $0.bucket.tools + $0.bucket.errors >= 12 }
        if overall > 0 {
            if let hard = solid.max(by: { $0.bucket.errorRate < $1.bucket.errorRate }),
               hard.bucket.errorRate >= overall * 1.5, hard.bucket.errorRate >= overall + 0.05 {
                out.hard = hard; out.hardRatio = hard.bucket.errorRate / overall
            }
            if let best = solid.min(by: { $0.bucket.errorRate < $1.bucket.errorRate }),
               best.bucket.errorRate <= overall * 0.6, best != out.hard {
                out.best = best
            }
        }
        if let peak = out.peak, peak.bucket.activity > 0 { out.lines.append("trabajas más entre las \(peak.label)") }
        if totalTyped >= Self.minTyped, let tp = all.max(by: { $0.bucket.typed < $1.bucket.typed }), tp.bucket.typed > 0 {
            out.typingPeak = tp
            out.lines.append("tecleas más entre las \(tp.label)")
        }
        if let hard = out.hard {
            out.lines.append("en \(hard.label) fallas \(Self.ratio(out.hardRatio))× más que de media: déjalo para otro rato")
        }
        if let best = out.best {
            out.lines.append("tu mejor franja es \(best.label), con solo \(Int((best.bucket.errorRate * 100).rounded())) % de fallos")
        }
        if out.hard == nil { out.lines.append("sin una franja claramente peor: tu ritmo es parejo") }
        return out
    }

    private static func ratio(_ r: Double) -> String { String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",") }
}
