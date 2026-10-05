import Foundation

/// Parametros del partido. Los valores por defecto son los de producto; las variables de
/// entorno existen solo para pruebas manuales y no cambian nada global.
struct FootballConfig {
    /// Segundos de inactividad compartida antes de empezar.
    var idleDelay: TimeInterval = 8
    /// Minimo entre dos inicios (un partido cancelado tambien cuenta).
    var cooldown: TimeInterval = 300

    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> FootballConfig {
        var c = FootballConfig()
        if let v = env["CLAUDE_PET_FOOTBALL_IDLE_SECONDS"].flatMap(Double.init), v >= 1 { c.idleDelay = v }
        if let v = env["CLAUDE_PET_FOOTBALL_COOLDOWN"].flatMap(Double.init), v >= 5 { c.cooldown = v }
        return c
    }
}

/// Maquina de estados del partido. Solo logica: sin UI, sin sockets, sin reloj propio
/// (el tiempo entra por parametro, asi se puede probar con un reloj falso).
///
/// Deduce el juego unicamente de la presencia y el estado que ya existen en el protocolo v1:
///  - empieza cuando Claude y el par estan en `idle` durante `idleDelay` segundos seguidos
///    y han pasado `cooldown` segundos desde el ultimo inicio;
///  - se cancela al instante si cualquiera sale de `idle` (starting, thinking, tool, waiting,
///    error y tambien done) o si el par desaparece o no reporta un estado conocido.
final class FootballGame {
    let config: FootballConfig
    private(set) var startedAt: Date?
    /// Partido lanzado a mano: dura entera aunque cambien los estados o el par no exista.
    private(set) var forced = false
    private var lastStart: Date?
    private var sharedIdleSince: Date?

    init(config: FootballConfig = FootballConfig()) { self.config = config }

    var isActive: Bool { startedAt != nil }

    func cancel() { startedAt = nil; forced = false }

    /// Disparador manual (menu o linea de comandos): empieza ya, sin espera, sin cooldown y sin
    /// exigir al par ni inactividad. El inicio cuenta para el cooldown automatico.
    func forceStart(now: Date) {
        guard startedAt == nil else { return }
        startedAt = now; lastStart = now; forced = true
    }

    /// - Parameters:
    ///   - claude: estado de esta mascota.
    ///   - peer: estado del par; `nil` si no hay par o su estado es desconocido.
    func update(now: Date, claude: PetState, peer: PetState?) {
        if forced, let s = startedAt {
            if now.timeIntervalSince(s) >= FootballChoreography.duration { startedAt = nil; forced = false; sharedIdleSince = nil }
            return
        }
        guard claude == .idle, peer == .idle else {
            sharedIdleSince = nil
            startedAt = nil              // cancelacion inmediata (el cooldown sigue contando)
            return
        }
        if sharedIdleSince == nil { sharedIdleSince = now }

        if let s = startedAt {
            if now.timeIntervalSince(s) >= FootballChoreography.duration {
                startedAt = nil          // termino solo
                sharedIdleSince = nil    // exigira otra espera de inactividad compartida
            }
            return
        }
        guard let idleFor = sharedIdleSince.map({ now.timeIntervalSince($0) }), idleFor >= config.idleDelay else { return }
        if let last = lastStart, now.timeIntervalSince(last) < config.cooldown { return }
        startedAt = now
        lastStart = now
    }

    /// Segundos desde el inicio, o `nil` si no hay partido en curso.
    func elapsed(at date: Date) -> TimeInterval? {
        guard let s = startedAt else { return nil }
        let e = date.timeIntervalSince(s)
        return e >= 0 && e < FootballChoreography.duration ? e : nil
    }
}
