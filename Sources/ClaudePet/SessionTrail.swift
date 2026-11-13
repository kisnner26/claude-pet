import SwiftUI

struct TrailSegment: Equatable {
    let agent: String
    let state: PetState
    let start: Date
    let end: Date
}

struct TrailSummary: Equatable {
    var claude: TimeInterval = 0
    var codex: TimeInterval = 0
    var together: TimeInterval = 0
}

/// Convierte la traza de eventos en tramos por agente. Solo usa estados y horas que ya se registran.
enum SessionTrail {
    static func isWorking(_ state: PetState) -> Bool { state == .starting || state == .thinking || state == .tool }

    /// `events` llega con el más reciente primero. Cada evento dura hasta el siguiente del mismo agente (o hasta `now`).
    static func segments(events: [MissionEvent], now: Date) -> [TrailSegment] {
        var result: [TrailSegment] = []
        for agent in ["claude", "codex"] {
            let own = events.filter { $0.agent == agent }.sorted { $0.at < $1.at }
            for (index, event) in own.enumerated() {
                let end = index + 1 < own.count ? own[index + 1].at : now
                guard end > event.at else { continue }
                if isWorking(event.state) || event.state == .waiting || event.state == .error {
                    result.append(TrailSegment(agent: agent, state: event.state, start: event.at, end: end))
                }
            }
        }
        return result
    }

    /// Intervalos en los que los dos agentes trabajaban a la vez.
    static func overlaps(_ segments: [TrailSegment]) -> [ClosedRange<Date>] {
        let claude = segments.filter { $0.agent == "claude" && isWorking($0.state) }
        let codex = segments.filter { $0.agent == "codex" && isWorking($0.state) }
        var out: [ClosedRange<Date>] = []
        for a in claude {
            for b in codex {
                let lo = max(a.start, b.start), hi = min(a.end, b.end)
                if hi > lo { out.append(lo...hi) }
            }
        }
        var merged: [ClosedRange<Date>] = []
        for range in out.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func summary(_ segments: [TrailSegment]) -> TrailSummary {
        var s = TrailSummary()
        for seg in segments where isWorking(seg.state) {
            let d = seg.end.timeIntervalSince(seg.start)
            if seg.agent == "claude" { s.claude += d } else { s.codex += d }
        }
        s.together = overlaps(segments).reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
        return s
    }

    /// Ventana visible: desde el primer evento (mínimo 5 min, máximo 60) hasta ahora.
    static func window(events: [MissionEvent], now: Date) -> TimeInterval {
        let first = events.map(\.at).min() ?? now
        return min(3600, max(300, now.timeIntervalSince(first) + 20))
    }
}

/// Una celda de la estela: lo mas fuerte que paso en ese tramo de tiempo. El orden es la prioridad al dibujar.
enum TrailCell: Int, Comparable {
    case empty, thinking, tool, waiting, error
    static func < (a: TrailCell, b: TrailCell) -> Bool { a.rawValue < b.rawValue }

    /// Cuantas celdas de alto ocupa en la columna (como un ecualizador pixel-art).
    var height: Int { switch self { case .empty: return 0; case .thinking: return 1; default: return 2 } }
    var isWorking: Bool { self == .thinking || self == .tool }
}

extension SessionTrail {
    /// Reparte los tramos de un agente en `count` columnas iguales de la ventana. Una columna se llena si el tramo la cubre
    /// al menos un quinto: asi un destello de un segundo no ensucia la linea y uno real nunca se pierde.
    static func cells(_ segments: [TrailSegment], agent: String, now: Date, span: TimeInterval, count: Int) -> [TrailCell] {
        guard count > 0, span > 0 else { return [] }
        let start = now.addingTimeInterval(-span), width = span / Double(count)
        var out = [TrailCell](repeating: .empty, count: count)
        for seg in segments where seg.agent == agent {
            let kind: TrailCell
            switch seg.state { case .tool: kind = .tool; case .waiting: kind = .waiting; case .error: kind = .error; default: kind = .thinking }
            let lo = max(0, Int((seg.start.timeIntervalSince(start) / width).rounded(.down)))
            let hi = min(count - 1, Int((seg.end.timeIntervalSince(start) / width).rounded(.down)))
            guard lo <= hi else { continue }
            for i in lo...hi {
                let a = start.addingTimeInterval(Double(i) * width), b = a.addingTimeInterval(width)
                let overlap = min(b, seg.end).timeIntervalSince(max(a, seg.start))
                if overlap >= width * 0.2, kind > out[i] { out[i] = kind }
            }
        }
        return out
    }

    /// Columnas en las que los dos agentes trabajaban a la vez.
    static func togetherColumns(_ claude: [TrailCell], _ codex: [TrailCell]) -> [Int] {
        (0..<min(claude.count, codex.count)).filter { claude[$0].isWorking && codex[$0].isWorking }
    }

    /// Opacidad por tramos de la ventana: lo antiguo se apaga en escalones, no en degradado.
    static func ageAlpha(column: Int, count: Int) -> Double {
        let k = count <= 1 ? 1 : Double(column) / Double(count - 1)
        return k < 0.25 ? 0.38 : k < 0.5 ? 0.56 : k < 0.75 ? 0.78 : 1
    }
}

/// La estela de la sesion en pixel-art: dos carriles (claude arriba, codex abajo), una columna por tramo de tiempo, de la
/// altura de lo que hizo el agente. Nitida, sin desenfoque y en los colores de cada agente.
struct SessionTrailView: View {
    let events: [MissionEvent]
    let reduceMotion: Bool

    static let claude = Color(hex: 0xE0824F)
    static let codex = Color(hex: 0x5270E8)
    static let alert = Color(hex: 0xD85C5C)
    static let amber = Color(hex: 0xE7B45B)
    /// Celda y separacion, en puntos: la rejilla del resto de la interfaz.
    static let cell: CGFloat = 4
    static let gap: CGFloat = 1

    @ViewBuilder var body: some View {
        if events.isEmpty {
            Color.clear.frame(height: 64)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let segs = SessionTrail.segments(events: events, now: now)
            let span = SessionTrail.window(events: events, now: now)
            VStack(alignment: .leading, spacing: 6) {
                Canvas { gc, size in Self.draw(&gc, size: size, segs: segs, events: events, now: now, span: span) }
                    .frame(height: 64)
                HStack {
                    Text("hace \(max(1, Int(span / 60))) min")
                    Spacer()
                    Text("ahora")
                }
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Pal.cream.opacity(0.5))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(SessionTrail.summary(segs)))
            }
        }
    }

    private func accessibilitySummary(_ s: TrailSummary) -> String {
        func min(_ t: TimeInterval) -> String { "\(Int((t / 60).rounded())) min" }
        return "estela de sesión: claude trabajó \(min(s.claude)), codex \(min(s.codex)), a la vez \(min(s.together))"
    }

    static func draw(_ gc: inout GraphicsContext, size: CGSize, segs: [TrailSegment], events: [MissionEvent], now: Date, span: TimeInterval) {
        let pitch = cell + gap
        let count = max(1, Int(size.width / pitch))
        let left = (size.width - CGFloat(count) * pitch + gap) / 2
        let lanes: [(agent: String, base: CGFloat, color: Color)] = [("claude", 26, claude), ("codex", 58, codex)]
        func rect(_ column: Int, row: Int, base: CGFloat) -> CGRect {
            CGRect(x: left + CGFloat(column) * pitch, y: base - CGFloat(row + 1) * pitch + gap, width: cell, height: cell)
        }
        let columns = lanes.map { SessionTrail.cells(segs, agent: $0.agent, now: now, span: span, count: count) }

        // linea fina de cada carril
        for lane in lanes {
            gc.fill(Path(CGRect(x: left, y: lane.base + 1, width: CGFloat(count) * pitch - gap, height: 1)), with: .color(.white.opacity(0.1)))
        }
        // coincidencias: un corchete fino al principio y al final de cada tramo en que trabajan a la vez
        let together = Set(SessionTrail.togetherColumns(columns[0], columns[1]))
        for c in together.sorted() where !together.contains(c - 1) || !together.contains(c + 1) {
            let x = left + CGFloat(c) * pitch + cell / 2 - 0.5
            gc.fill(Path(CGRect(x: x, y: lanes[0].base + 5, width: 1, height: lanes[1].base - 2 * pitch - lanes[0].base - 4)), with: .color(Pal.cream.opacity(0.4)))
        }
        // columnas
        for (index, lane) in lanes.enumerated() {
            for (c, kind) in columns[index].enumerated() where kind != .empty {
                let alpha = SessionTrail.ageAlpha(column: c, count: count)
                let tint = kind == .error ? alert : kind == .waiting ? amber : lane.color
                for row in 0..<kind.height {
                    let r = rect(c, row: row, base: lane.base)
                    if kind == .waiting && row == 0 {
                        // esperando tu respuesta: celda hueca
                        gc.stroke(Path(r.insetBy(dx: 0.5, dy: 0.5)), with: .color(tint.opacity(alpha)), lineWidth: 1)
                    } else if kind == .thinking {
                        gc.fill(Path(r), with: .color(tint.opacity(alpha * 0.6)))
                    } else {
                        gc.fill(Path(r), with: .color(tint.opacity(alpha)))
                    }
                }
            }
        }
        // cierres: una celda crema bajo el carril donde un agente termino
        let start = now.addingTimeInterval(-span)
        for event in events where event.state == .done && event.at >= start {
            guard let lane = lanes.first(where: { $0.agent == event.agent }) else { continue }
            let c = min(count - 1, max(0, Int(event.at.timeIntervalSince(start) / span * Double(count))))
            gc.fill(Path(CGRect(x: left + CGFloat(c) * pitch, y: lane.base + 4, width: cell, height: cell)), with: .color(Pal.cream.opacity(0.9)))
        }
    }
}
