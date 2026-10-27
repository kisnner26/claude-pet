import Foundation

/// Sonidos de la isla, sintetizados por claude pet (senos con envolvente). Ningun archivo de terceros.
/// Todos viven en una escala pentatonica de re mayor: lo que suena junto o seguido nunca choca.
enum SoundCue: String, CaseIterable {
    case peek, open, fold, click, hover, permission, allowed, denied, question, done, error, greeting, rest

    enum Category: String, CaseIterable { case interface = "interfaz", alert = "alertas", pet = "mascota" }

    var category: Category {
        switch self {
        case .peek, .open, .fold, .click, .hover: return .interface
        case .permission, .allowed, .denied, .question, .error: return .alert
        case .done, .greeting, .rest: return .pet
        }
    }

    /// Notas de la escala: re5 mi5 fa#5 la5 si5 re6 y la4 para los graves.
    static let scale: [Double] = [440.00, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66]

    struct Note: Equatable { let frequency: Double; let start: Double; let duration: Double; let gain: Double }

    var notes: [Note] {
        let d5 = 587.33, e5 = 659.25, f5 = 739.99, a5 = 880.00, b5 = 987.77, d6 = 1174.66, a4 = 440.00
        switch self {
        case .peek: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.35)]
        case .open: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.4), Note(frequency: a5, start: 0.07, duration: 0.12, gain: 0.4)]
        case .fold: return [Note(frequency: a5, start: 0, duration: 0.08, gain: 0.35), Note(frequency: d5, start: 0.07, duration: 0.11, gain: 0.35)]
        case .click: return [Note(frequency: f5, start: 0, duration: 0.045, gain: 0.45)]
        case .hover: return [Note(frequency: b5, start: 0, duration: 0.04, gain: 0.18)]
        case .permission: return [Note(frequency: a5, start: 0, duration: 0.09, gain: 0.5), Note(frequency: a5, start: 0.13, duration: 0.11, gain: 0.5)]
        case .allowed: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.45), Note(frequency: f5, start: 0.08, duration: 0.09, gain: 0.45), Note(frequency: a5, start: 0.16, duration: 0.14, gain: 0.45)]
        case .denied: return [Note(frequency: a5, start: 0, duration: 0.09, gain: 0.45), Note(frequency: f5, start: 0.08, duration: 0.09, gain: 0.45), Note(frequency: d5, start: 0.16, duration: 0.14, gain: 0.45)]
        case .question: return [Note(frequency: e5, start: 0, duration: 0.09, gain: 0.45), Note(frequency: b5, start: 0.1, duration: 0.12, gain: 0.45)]
        case .done: return [Note(frequency: d5, start: 0, duration: 0.12, gain: 0.45), Note(frequency: f5, start: 0.11, duration: 0.12, gain: 0.45), Note(frequency: a5, start: 0.22, duration: 0.12, gain: 0.45), Note(frequency: d6, start: 0.33, duration: 0.3, gain: 0.45)]
        case .error: return [Note(frequency: d5, start: 0, duration: 0.12, gain: 0.5), Note(frequency: a4, start: 0.12, duration: 0.24, gain: 0.5)]
        case .greeting: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.35), Note(frequency: a5, start: 0.09, duration: 0.09, gain: 0.35), Note(frequency: f5, start: 0.18, duration: 0.13, gain: 0.35)]
        case .rest: return [Note(frequency: a5, start: 0, duration: 0.16, gain: 0.25), Note(frequency: f5, start: 0.16, duration: 0.16, gain: 0.25), Note(frequency: d5, start: 0.32, duration: 0.24, gain: 0.25)]
        }
    }

    /// Duracion total en segundos.
    var duration: Double { notes.map { $0.start + $0.duration }.max() ?? 0 }
    /// Ninguno pasa de 600 ms salvo "terminado".
    static let maxDuration = 0.6
    static let doneMaxDuration = 0.7
}

enum SoundBank {
    static let sampleRate = 44_100.0

    /// Muestras mono en [-1, 1]. `semitones` sube el tono (alertas repetidas) sin cambiar la duracion.
    static func samples(for cue: SoundCue, semitones: Int = 0) -> [Float] {
        let ratio = pow(2.0, Double(max(0, min(4, semitones))) / 12.0)
        let total = Int((cue.duration + 0.02) * sampleRate)
        var out = [Float](repeating: 0, count: total)
        for note in cue.notes {
            let begin = Int(note.start * sampleRate), count = Int(note.duration * sampleRate)
            guard count > 0 else { continue }
            let attack = max(1, Int(0.006 * sampleRate))
            for i in 0..<count where begin + i < total {
                let t = Double(i) / sampleRate
                // seno con un poco de segundo armonico para que no suene a pitido
                let tone = sin(2 * .pi * note.frequency * ratio * t) + 0.22 * sin(4 * .pi * note.frequency * ratio * t)
                let attackGain = i < attack ? Double(i) / Double(attack) : 1
                let release = exp(-4.2 * Double(i) / Double(count))
                out[begin + i] += Float(tone * attackGain * release * note.gain / 1.22)
            }
        }
        return out.map { max(-0.95, min(0.95, $0)) }
    }

    /// Ritmo de las alertas repetidas: cada aviso igual en menos de 30 s sube un semitono, hasta cuatro.
    static func escalation(previousCount: Int) -> Int { min(4, max(0, previousCount)) }
}
