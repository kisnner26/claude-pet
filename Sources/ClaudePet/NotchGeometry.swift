import CoreGraphics

/// Medidas de una pantalla, en coordenadas de AppKit (origen abajo a la izquierda).
struct ScreenMetrics: Equatable {
    var frame: CGRect
    /// `safeAreaInsets.top`: mayor que cero solo en pantallas con notch.
    var safeTop: CGFloat
    /// Anchos de las zonas a cada lado del notch (`auxiliaryTopLeftArea` y `auxiliaryTopRightArea`).
    var auxLeft: CGFloat
    var auxRight: CGFloat
    /// Altura real de la barra de menús en puntos; se inyecta en pruebas.
    var menuBarHeight: CGFloat = 24
    var centerLeftInset: CGFloat = 180
    var centerRightInset: CGFloat = 180
}

enum IslandScreenPreference: String, CaseIterable { case notch = "pantalla del notch"; case mouse = "seguir al ratón" }

/// Geometria de la isla: tamano por modo y posicion pegada al borde superior.
/// Los valores salen de las reglas de la isla (doc/ISLAND.md); las medidas del notch son las reales de la pantalla.
enum NotchGeometry {
    /// Ventana fija que contiene la isla; el resto es transparente y deja pasar los clics.
    static let panelSize = CGSize(width: 720, height: 320)
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 196
    static let hitMargin: CGFloat = 6
    /// Pantalla sin notch: barra de este ancho y alto en reposo.
    static let barWidth: CGFloat = 80

    static func hasNotch(_ m: ScreenMetrics) -> Bool { m.safeTop > 0 && m.frame.width - m.auxLeft - m.auxRight > 0 }

    /// Tamano del notch real, o de la barra cuando no hay notch.
    static func notchSize(_ m: ScreenMetrics) -> CGSize {
        hasNotch(m) ? CGSize(width: m.frame.width - m.auxLeft - m.auxRight, height: m.safeTop) : CGSize(width: barWidth, height: m.menuBarHeight)
    }

    static func islandSize(_ mode: IslandMode, metrics m: ScreenMetrics, expandedHeight: CGFloat = expandedHeight, compactContentWidth: CGFloat? = nil) -> CGSize {
        let n = notchSize(m)
        switch mode {
        case .hidden: return n
        case .peek: return CGSize(width: n.width + 64, height: n.height)
        case .compact:
            let base = hasNotch(m) ? n.width + 104 : (compactContentWidth ?? 240)
            let maxWidth = max(120, m.frame.width - m.centerLeftInset - m.centerRightInset)
            return CGSize(width: min(max(120, base), maxWidth), height: n.height)
        case .expanded: return CGSize(width: expandedWidth, height: max(expandedHeight, n.height))
        }
    }

    /// Radio de las esquinas de abajo (las de arriba son cuadradas para fundirse con el borde).
    static func cornerRadius(_ mode: IslandMode) -> CGFloat { mode == .expanded ? 30 : 14 }

    /// Rectangulo de la ventana: centrada arriba en la pantalla.
    static func panelFrame(_ m: ScreenMetrics) -> CGRect {
        CGRect(x: m.frame.midX - panelSize.width / 2, y: m.frame.maxY - panelSize.height,
               width: panelSize.width, height: panelSize.height)
    }

    /// Rectangulo de la isla en coordenadas de pantalla (para probar si el cursor esta encima).
    static func islandFrame(_ mode: IslandMode, metrics m: ScreenMetrics, expandedHeight: CGFloat = expandedHeight) -> CGRect {
        let s = islandSize(mode, metrics: m, expandedHeight: expandedHeight)
        return CGRect(x: m.frame.midX - s.width / 2, y: m.frame.maxY - s.height, width: s.width, height: s.height)
    }

    static let permissionHeight: CGFloat = 224

    static func contains(_ p: CGPoint, mode: IslandMode, metrics m: ScreenMetrics, expandedHeight: CGFloat = expandedHeight) -> Bool {
        islandFrame(mode, metrics: m, expandedHeight: expandedHeight).insetBy(dx: -hitMargin, dy: -hitMargin).contains(p)
    }

    /// El cursor esta sobre el notch (o la barra), con margen. Es lo que hace asomar a la mascota.
    static func overNotch(_ p: CGPoint, metrics m: ScreenMetrics) -> Bool {
        islandFrame(.hidden, metrics: m).insetBy(dx: -hitMargin, dy: -hitMargin).contains(p)
    }

    /// Eleccion de pantalla: la que tiene notch; si no, la primera (la de la barra de menus).
    static func pick(_ screens: [ScreenMetrics], preference: IslandScreenPreference = .notch, mouse: CGPoint? = nil) -> ScreenMetrics? {
        if preference == .mouse, let mouse, let screen = screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return screens.first(where: hasNotch) ?? screens.first
    }
}
