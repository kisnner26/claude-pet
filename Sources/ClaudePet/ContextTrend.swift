import Foundation
import SwiftUI

struct ContextSample: Equatable {
    let percent: Int
    let pressure: ContextPressure
    let at: Date
}

enum ContextTrend {
    static let limit = 24

    static func append(_ reading: ContextReading, to samples: [ContextSample], at date: Date) -> [ContextSample] {
        let sample = ContextSample(percent: reading.remainingPercent, pressure: reading.pressure, at: date)
        if let last = samples.last, last.percent == sample.percent && last.pressure == sample.pressure { return samples }
        return Array((samples + [sample]).suffix(limit))
    }

    static func delta(_ samples: [ContextSample]) -> Int? {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return nil }
        return last.percent - first.percent
    }

    static func label(_ samples: [ContextSample]) -> String {
        guard let delta = delta(samples) else { return "sin tendencia" }
        if delta == 0 { return "estable" }
        return delta > 0 ? "+\(delta) puntos" : "\(delta) puntos"
    }

    static func warning(_ samples: [ContextSample]) -> String? {
        guard let delta = delta(samples), delta <= -10 else { return nil }
        return "descenso rápido"
    }

    static func copyText(_ samples: [ContextSample], agent: String) -> String {
        guard let last = samples.last else { return "\(agent) · sin lecturas" }
        let warning = warning(samples).map { " · \($0)" } ?? ""
        return "\(agent) · \(last.percent)% restante · \(label(samples))\(warning) · \(samples.count) lecturas"
    }
}

struct ContextTrendView: View {
    let samples: [ContextSample]
    var agent: String = "contexto"

    private func color(_ pressure: ContextPressure) -> Color {
        switch pressure {
        case .normal: return Color(hex: 0x5270E8)
        case .caution: return Color(hex: 0xE7B45B)
        case .critical: return Color(hex: 0xD85C5C)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("tendencia de contexto").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(ContextTrend.label(samples)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                if let warning = ContextTrend.warning(samples) {
                    Text(warning).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xD85C5C))
                }
            }
            GeometryReader { proxy in
                Path { path in
                    guard samples.count > 1 else { return }
                    let step = proxy.size.width / CGFloat(samples.count - 1)
                    for (index, sample) in samples.enumerated() {
                        let point = CGPoint(x: CGFloat(index) * step,
                                            y: proxy.size.height * (1 - CGFloat(sample.percent) / 100))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(samples.last.map { color($0.pressure) } ?? Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = samples.last {
                    Circle().fill(color(last.pressure)).frame(width: 5, height: 5)
                        .position(x: proxy.size.width, y: proxy.size.height * (1 - CGFloat(last.percent) / 100))
                }
            }
            .frame(height: 18)
            Button("copiar tendencia", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ContextTrend.copyText(samples, agent: agent), forType: .string)
            }
            .buttonStyle(.plain)
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.white.opacity(0.45))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("tendencia de contexto: \(ContextTrend.label(samples))")
        .help("tendencia de las últimas lecturas; no se guarda el transcript")
    }
}
