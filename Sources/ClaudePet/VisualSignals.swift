import SwiftUI

struct ContextCocoonView: View {
    let pressure: ContextPressure

    var body: some View {
        Canvas { context, _ in
            let tint = pressure == .critical ? Color(hex: 0xFF7B70) : Color(hex: 0xE7B45B)
            for index in 0..<5 {
                let inset = CGFloat(14 + index * 5)
                let thread = Path(ellipseIn: CGRect(x: inset, y: 16 + CGFloat(index % 2) * 4,
                                                     width: 128 - inset * 2, height: 96 - CGFloat(index % 2) * 8))
                context.stroke(thread, with: .color(tint.opacity(0.2 + Double(index) * 0.09)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }
}

struct AppRadarView: View {
    let label: String

    var body: some View {
        Canvas { context, _ in
            var antenna = Path()
            antenna.move(to: CGPoint(x: 74, y: 50))
            antenna.addLine(to: CGPoint(x: 105, y: 25))
            context.stroke(antenna, with: .color(Color(hex: 0x7DB4FF).opacity(0.8)), lineWidth: 1.5)
            context.fill(Path(ellipseIn: CGRect(x: 101, y: 21, width: 8, height: 8)), with: .color(Color(hex: 0x7DB4FF)))
        }
        .overlay(alignment: .topTrailing) {
            Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Pal.cream).lineLimit(1).padding(.horizontal, 4).padding(.vertical, 2)
                .background(Pal.charcoal.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 5)
        }
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }
}
