import Foundation

/// Modos de la isla que sale del notch (o de la barra superior en pantallas sin notch).
enum IslandMode: String, Equatable {
    case hidden, peek, compact, expanded
}

/// Por que esta abierta la isla; decide si se cierra sola.
enum IslandReason: Equatable {
    case none
    case hover        // el cursor se quedo sobre el notch o la isla compacta
    case click        // clic en la mascota
    case alert        // permiso, pregunta o error: no se cierra sola
    case finished     // tarea terminada: se cierra a los 5,2 s
}

/// Lo que la maquina necesita saber en cada tick (la app lo lee 60 veces por segundo).
struct IslandInput: Equatable {
    var now: TimeInterval
    /// El cursor esta sobre el notch (mas 6 pt de margen).
    var overNotch: Bool
    /// El cursor esta sobre la forma actual de la isla.
    var overIsland: Bool
    var tasksRunning: Bool
    var alertPending: Bool
    /// Una tarea acaba de terminar y aun no se mostro.
    var finishedPending: Bool
    /// Segundos desde el ultimo movimiento del raton, clic o tecla del usuario.
    var idleSeconds: TimeInterval
    var clickedPet: Bool = false
}

/// Reglas de comportamiento de la isla. Pura y sin reloj propio: la app le pasa `now`.
struct IslandMachine {
    static let peekToExpand: TimeInterval = 0.65
    static let peekLeave: TimeInterval = 0.6
    static let compactHoverToExpand: TimeInterval = 0.2
    static let autoClose: TimeInterval = 60
    static let countdownFrom: TimeInterval = 10
    static let away: TimeInterval = 180
    static let finishedHold: TimeInterval = 5.2

    private(set) var mode: IslandMode = .hidden
    private(set) var reason: IslandReason = .none
    private var enteredAt: TimeInterval = 0
    private var hoverSince: TimeInterval?
    private var leftSince: TimeInterval?
    private var lastActivity: TimeInterval = 0
    /// Cuenta atras (0...1) de los ultimos 10 s antes de plegarse; nil si no aplica.
    private(set) var countdown: Double?

    /// Con `away` ajustable por el usuario (por defecto 180 s).
    var awayAfter: TimeInterval = IslandMachine.away
    /// Tiempo que el cursor debe permanecer sobre la zona de activacion antes de asomar (0 = de inmediato).
    var activationDelay: TimeInterval = 0
    private var approachSince: TimeInterval?

    private mutating func go(_ m: IslandMode, _ r: IslandReason, _ now: TimeInterval) {
        mode = m; reason = r; enteredAt = now; lastActivity = now
        hoverSince = nil; leftSince = nil; countdown = nil
    }

    /// Modo en reposo cuando no hay nada que mostrar.
    private func resting(_ i: IslandInput) -> IslandMode {
        guard i.tasksRunning, i.idleSeconds < awayAfter else { return .hidden }
        return .compact
    }

    @discardableResult
    mutating func tick(_ i: IslandInput) -> IslandMode {
        let now = i.now

        // 7. las alertas abren sola la isla, incluso si el usuario esta ausente, y no se cierran solas.
        if i.alertPending {
            if !(mode == .expanded && reason == .alert) { go(.expanded, .alert, now) }
            return mode
        }
        if mode == .expanded && reason == .alert {
            // la alerta se respondio: vuelve al reposo
            go(resting(i), .none, now)
            return mode
        }

        // 8. terminado: vista de fin durante 5,2 s y despues se pliega.
        if i.finishedPending && !(mode == .expanded && reason == .finished) {
            go(.expanded, .finished, now)
            return mode
        }
        if mode == .expanded && reason == .finished {
            if now - enteredAt >= Self.finishedHold { go(resting(i), .none, now) }
            return mode
        }

        switch mode {
        case .hidden:
            if i.overNotch {
                // 2. el cursor sobre el notch asoma a la mascota, tras el retraso de activacion
                if approachSince == nil { approachSince = now }
                if now - (approachSince ?? now) >= activationDelay {
                    go(.peek, .hover, now)
                    hoverSince = now
                    approachSince = nil
                }
            } else {
                approachSince = nil
                if resting(i) == .compact { go(.compact, .none, now) }
            }

        case .peek:
            if i.clickedPet { go(.expanded, .click, now); break }
            if i.overNotch || i.overIsland {
                leftSince = nil
                if let h = hoverSince, now - h >= Self.peekToExpand { go(.expanded, .hover, now) }
            } else {
                if leftSince == nil { leftSince = now }
                if let l = leftSince, now - l >= Self.peekLeave { go(resting(i), .none, now) }
            }

        case .compact:
            if i.clickedPet { go(.expanded, .click, now); break }
            if !i.tasksRunning { go(.hidden, .none, now); break }
            if i.idleSeconds >= awayAfter { go(.hidden, .none, now); break }   // 6. usuario ausente
            if i.overIsland || i.overNotch {
                if hoverSince == nil { hoverSince = now }
                if let h = hoverSince, now - h >= Self.compactHoverToExpand { go(.expanded, .hover, now) }
            } else {
                hoverSince = nil
            }

        case .expanded:
            // 5. se pliega tras 60 s sin actividad; los ultimos 10 s muestran una cuenta atras.
            if i.overIsland || i.clickedPet { lastActivity = now }
            let quiet = now - lastActivity
            if quiet >= Self.autoClose {
                go(resting(i), .none, now)
            } else if quiet >= Self.autoClose - Self.countdownFrom {
                countdown = max(0, min(1, (Self.autoClose - quiet) / Self.countdownFrom))
            } else {
                countdown = nil
            }
        }
        return mode
    }
}
