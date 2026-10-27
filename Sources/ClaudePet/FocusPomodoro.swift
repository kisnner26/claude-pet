import Foundation

/// Modo foco: silencia lo menor y deja pasar solo lo que pide una decision o falla.
struct FocusMode: Equatable {
    var manual = false
    /// Horario opcional: hora de inicio y de fin (0...23). Puede cruzar la medianoche (22 a 7).
    var scheduleStart: Int?
    var scheduleEnd: Int?

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        if manual { return true }
        guard let start = scheduleStart, let end = scheduleEnd, (0...23).contains(start), (0...23).contains(end), start != end else { return false }
        let hour = calendar.component(.hour, from: date)
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// Con foco activo solo suenan las alertas (permisos, preguntas, error) y no se avisa de lo menor.
    func allows(_ cue: SoundCue, active: Bool) -> Bool { !active || cue.category == .alert }
}

/// Temporizador de enfoque: trabajo, descanso corto y descanso largo cada cuatro ciclos. Pura: recibe el reloj.
struct Pomodoro: Equatable {
    enum Phase: String { case idle, work, shortBreak = "descanso", longBreak = "descanso largo" }
    static let work: TimeInterval = 25 * 60
    static let shortBreak: TimeInterval = 5 * 60
    static let longBreak: TimeInterval = 15 * 60
    static let cyclesBeforeLong = 4

    private(set) var phase: Phase = .idle
    private(set) var phaseStart: TimeInterval = 0
    private(set) var completed = 0
    /// Tiempo acumulado en pausa dentro de la fase actual.
    private var paused: TimeInterval = 0
    private var pausedAt: TimeInterval?

    var isRunning: Bool { phase != .idle && pausedAt == nil }
    var isPaused: Bool { pausedAt != nil }
    var onBreak: Bool { phase == .shortBreak || phase == .longBreak }

    func length(of phase: Phase) -> TimeInterval {
        switch phase { case .idle: return 0; case .work: return Self.work; case .shortBreak: return Self.shortBreak; case .longBreak: return Self.longBreak }
    }

    mutating func start(now: TimeInterval) { phase = .work; phaseStart = now; paused = 0; pausedAt = nil }
    mutating func stop() { self = Pomodoro() }
    mutating func pause(now: TimeInterval) { if phase != .idle, pausedAt == nil { pausedAt = now } }
    mutating func resume(now: TimeInterval) { if let p = pausedAt { paused += now - p; pausedAt = nil } }

    func remaining(now: TimeInterval) -> TimeInterval {
        guard phase != .idle else { return 0 }
        let reference = pausedAt ?? now
        return max(0, length(of: phase) - (reference - phaseStart - paused))
    }

    /// Avanza de fase cuando se agota el tiempo. Devuelve la fase nueva si cambio (para avisar con un sonido).
    @discardableResult
    mutating func tick(now: TimeInterval) -> Phase? {
        guard isRunning, remaining(now: now) <= 0 else { return nil }
        let next: Phase
        switch phase {
        case .work:
            completed += 1
            next = completed % Self.cyclesBeforeLong == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: next = .work
        case .idle: return nil
        }
        phase = next; phaseStart = now; paused = 0
        return next
    }

    /// "24:59" para mostrar en la isla.
    func label(now: TimeInterval) -> String {
        let s = Int(remaining(now: now).rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
