import AppKit

/// Escucha las pulsaciones del sistema (el mismo permiso que los atajos globales) y alimenta `TypingRhythm`.
/// Solo mira el momento y si la tecla borra; no guarda que teclas ni el texto. Apagado por defecto.
@MainActor
final class TypingMonitor {
    static let shared = TypingMonitor()
    private var rhythm = TypingRhythm()
    private var token: Any?
    private var pending = 0
    private var flushTimer: Timer?

    var running: Bool { token != nil }

    /// El aviso vigente para la mascota, o nil.
    var note: String? { token == nil ? nil : rhythm.note(at: ProcessInfo.processInfo.systemUptime) }

    func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    private func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard !event.isARepeat else { return }
            let erase = TypingRhythm.erases(keyCode: event.keyCode)
            let t = ProcessInfo.processInfo.systemUptime
            MainActor.assumeIsolated {
                self?.rhythm.record(erase: erase, at: t)
                self?.pending += 1
            }
        }
        // las pulsaciones por hora se guardan en lotes: escribir a disco en cada tecla seria absurdo
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { TypingMonitor.shared.flush() } }
    }

    private func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        flushTimer?.invalidate(); flushTimer = nil
        flush()
        rhythm = TypingRhythm()
    }

    func flush() {
        guard pending > 0 else { return }
        ChronotypeStore.shared.addTyped(pending)
        pending = 0
    }
}
