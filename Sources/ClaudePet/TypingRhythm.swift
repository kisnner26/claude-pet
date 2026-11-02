import Foundation

/// El ritmo con que escribes, sin saber que escribes: solo cuenta cuando pulsas y si la tecla borra. Nunca guarda cual tecla fue.
/// Con eso avisa de dos cosas: que llevas rato peleandote con algo (muchas teclas y mucho borrado) y que llevas demasiado sin parar.
struct TypingRhythm {
    static let window: TimeInterval = 30
    static let strainMinKeys = 60
    static let strainEraseShare = 0.30
    static let breakAfter: TimeInterval = 50 * 60
    static let restGap: TimeInterval = 5 * 60

    private(set) var recent: [(at: TimeInterval, erase: Bool)] = []
    private(set) var sessionStart: TimeInterval?
    private(set) var lastKey: TimeInterval?

    /// Las teclas que borran: retroceso y suprimir.
    static func erases(keyCode: UInt16) -> Bool { keyCode == 51 || keyCode == 117 }

    mutating func record(erase: Bool, at t: TimeInterval) {
        // una pausa larga cierra la racha: la siguiente tecla abre otra
        if sessionStart == nil || (lastKey.map { t - $0 > Self.restGap } ?? true) { sessionStart = t }
        lastKey = t
        recent.append((t, erase))
        recent.removeAll { t - $0.at > Self.window }
    }

    private func inWindow(_ t: TimeInterval) -> [(at: TimeInterval, erase: Bool)] { recent.filter { t - $0.at <= Self.window } }

    func keysPerMinute(at t: TimeInterval) -> Double { Double(inWindow(t).count) * 60 / Self.window }

    func eraseShare(at t: TimeInterval) -> Double {
        let w = inWindow(t)
        return w.isEmpty ? 0 : Double(w.filter(\.erase).count) / Double(w.count)
    }

    /// Mucho tecleo y mucho borrado a la vez: reescribir sin parar suele ser pelea, no avance.
    func isStrained(at t: TimeInterval) -> Bool {
        inWindow(t).count >= Self.strainMinKeys && eraseShare(at: t) >= Self.strainEraseShare
    }

    /// Minutos seguidos tecleando sin una pausa de cinco; nil si no hay racha viva.
    func streakMinutes(at t: TimeInterval) -> Int? {
        guard let s = sessionStart, let l = lastKey, t - l < Self.restGap else { return nil }
        return Int((t - s) / 60)
    }

    func needsBreak(at t: TimeInterval) -> Bool { (streakMinutes(at: t) ?? 0) * 60 >= Int(Self.breakAfter) }

    /// El aviso para la mascota; el esfuerzo manda sobre el descanso.
    func note(at t: TimeInterval) -> String? {
        if isStrained(at: t) { return "respira un momento" }
        if needsBreak(at: t), let m = streakMinutes(at: t) { return "llevas \(m) min seguidos: descansa" }
        return nil
    }
}
