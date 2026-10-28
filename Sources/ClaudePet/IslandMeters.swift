import SwiftUI
import AppKit

enum IslandMeterStyle {
    static func color(_ pressure: ContextPressure) -> Color {
        switch pressure {
        case .normal: return Color(hex: 0x5270E8)
        case .caution: return Color(hex: 0xE7B45B)
        case .critical: return Color(hex: 0xD85C5C)
        }
    }
}

struct IslandContextMeter: View {
    let reading: ContextReading
    let label: String
    let onOpen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(reading.remainingPercent)%").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(IslandMeterStyle.color(reading.pressure))
            GeometryReader { proxy in
                Capsule().fill(IslandMeterStyle.color(reading.pressure)).frame(width: max(2, proxy.size.width * CGFloat(reading.remainingPercent) / 100), height: 2)
            }.frame(width: 24, height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(reading.remainingPercent) por ciento restante, estado \(reading.pressureLabel)")
        .help("\(label): \(reading.remainingPercent)% restante · estado \(reading.pressureLabel) · azul normal · ámbar cuidado · rojo crítico")
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu { Button("copiar \(label)", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reading.summary, forType: .string) } }
    }
}

/// Dos barras finas: lo que queda del limite de 5 horas y del semanal, con cuanto falta para que se reinicien.
struct PlanUsageRow: View {
    let usage: PlanUsage
    private func color(_ used: Double) -> Color { used >= 95 ? Color(hex: 0xD85C5C) : used >= 80 ? Color(hex: 0xE7B45B) : Color(hex: 0x5270E8) }

    private func bar(_ title: String, _ w: PlanWindow, now: Date) -> some View {
        let used = w.effectivePercent(now: now), left = w.remainingPercent(now: now)
        return HStack(spacing: 6) {
            Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 18, alignment: .leading)
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color(used)).frame(width: max(3, p.size.width * CGFloat(left) / 100))
                }
            }.frame(height: 3)
            Text("\(left)%").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(color(used)).frame(width: 30, alignment: .trailing)
            if let r = w.resetText(now: now) { Text(r).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4)).frame(width: 44, alignment: .leading) }
        }
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 3) {
            if let f = usage.five { bar("5h", f, now: now) }
            if let w = usage.week { bar("7d", w, now: now) }
            if usage.isStale(now: now) { Text("sin datos recientes: se actualiza cuando claude trabaja").font(.system(size: 9)).foregroundColor(.white.opacity(0.35)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("plan: " + [usage.five.map { "5 horas, queda el \($0.remainingPercent(now: now)) por ciento" }, usage.week.map { "semanal, queda el \($0.remainingPercent(now: now)) por ciento" }].compactMap { $0 }.joined(separator: "; "))
    }
}
