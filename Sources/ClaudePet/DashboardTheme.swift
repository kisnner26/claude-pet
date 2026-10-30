import SwiftUI

/// Tokens del lenguaje visual técnico. Un único acento mantiene coherencia entre isla, memoria y ajustes.
enum DashboardTheme {
    static let black = Color(hex: 0x0A0A0A)
    static let surface = Color(hex: 0x11110F)
    static let surfaceRaised = Color(hex: 0x171510)
    static let ink = Color(hex: 0xF5F1EA)
    static let muted = Color(hex: 0xA7A198)
    static let line = Color(hex: 0xFFB380).opacity(0.18)
    static let amber = Color(hex: 0xFF6B1A)
    static let ember = Color(hex: 0xFFB380)
    static let signal = Color(hex: 0xDCEB58)
    static let cream = Color(hex: 0xF5F1EA)
    static let accent = LinearGradient(colors: [amber, ember], startPoint: .leading, endPoint: .trailing)
}

struct DashboardBackground: View {
    var body: some View {
        ZStack {
            DashboardTheme.black
            LinearGradient(colors: [DashboardTheme.amber.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for index in stride(from: 0, through: Int(size.height), by: 4) {
                    let y = CGFloat(index)
                    context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0.4)), with: .color(.white.opacity(0.018)), lineWidth: 0.4)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func dashboardTile(padding: CGFloat = 10, active: Bool = false) -> some View {
        self
            .padding(padding)
            .background(DashboardTheme.surfaceRaised.opacity(active ? 0.96 : 0.82))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DashboardTheme.line.opacity(active ? 1 : 0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func dashboardLabel() -> some View {
        self.font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1).textCase(.uppercase).foregroundStyle(DashboardTheme.muted)
    }
}
