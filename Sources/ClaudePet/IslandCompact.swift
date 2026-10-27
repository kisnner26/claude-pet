import SwiftUI

/// Cuanta informacion muestra la isla compacta. Sin notch no hay nada que tape el espacio, asi que se puede elegir.
enum IslandCompactMode: String, CaseIterable {
    case minimal = "mínimo", normal = "normal", full = "completo"

    struct Items: Equatable {
        var state = true
        var context = false
        var badge = false
        var duration = false
        var branch = false
    }

    var items: Items {
        switch self {
        case .minimal: return Items()
        case .normal: return Items(context: true, badge: true)
        case .full: return Items(context: true, badge: true, duration: true, branch: true)
        }
    }

    /// Ancho del contenido en puntos; la geometria lo acota luego al espacio libre de la barra.
    func contentWidth(clock: Bool) -> CGFloat {
        let base: CGFloat
        switch self { case .minimal: base = 120; case .normal: base = 200; case .full: base = 300 }
        return base + (clock ? 52 : 0)
    }
}

/// Reloj de la isla compacta, con el formato de 12 o 24 horas del sistema.
struct IslandClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(context.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
        }
        .accessibilityLabel("hora")
    }
}
