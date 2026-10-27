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
    /// Area libre de barra y dock (`NSScreen.visibleFrame`); nil usa el marco completo.
    var visibleFrame: CGRect?
    /// La barra de menus esta oculta (autoocultar o app a pantalla completa).
    var menuBarHidden = false
    /// Desplazamiento horizontal de la isla flotante, en puntos desde el centro.
    var floatingOffsetX: CGFloat = 0
}

/// Donde se ancla la isla en la pantalla.
enum IslandPlacement: String, CaseIterable {
    case top = "arriba", bottom = "abajo", side = "lateral", floating = "flotante"
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

    /// Separacion de la isla flotante respecto al borde, en puntos.
    static let floatingGap: CGFloat = 8
    /// Alto de la franja de activacion cuando la barra de menus esta oculta.
    static let edgeStripHeight: CGFloat = 4

    /// Tamano del notch real, o de la barra cuando no hay notch (o la isla no va arriba).
    static func notchSize(_ m: ScreenMetrics, placement: IslandPlacement = .top) -> CGSize {
        placement == .top && hasNotch(m)
            ? CGSize(width: m.frame.width - m.auxLeft - m.auxRight, height: m.safeTop)
            : CGSize(width: barWidth, height: m.menuBarHeight)
    }

    static func islandSize(_ mode: IslandMode, metrics m: ScreenMetrics, placement: IslandPlacement = .top, expandedHeight: CGFloat = expandedHeight, compactContentWidth: CGFloat? = nil) -> CGSize {
        let n = notchSize(m, placement: placement)
        let notched = placement == .top && hasNotch(m)
        switch mode {
        case .hidden: return n
        case .peek: return CGSize(width: n.width + 64, height: n.height)
        case .compact:
            let base = notched ? n.width + 104 : (compactContentWidth ?? 240)
            let maxWidth = max(120, m.frame.width - m.centerLeftInset - m.centerRightInset)
            return CGSize(width: min(max(120, base), maxWidth), height: n.height)
        case .expanded: return CGSize(width: min(expandedWidth, m.frame.width - 24), height: max(expandedHeight, n.height))
        }
    }

    /// Borde del que sale la isla; define que esquinas se redondean.
    static func anchorEdge(_ placement: IslandPlacement) -> Edge {
        switch placement { case .top: return .top; case .bottom: return .bottom; case .side: return .trailing; case .floating: return .top }
    }
    enum Edge { case top, bottom, trailing }

    /// Radio de las esquinas de abajo (las de arriba son cuadradas para fundirse con el borde).
    static func cornerRadius(_ mode: IslandMode) -> CGFloat { mode == .expanded ? 30 : 14 }

    private static func visible(_ m: ScreenMetrics) -> CGRect { m.visibleFrame ?? m.frame }

    /// Rectangulo de la ventana que contiene la isla, segun la ubicacion elegida.
    static func panelFrame(_ m: ScreenMetrics, placement: IslandPlacement = .top) -> CGRect {
        let w = min(panelSize.width, m.frame.width), h = panelSize.height
        let cx = m.frame.midX + (placement == .floating ? m.floatingOffsetX : 0)
        let x = max(m.frame.minX, min(m.frame.maxX - w, cx - w / 2))
        switch placement {
        case .top: return CGRect(x: x, y: m.frame.maxY - h, width: w, height: h)
        case .bottom: return CGRect(x: x, y: visible(m).minY, width: w, height: h)
        case .side: return CGRect(x: m.frame.maxX - w, y: m.frame.midY - h / 2, width: w, height: h)
        case .floating: return CGRect(x: x, y: visible(m).maxY - floatingGap - h, width: w, height: h)
        }
    }

    /// Rectangulo de la isla en coordenadas de pantalla (para probar si el cursor esta encima).
    static func islandFrame(_ mode: IslandMode, metrics m: ScreenMetrics, placement: IslandPlacement = .top, expandedHeight: CGFloat = expandedHeight) -> CGRect {
        let s = islandSize(mode, metrics: m, placement: placement, expandedHeight: expandedHeight)
        switch placement {
        case .top: return CGRect(x: m.frame.midX - s.width / 2, y: m.frame.maxY - s.height, width: s.width, height: s.height)
        case .bottom: return CGRect(x: m.frame.midX - s.width / 2, y: visible(m).minY, width: s.width, height: s.height)
        case .side: return CGRect(x: m.frame.maxX - s.width, y: m.frame.midY - s.height / 2, width: s.width, height: s.height)
        case .floating:
            let cx = m.frame.midX + m.floatingOffsetX
            return CGRect(x: cx - s.width / 2, y: visible(m).maxY - floatingGap - s.height, width: s.width, height: s.height)
        }
    }

    static let permissionHeight: CGFloat = 224

    static func contains(_ p: CGPoint, mode: IslandMode, metrics m: ScreenMetrics, placement: IslandPlacement = .top, expandedHeight: CGFloat = expandedHeight) -> Bool {
        islandFrame(mode, metrics: m, placement: placement, expandedHeight: expandedHeight).insetBy(dx: -hitMargin, dy: -hitMargin).contains(p)
    }

    /// Zona que hace asomar a la mascota. Con notch es el notch; sin notch es una franja centrada de
    /// `activationWidth` (120 a 400 pt); con la barra de menus oculta se reduce a una linea en el borde.
    static func activationZone(metrics m: ScreenMetrics, placement: IslandPlacement = .top, activationWidth: CGFloat = 240) -> CGRect {
        let base = islandFrame(.hidden, metrics: m, placement: placement)
        let width = placement == .top && hasNotch(m) ? base.width : max(base.width, min(400, max(120, activationWidth)))
        var zone = CGRect(x: base.midX - width / 2, y: base.minY, width: width, height: base.height)
        if placement == .top && m.menuBarHidden { zone = CGRect(x: zone.minX, y: m.frame.maxY - edgeStripHeight, width: zone.width, height: edgeStripHeight) }
        return zone.insetBy(dx: -hitMargin, dy: placement == .top && m.menuBarHidden ? 0 : -hitMargin).intersection(m.frame)
    }

    /// El cursor esta sobre la zona de activacion. Es lo que hace asomar a la mascota.
    static func overNotch(_ p: CGPoint, metrics m: ScreenMetrics, placement: IslandPlacement = .top, activationWidth: CGFloat = 240) -> Bool {
        activationZone(metrics: m, placement: placement, activationWidth: activationWidth).contains(p)
    }

    /// Comprobacion de cordura usada por las pruebas: la isla cabe en la pantalla y queda centrada donde toca.
    static func fits(_ mode: IslandMode, metrics m: ScreenMetrics, placement: IslandPlacement = .top) -> Bool {
        let f = islandFrame(mode, metrics: m, placement: placement)
        guard m.frame.contains(f) else { return false }
        return placement == .side || abs(f.midX - (m.frame.midX + (placement == .floating ? m.floatingOffsetX : 0))) < 0.5
    }

    /// Eleccion de pantalla: la que tiene notch; si no, la primera (la de la barra de menus).
    static func pick(_ screens: [ScreenMetrics], preference: IslandScreenPreference = .notch, mouse: CGPoint? = nil) -> ScreenMetrics? {
        if preference == .mouse, let mouse, let screen = screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return screens.first(where: hasNotch) ?? screens.first
    }
}
