import SwiftUI

/// Tu ritmo: las 24 horas del dia con la actividad como altura y los fallos como color, y lo que se saca de ahi.
struct RhythmPanel: View {
    let chrono: Chronotype
    var reduceMotion = false

    private static let calm = Color(hex: 0x6CCB8A), normal = Color(hex: 0xF4EDE1), hot = Color(hex: 0xD85C5C)

    /// Color por hora: verde si falla mucho menos que de media, rojo si mucho mas, crema entre medias.
    static func tint(for bucket: HourBucket, overall: Double) -> Color {
        guard bucket.tools + bucket.errors >= 4, overall > 0 else { return normal.opacity(bucket.activity == 0 ? 0.12 : 0.55) }
        if bucket.errorRate >= max(overall * 1.5, overall + 0.05) { return hot }
        if bucket.errorRate <= overall * 0.6 { return calm }
        return normal.opacity(0.75)
    }

    var body: some View {
        let insight = chrono.insight()
        let overall = chrono.overallErrorRate
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVIDAD POR HORA").dashboardLabel()
                chart(insight: insight, overall: overall).frame(height: 100)
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(h == 0 ? "0 h" : "\(h)").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
                        Spacer(minLength: 0)
                    }
                    Text("24").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
                }
                legend
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text("LO QUE SE VE").dashboardLabel()
                if let insight {
                    ForEach(insight.lines.prefix(3), id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(DashboardTheme.ember).frame(width: 5, height: 5).padding(.top, 5)
                            Text(line).font(.system(size: 11.5)).foregroundStyle(DashboardTheme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("todavía hay poco que contar").font(.system(size: 12, weight: .semibold)).foregroundStyle(DashboardTheme.ink)
                    Text("hacen falta unos \(Chronotype.minEvents) eventos en \(Chronotype.minDays) días; llevas \(chrono.totalEvents) en \(chrono.days.count) \(chrono.days.count == 1 ? "día" : "días").")
                        .font(.system(size: 10.5)).foregroundStyle(DashboardTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("\(chrono.days.count) \(chrono.days.count == 1 ? "día observado" : "días observados") · \(chrono.totalEvents) eventos")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
            }
            .frame(width: 214, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("tu ritmo: " + (insight?.lines.joined(separator: ". ") ?? "todavía hay poco que contar"))
    }

    private func chart(insight: Chronotype.Insight?, overall: Double) -> some View {
        Canvas { gc, size in
            let peak = max(1, chrono.hours.map(\.activity).max() ?? 1)
            let w = size.width / 24
            // la franja en la que mas fallas, resaltada de fondo
            if let hard = insight?.hard {
                gc.fill(Path(roundedRect: CGRect(x: CGFloat(hard.start) * w, y: 0, width: CGFloat(hard.end - hard.start) * w, height: size.height), cornerRadius: 4), with: .color(Self.hot.opacity(0.14)))
            }
            for h in 0..<24 {
                let b = chrono.hours[h]
                let bar = max(2, size.height * CGFloat(b.activity) / CGFloat(peak))
                gc.fill(Path(roundedRect: CGRect(x: CGFloat(h) * w + 1.2, y: size.height - bar, width: w - 2.4, height: bar), cornerRadius: 2), with: .color(Self.tint(for: b, overall: overall)))
            }
            if let p = insight?.peak, p.bucket.activity > 0 {
                gc.fill(Path(CGRect(x: CGFloat(p.start) * w + 2, y: size.height - 1.5, width: CGFloat(p.end - p.start) * w - 4, height: 1.5)), with: .color(DashboardTheme.ember))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([("falla poco", Self.calm), ("normal", Self.normal.opacity(0.75)), ("falla mucho", Self.hot)], id: \.0) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.1).frame(width: 6, height: 6)
                    Text(item.0).font(.system(size: 9)).foregroundStyle(DashboardTheme.muted)
                }
            }
        }
    }
}
