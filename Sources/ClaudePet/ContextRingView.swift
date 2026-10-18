import SwiftUI

struct ContextRingView: View {
    let reading: ContextReading

    private var tint: Color {
        switch reading.pressure {
        case .normal: Color(hex: 0x7DB4FF)
        case .caution: Color(hex: 0xE6B85C)
        case .critical: Color(hex: 0xFF6B63)
        }
    }

    private var stroke: StrokeStyle {
        switch reading.pressure {
        case .normal: StrokeStyle(lineWidth: 3, lineCap: .round)
        case .caution: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [8, 3])
        case .critical: StrokeStyle(lineWidth: 4, lineCap: .square, dash: [4, 3])
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: reading.remainingFraction)
                .stroke(tint, style: stroke)
                .rotationEffect(.degrees(-90))
            Text("\(reading.remainingPercent)%")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(tint)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Pal.charcoal.opacity(0.9), in: Capsule())
                .offset(y: -54)
        }
        .frame(width: 108, height: 108)
        .accessibilityHidden(true)
    }
}
