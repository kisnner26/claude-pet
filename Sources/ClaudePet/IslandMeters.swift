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
