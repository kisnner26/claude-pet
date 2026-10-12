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

struct SessionTrailView: View {
    let events: [MissionEvent]
    let reduceMotion: Bool

    private let claude = Color(hex: 0xE0824F)
    private let codex = Color(hex: 0x96EBFF)
    private let glow = Color(hex: 0x7DB4FF)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let segs = SessionTrail.segments(events: events, now: now)
            let span = SessionTrail.window(events: events, now: now)
            VStack(alignment: .leading, spacing: 6) {
                Canvas { gc, size in draw(&gc, size: size, segs: segs, now: now, span: span, t: ctx.date.timeIntervalSinceReferenceDate) }
                    .frame(height: 64)
                HStack {
                    Text("hace \(max(1, Int(span / 60))) min")
                    Spacer()
                    Text("ahora")
                }
                .font(.caption2).foregroundStyle(Pal.cream.opacity(0.5))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(SessionTrail.summary(segs)))
        }
    }

    private func accessibilitySummary(_ s: TrailSummary) -> String {
        func min(_ t: TimeInterval) -> String { "\(Int((t / 60).rounded())) min" }
        return "estela de sesión: claude trabajó \(min(s.claude)), codex \(min(s.codex)), a la vez \(min(s.together))"
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, segs: [TrailSegment], now: Date, span: TimeInterval, t: Double) {
        let start = now.addingTimeInterval(-span)
        func x(_ d: Date) -> CGFloat { CGFloat(max(0, min(1, d.timeIntervalSince(start) / span))) * size.width }
        let lanes: [(String, CGFloat, Color)] = [("claude", size.height * 0.27, claude), ("codex", size.height * 0.73, codex)]

        // carriles base
        for (_, y, _) in lanes {
            gc.fill(Path(roundedRect: CGRect(x: 0, y: y - 0.5, width: size.width, height: 1), cornerRadius: 0.5), with: .color(.white.opacity(0.08)))
        }
        // coincidencias: banda de luz que une los dos carriles
        for range in SessionTrail.overlaps(segs) {
            let x0 = x(range.lowerBound), x1 = max(x(range.upperBound), x0 + 3)
            let rect = CGRect(x: x0, y: lanes[0].1 - 2, width: x1 - x0, height: lanes[1].1 - lanes[0].1 + 4)
            gc.drawLayer { layer in
                layer.addFilter(.blur(radius: 9))
                layer.fill(Path(roundedRect: rect.insetBy(dx: 3, dy: 5), cornerRadius: 8), with: .color(glow.opacity(0.4)))
            }
            gc.fill(Path(roundedRect: CGRect(x: x0, y: lanes[0].1, width: 1.5, height: lanes[1].1 - lanes[0].1), cornerRadius: 0.75), with: .color(glow.opacity(0.55)))
            gc.fill(Path(roundedRect: CGRect(x: x1 - 1.5, y: lanes[0].1, width: 1.5, height: lanes[1].1 - lanes[0].1), cornerRadius: 0.75), with: .color(glow.opacity(0.55)))
        }
        // trazos: se desvanecen hacia el pasado
        for seg in segs {
            guard let lane = lanes.first(where: { $0.0 == seg.agent }) else { continue }
            let x0 = x(seg.start), x1 = max(x(seg.end), x0 + 2)
            let thickness: CGFloat
            switch seg.state {
            case .tool: thickness = 8
            case .waiting: thickness = 6
            case .error: thickness = 6
            case .thinking: thickness = 4
            default: thickness = 3
            }
            let tint = seg.state == .error ? Color(hex: 0xFF8A7A) : lane.2
            var pulse = 1.0
            if seg.state == .waiting && !reduceMotion && seg.end >= now.addingTimeInterval(-1) { pulse = 0.65 + 0.35 * sin(t * 6) }
            let rect = CGRect(x: x0, y: lane.1 - thickness / 2, width: x1 - x0, height: thickness)
            // el brillo depende de la posición absoluta: lo antiguo se apaga de forma continua entre tramos
            func age(_ px: CGFloat) -> Double { 0.18 + 0.82 * Double(px / size.width) }
            let fade = Gradient(colors: [tint.opacity(age(x0) * pulse), tint.opacity(age(x1) * pulse)])
            gc.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                    with: .linearGradient(fade, startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
            // cabeza viva
            if seg.end >= now.addingTimeInterval(-1) && SessionTrail.isWorking(seg.state) {
                let head = CGRect(x: x1 - thickness, y: lane.1 - thickness, width: thickness * 2, height: thickness * 2)
                gc.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5))
                    layer.fill(Path(ellipseIn: head), with: .color(tint.opacity(0.9)))
                }
            }
        }
        // cierres: una marca donde un agente terminó
        for event in events where event.state == .done {
            guard let lane = lanes.first(where: { $0.0 == event.agent }), event.at >= start else { continue }
            gc.fill(Path(ellipseIn: CGRect(x: x(event.at) - 3, y: lane.1 - 3, width: 6, height: 6)), with: .color(Pal.cream.opacity(0.9)))
        }
    }
}
