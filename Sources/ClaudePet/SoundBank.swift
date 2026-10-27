import Foundation

/// Sonidos de la isla, sintetizados por claude pet. Ningun archivo de terceros.
/// Todos viven en una escala pentatonica de re mayor: lo que suena junto o seguido nunca choca.
/// Cuatro voces: campana (FM, brillante), marimba (madera suave), clic de papel (ruido filtrado) y golpe grave (error).
enum SoundCue: String, CaseIterable {
    case peek, open, fold, click, hover, permission, allowed, denied, question, done, error, greeting, rest

    enum Category: String, CaseIterable { case interface = "interfaz", alert = "alertas", pet = "mascota" }
    enum Voice { case bell, marimba, soft, tick, thud }

    var category: Category {
        switch self {
        case .peek, .open, .fold, .click, .hover: return .interface
        case .permission, .allowed, .denied, .question, .error: return .alert
        case .done, .greeting, .rest: return .pet
        }
    }

    /// Pentatonica de re mayor en dos octavas: re mi fa# la si.
    static let scale: [Double] = [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66]

    struct Note: Equatable {
        let frequency: Double
        let start: Double
        let duration: Double
        let gain: Double
        var voice: Voice = .bell
    }

    var notes: [Note] {
        let d4 = 293.66, a4 = 440.00, d5 = 587.33, e5 = 659.25, f5 = 739.99, a5 = 880.00, b5 = 987.77, d6 = 1174.66
        switch self {
        case .peek: return [Note(frequency: a5, start: 0, duration: 0.09, gain: 0.5, voice: .bell)]
        case .open: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.8, voice: .marimba), Note(frequency: a5, start: 0.07, duration: 0.14, gain: 0.8, voice: .marimba)]
        case .fold: return [Note(frequency: a5, start: 0, duration: 0.08, gain: 0.7, voice: .marimba), Note(frequency: d5, start: 0.07, duration: 0.12, gain: 0.7, voice: .marimba)]
        case .click: return [Note(frequency: 2400, start: 0, duration: 0.03, gain: 0.7, voice: .tick)]
        case .hover: return [Note(frequency: 3200, start: 0, duration: 0.02, gain: 0.3, voice: .tick)]
        case .permission: return [Note(frequency: a5, start: 0, duration: 0.1, gain: 0.9, voice: .bell), Note(frequency: d6, start: 0.14, duration: 0.14, gain: 0.9, voice: .bell)]
        case .allowed: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.8, voice: .marimba), Note(frequency: f5, start: 0.08, duration: 0.09, gain: 0.8, voice: .marimba), Note(frequency: a5, start: 0.16, duration: 0.16, gain: 0.85, voice: .marimba)]
        case .denied: return [Note(frequency: a5, start: 0, duration: 0.09, gain: 0.7, voice: .soft), Note(frequency: f5, start: 0.09, duration: 0.09, gain: 0.7, voice: .soft), Note(frequency: d5, start: 0.18, duration: 0.16, gain: 0.7, voice: .soft)]
        case .question: return [Note(frequency: e5, start: 0, duration: 0.09, gain: 0.85, voice: .bell), Note(frequency: b5, start: 0.1, duration: 0.14, gain: 0.85, voice: .bell)]
        case .done: return [Note(frequency: d5, start: 0, duration: 0.12, gain: 0.8, voice: .bell), Note(frequency: f5, start: 0.11, duration: 0.12, gain: 0.8, voice: .bell), Note(frequency: a5, start: 0.22, duration: 0.12, gain: 0.8, voice: .bell), Note(frequency: d6, start: 0.33, duration: 0.3, gain: 0.9, voice: .bell)]
        case .error: return [Note(frequency: d5, start: 0, duration: 0.1, gain: 0.8, voice: .thud), Note(frequency: d4, start: 0.1, duration: 0.26, gain: 0.9, voice: .thud)]
        case .greeting: return [Note(frequency: d5, start: 0, duration: 0.09, gain: 0.7, voice: .marimba), Note(frequency: a5, start: 0.09, duration: 0.09, gain: 0.7, voice: .marimba), Note(frequency: f5, start: 0.18, duration: 0.15, gain: 0.7, voice: .marimba)]
        case .rest: return [Note(frequency: a5, start: 0, duration: 0.16, gain: 0.5, voice: .soft), Note(frequency: f5, start: 0.16, duration: 0.16, gain: 0.5, voice: .soft), Note(frequency: d5, start: 0.32, duration: 0.24, gain: 0.5, voice: .soft)]
        }
    }

    /// Duracion nominal de las notas en segundos (la cola de reverberacion va aparte).
    var duration: Double { notes.map { $0.start + $0.duration }.max() ?? 0 }
    /// Ninguno pasa de 600 ms salvo "terminado".
    static let maxDuration = 0.6
    static let doneMaxDuration = 0.7
    /// Cola maxima de reverberacion tras la ultima nota.
    static let maxTail = 0.3

    /// Nivel de pico objetivo por categoria: lo de interfaz casi no se nota, las alertas se distinguen.
    var targetPeak: Float {
        switch category { case .interface: return 0.32; case .alert: return 0.62; case .pet: return 0.5 }
    }
}

enum SoundBank {
    static let sampleRate = 44_100.0

    /// Generador de ruido determinista (LCG) para que cada sonido sea siempre identico.
    private struct Noise {
        var state: UInt32
        mutating func next() -> Double {
            state = state &* 1664525 &+ 1013904223
            return Double(state >> 8) / Double(1 << 23) - 1
        }
    }

    /// Una nota con su voz. Devuelve muestras que pueden pasar de `duration` por la resonancia propia de la voz.
    private static func render(_ note: SoundCue.Note, ratio: Double, seed: UInt32) -> [Double] {
        let f = note.frequency * ratio
        let ring: Double
        switch note.voice { case .bell: ring = 0.22; case .marimba: ring = 0.1; case .soft: ring = 0.06; case .tick: ring = 0.0; case .thud: ring = 0.08 }
        let total = Int((note.duration + ring) * sampleRate)
        var out = [Double](repeating: 0, count: total)
        var noise = Noise(state: seed)
        var lowpass = 0.0
        for i in 0..<total {
            let t = Double(i) / sampleRate
            var y = 0.0
            switch note.voice {
            case .bell:
                // campana FM: el indice de modulacion cae rapido, asi nace brillante y se apaga redonda
                let index = 2.4 * exp(-7 * t)
                y = sin(2 * .pi * f * t + index * sin(2 * .pi * f * 2 * t)) * exp(-5.5 * t)
                y += 0.18 * sin(2 * .pi * f * 2.76 * t) * exp(-11 * t)
            case .marimba:
                // barra de madera: fundamental, un parcial a ~4x que muere enseguida y un golpe de ataque
                y = sin(2 * .pi * f * t) * exp(-9 * t)
                y += 0.32 * sin(2 * .pi * f * 3.98 * t) * exp(-38 * t)
                y += 0.08 * sin(2 * .pi * f * 9.9 * t) * exp(-90 * t)
            case .soft:
                // pad suave: seno con subarmonico, ataque lento y caida redonda
                let attack = min(1, t / 0.03)
                y = (sin(2 * .pi * f * t) + 0.25 * sin(2 * .pi * f * 0.5 * t)) * attack * exp(-4 * t / max(0.05, note.duration))
            case .tick:
                // clic de papel: ruido filtrado muy corto y un destello de tono
                let raw = noise.next()
                lowpass += 0.55 * (raw - lowpass)
                y = (raw - lowpass) * exp(-t / 0.006) * 0.9 + 0.35 * sin(2 * .pi * f * t) * exp(-t / 0.004)
            case .thud:
                // golpe grave: seno que baja de tono con un soplo de ruido grave
                let sweep = f * (1 - 0.35 * min(1, t / 0.12))
                let raw = noise.next(); lowpass += 0.08 * (raw - lowpass)
                y = sin(2 * .pi * sweep * t) * exp(-t / 0.1) + 0.5 * lowpass * exp(-t / 0.05)
            }
            let attack = note.voice == .soft ? 1 : min(1, t / 0.003)
            out[i] = y * attack * note.gain
        }
        return out
    }

    /// Reverberacion corta tipo Schroeder: cuatro peines y un pasa-todo. Da cuerpo sin alargar el sonido.
    private static func reverb(_ x: [Double], mix: Double) -> [Double] {
        let delays = [0.0297, 0.0371, 0.0411, 0.0437].map { Int($0 * sampleRate) }
        var wet = [Double](repeating: 0, count: x.count)
        for d in delays {
            var buf = [Double](repeating: 0, count: x.count)
            for i in 0..<x.count { buf[i] = x[i] + (i >= d ? buf[i - d] * 0.5 : 0) }
            for i in 0..<x.count { wet[i] += buf[i] * 0.25 }
        }
        return (0..<x.count).map { x[$0] * (1 - mix) + wet[$0] * mix }
    }

    /// Muestras mono en [-1, 1]. `semitones` sube el tono (alertas repetidas) sin cambiar la duracion.
    static func samples(for cue: SoundCue, semitones: Int = 0) -> [Float] {
        let ratio = pow(2.0, Double(max(0, min(4, semitones))) / 12.0)
        let tail = 0.18
        let total = Int((cue.duration + 0.22 + tail) * sampleRate)
        var mix = [Double](repeating: 0, count: total)
        for (n, note) in cue.notes.enumerated() {
            let begin = Int(note.start * sampleRate)
            for (i, v) in render(note, ratio: ratio, seed: UInt32(truncatingIfNeeded: cue.hashSeed &+ n * 7919)).enumerated() where begin + i < total { mix[begin + i] += v }
        }
        // la reverberacion solo da cuerpo a lo tonal; el clic de papel se queda seco
        let wetMix = cue == .click || cue == .hover ? 0.0 : 0.22
        var y = wetMix > 0 ? reverb(mix, mix: wetMix) : mix
        // cola que se apaga limpia: sin cortes ni clics al final
        let tailLength = wetMix > 0 ? SoundCue.maxTail : 0.05
        let fadeStart = Int((cue.duration + tailLength - min(0.12, tailLength)) * sampleRate)
        let end = min(y.count, Int((cue.duration + tailLength) * sampleRate))
        y = Array(y.prefix(end))
        for i in max(0, fadeStart)..<y.count { y[i] *= max(0, 1 - Double(i - fadeStart) / Double(max(1, y.count - fadeStart))) }
        // nivel de pico fijo por categoria; los objetivos son bajos, asi que no hace falta limitar
        let peak = max(1e-9, y.map { abs($0) }.max() ?? 1)
        let scale = Double(cue.targetPeak) / peak
        return y.map { Float($0 * scale) }.map { max(-0.95, min(0.95, $0)) }
    }

    /// Ritmo de las alertas repetidas: cada aviso igual en menos de 30 s sube un semitono, hasta cuatro.
    static func escalation(previousCount: Int) -> Int { min(4, max(0, previousCount)) }

    /// WAV de 16 bits mono, para escuchar los sonidos fuera de la app.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        data.append("RIFF".data(using: .ascii)!); u32(36 + bytes); data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        return data
    }
}

private extension SoundCue {
    /// Semilla estable por sonido (no usa hashValue, que cambia entre ejecuciones).
    var hashSeed: Int { rawValue.unicodeScalars.reduce(17) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } }
}
