import Foundation
import CoreGraphics

/// Si la isla en reposo se ve como una pastilla negra. Con notch real o con la barra de menus oculta no se dibuja nada;
/// sin notch se dibuja una pastilla del tamano del notch, salvo que el usuario haya pedido la pildora invisible.
enum IslandRestingLook {
    static func pillVisible(mode: IslandMode, hasNotch: Bool, menuBarHidden: Bool, hideCompact: Bool) -> Bool {
        guard mode == .hidden else { return true }
        return !(hasNotch || menuBarHidden || hideCompact)
    }
}

enum IslandPollingPolicy {
    /// treinta actualizaciones por segundo mantienen el seguimiento fluido sin forzar
    /// una reevaluación de toda la isla a 60 hz.
    static let activeInterval: TimeInterval = 1.0 / 30.0
    static let idleInterval: TimeInterval = 1.0
    /// Isla en reposo y visible (compacta, sin trabajo ni avisos, con el cursor lejos): 10 actualizaciones por segundo bastan para la mirada.
    static let calmCompactInterval: TimeInterval = 0.1

    static func interval(hidden: Bool, tasksRunning: Bool, attention: Bool, cursorNearZone: Bool = false, compact: Bool = false) -> TimeInterval {
        if tasksRunning || attention || cursorNearZone { return activeInterval }
        if hidden { return idleInterval }
        return compact ? calmCompactInterval : activeInterval
    }

    /// Con la isla oculta se duerme a 1 Hz, pero el cursor acercandose a la zona de activacion la despierta de inmediato
    /// (un monitor global del raton): si no, asomar tardaria hasta tres ticks de un segundo.
    static func isNearZone(_ p: CGPoint, zone: CGRect, margin: CGFloat = 40) -> Bool { zone.insetBy(dx: -margin, dy: -margin).contains(p) }
}
