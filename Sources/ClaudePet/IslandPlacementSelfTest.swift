import Foundation
import CoreGraphics

/// `ClaudePet --selftest-placement`: geometria por ubicacion y matriz de pantallas sinteticas.
enum IslandPlacementSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        func screen(_ name: String, _ w: CGFloat, _ h: CGFloat, bar: CGFloat, notch: CGFloat = 0, dock: CGFloat = 70, hidden: Bool = false, x: CGFloat = 0) -> (String, ScreenMetrics) {
            let frame = CGRect(x: x, y: 0, width: w, height: h)
            let top = hidden ? 0 : bar
            let visible = CGRect(x: x, y: dock, width: w, height: h - dock - top)
            var m = ScreenMetrics(frame: frame, safeTop: notch, auxLeft: notch > 0 ? (w - 184) / 2 : 0, auxRight: notch > 0 ? (w - 184) / 2 : 0, menuBarHeight: bar)
            m.visibleFrame = visible; m.menuBarHidden = hidden
            return (name, m)
        }
        let matrix = [
            screen("macbook pro 13 2020 sin notch", 1440, 900, bar: 24),
            screen("macbook air 13 sin notch, mas espacio", 1680, 1050, bar: 24),
            screen("macbook pro 14 con notch", 1512, 982, bar: 38, notch: 38),
            screen("imac 24", 2240, 1260, bar: 24),
            screen("monitor 4k escalado", 3008, 1692, bar: 24, x: 1512),
            screen("monitor 1080p", 1920, 1080, bar: 24, x: 4520),
            screen("barra autooculta", 1440, 900, bar: 24, hidden: true),
        ]
        for (name, m) in matrix {
            for placement in IslandPlacement.allCases {
                for mode in [IslandMode.hidden, .peek, .compact, .expanded] {
                    check("\(name) · \(placement.rawValue) · \(mode): cabe y queda donde toca", NotchGeometry.fits(mode, metrics: m, placement: placement))
                }
                let pf = NotchGeometry.panelFrame(m, placement: placement)
                check("\(name) · \(placement.rawValue): la ventana cae dentro de la pantalla", m.frame.contains(pf))
            }
        }

        let (_, mac) = matrix[0]
        let (_, notched) = matrix[2]
        let (_, hidden) = matrix[6]

        // ubicaciones
        let top = NotchGeometry.islandFrame(.compact, metrics: mac, placement: .top)
        check("arriba: pegada al borde superior", top.maxY == mac.frame.maxY)
        let bottom = NotchGeometry.islandFrame(.compact, metrics: mac, placement: .bottom)
        check("abajo: encima del dock, no detras", bottom.minY == mac.visibleFrame!.minY && bottom.minY >= 70)
        let side = NotchGeometry.islandFrame(.compact, metrics: mac, placement: .side)
        check("lateral: pegada al borde derecho y centrada en vertical", side.maxX == mac.frame.maxX && abs(side.midY - mac.frame.midY) < 0.5)
        let floating = NotchGeometry.islandFrame(.compact, metrics: mac, placement: .floating)
        check("flotante: separada 8 pt de la barra de menus", floating.maxY == mac.visibleFrame!.maxY - 8)
        var moved = mac; moved.floatingOffsetX = 120
        check("flotante: recuerda el desplazamiento horizontal", NotchGeometry.islandFrame(.compact, metrics: moved, placement: .floating).midX == mac.frame.midX + 120)
        var edge = mac; edge.floatingOffsetX = 10_000
        check("flotante: el desplazamiento nunca la saca de la pantalla", mac.frame.contains(NotchGeometry.panelFrame(edge, placement: .floating)))
        check("con notch, fuera de arriba la isla usa una barra normal", NotchGeometry.notchSize(notched, placement: .bottom).width == NotchGeometry.barWidth)
        check("con notch, arriba usa el notch real", NotchGeometry.notchSize(notched, placement: .top).width == 184)

        // zona de activacion
        check("sin notch la zona de activacion es configurable (120)", NotchGeometry.activationZone(metrics: mac, activationWidth: 120).width == 120 + NotchGeometry.hitMargin * 2)
        check("sin notch la zona de activacion es configurable (400)", NotchGeometry.activationZone(metrics: mac, activationWidth: 400).width == 400 + NotchGeometry.hitMargin * 2)
        check("la zona se acota a 120...400", NotchGeometry.activationZone(metrics: mac, activationWidth: 10).width == 120 + 12 && NotchGeometry.activationZone(metrics: mac, activationWidth: 9000).width == 400 + 12)
        check("con notch la zona sigue siendo el notch", NotchGeometry.activationZone(metrics: notched, activationWidth: 400).width == 184 + 12)
        check("con la barra oculta la zona es una franja fina en el borde", NotchGeometry.activationZone(metrics: hidden).height <= NotchGeometry.edgeStripHeight + 0.1 && NotchGeometry.activationZone(metrics: hidden).maxY == hidden.frame.maxY)
        check("la franja del borde no cubre las ventanas de la app", !NotchGeometry.overNotch(CGPoint(x: hidden.frame.midX, y: hidden.frame.maxY - 30), metrics: hidden))
        check("el cursor en el borde superior activa la isla", NotchGeometry.overNotch(CGPoint(x: hidden.frame.midX, y: hidden.frame.maxY - 1), metrics: hidden))
        check("el cursor a un lado de la zona no activa", !NotchGeometry.overNotch(CGPoint(x: mac.frame.midX + 200, y: mac.frame.maxY - 5), metrics: mac, activationWidth: 240))

        // pantallas mixtas: cada una conserva su geometria
        let external = matrix[4].1
        check("dos pantallas no se mezclan", NotchGeometry.panelFrame(notched).midX == notched.frame.midX && NotchGeometry.panelFrame(external).midX == external.frame.midX)
        check("la abierta nunca desborda una pantalla estrecha", NotchGeometry.islandSize(.expanded, metrics: ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 500, height: 400), safeTop: 0, auxLeft: 0, auxRight: 0)).width <= 476)

        // contenido compacto
        check("el modo minimo solo muestra el estado", IslandCompactMode.minimal.items == .init())
        check("el modo normal añade contexto y avisos", IslandCompactMode.normal.items.context && IslandCompactMode.normal.items.badge && !IslandCompactMode.normal.items.branch)
        check("el modo completo añade duracion y rama", IslandCompactMode.full.items.duration && IslandCompactMode.full.items.branch)
        check("el ancho crece con el modo y con el reloj", IslandCompactMode.minimal.contentWidth(clock: false) < IslandCompactMode.normal.contentWidth(clock: false)
              && IslandCompactMode.normal.contentWidth(clock: false) < IslandCompactMode.full.contentWidth(clock: false)
              && IslandCompactMode.normal.contentWidth(clock: true) > IslandCompactMode.normal.contentWidth(clock: false))
        let narrow = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 800, height: 600), safeTop: 0, auxLeft: 0, auxRight: 0, centerLeftInset: 300, centerRightInset: 300)
        let compactW = NotchGeometry.islandSize(.compact, metrics: narrow, compactContentWidth: IslandCompactMode.full.contentWidth(clock: true)).width
        check("el modo completo se acota al espacio libre de la barra", compactW <= 200 && compactW >= 120)

        print(failures == 0 ? "UBICACION OK" : "UBICACION FALLOS: \(failures)")
        return failures == 0
    }
}
