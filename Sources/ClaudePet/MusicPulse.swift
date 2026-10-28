import Foundation

/// Un instante del audio que suena: volumen y energia por bandas (0...1, ya normalizadas) y si acaba de haber un pulso.
struct AudioFrame: Equatable {
    var level = 0.0
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0
    var beat = false
    var bpm: Double?
    var beatCount = 0
}

/// Analiza audio mono en tiempo real, sin FFT: tres filtros de un polo separan graves (<150 Hz), medios (<2 kHz) y agudos,
/// la energia se mide cada 10 ms y un detector de onsets con umbral adaptativo marca los pulsos. Los intervalos entre
/// pulsos dan el tempo. Es puro: recibe muestras y devuelve cuadros, asi se prueba con senales sinteticas.
struct AudioAnalyzer {
    let sampleRate: Double
    private let hop: Int
    private let aLow: Double, aMid: Double
    private var lpLow = 0.0, lpMid = 0.0
    private var sumB = 0.0, sumM = 0.0, sumT = 0.0, sumAll = 0.0
    private var n = 0
    private var peak = 1e-3                 // referencia comun de las tres bandas: asi el ruido de fondo no parece una banda llena
    private var silentHops = 0
    private var smoothed = 0.0, prevSmoothed = 0.0
    private var fluxHistory: [Double] = []
    private var hopIndex = 0
    private var lastBeatHop = -1000
    private var intervals: [Double] = []
    private(set) var beatCount = 0
    private(set) var bpm: Double?
    private var lastLevel = 0.0, lastB = 0.0, lastM = 0.0, lastT = 0.0

    static let hopSeconds = 0.01
    static let refractory = 0.24          // como mucho ~250 pulsos por minuto
    static let silenceFloor = 0.0015      // por debajo (~ -56 dB) no hay musica

    init(sampleRate: Double) {
        self.sampleRate = max(8_000, sampleRate)
        hop = max(1, Int(self.sampleRate * Self.hopSeconds))
        aLow = 1 - exp(-2 * .pi * 150 / self.sampleRate)
        aMid = 1 - exp(-2 * .pi * 2_000 / self.sampleRate)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    mutating func process(_ samples: [Float]) -> [AudioFrame] {
        var frames: [AudioFrame] = []
        for s in samples {
            let x = Double(s.isFinite ? s : 0)
            lpLow += aLow * (x - lpLow)
            lpMid += aMid * (x - lpMid)
            let bass = lpLow, mid = lpMid - lpLow, treble = x - lpMid
            sumB += bass * bass; sumM += mid * mid; sumT += treble * treble; sumAll += x * x
            n += 1
            if n == hop { frames.append(finishHop()); n = 0; sumB = 0; sumM = 0; sumT = 0; sumAll = 0 }
        }
        return frames
    }

    private mutating func finishHop() -> AudioFrame {
        let d = Double(hop)
        let rb = (sumB / d).squareRoot(), rm = (sumM / d).squareRoot(), rt = (sumT / d).squareRoot(), rAll = (sumAll / d).squareRoot()
        hopIndex += 1
        // normalizacion automatica con una sola referencia (cae despacio); medios y agudos se compensan porque la musica tiene menos energia ahi
        peak = max(rb, rm * 1.5, rt * 2.5, peak * 0.9996)
        let silent = rAll < Self.silenceFloor
        let db = 20 * log10(max(rAll, 1e-6))
        let level = silent ? 0 : Self.clamp((db + 60) / 50)
        // los graves mandan en el pulso; los medios ayudan con percusion sin bombo
        let energy = rb + 0.5 * rm
        smoothed = 0.5 * smoothed + 0.5 * energy
        let flux = max(0, smoothed - prevSmoothed)
        prevSmoothed = smoothed
        fluxHistory.append(flux); if fluxHistory.count > 120 { fluxHistory.removeFirst() }
        let mean = fluxHistory.reduce(0, +) / Double(fluxHistory.count)
        let variance = fluxHistory.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(fluxHistory.count)
        let threshold = mean + 2.2 * variance.squareRoot() + 0.04 * peak
        var beat = false
        let sinceBeat = Double(hopIndex - lastBeatHop) * Self.hopSeconds
        if !silent, flux > threshold, sinceBeat >= Self.refractory {
            beat = true; beatCount += 1
            if lastBeatHop > 0, sinceBeat < 1.6 { intervals.append(sinceBeat); if intervals.count > 12 { intervals.removeFirst() } }
            if sinceBeat >= 1.6 { intervals.removeAll() }      // pausa larga: el tempo anterior ya no vale
            lastBeatHop = hopIndex
            bpm = estimateBPM()
        }
        silentHops = silent ? silentHops + 1 : 0
        if silentHops > 100 { bpm = nil; intervals.removeAll() }       // un segundo de silencio real: el tempo anterior ya no vale
        lastLevel = level
        // suavizado de bajada: la barra cae rapido pero no de golpe
        func fall(_ v: Double, _ last: Double) -> Double { max(v, last * 0.82) }
        lastB = fall(silent ? 0 : Self.clamp(rb / peak), lastB); lastM = fall(silent ? 0 : Self.clamp(rm * 1.5 / peak), lastM); lastT = fall(silent ? 0 : Self.clamp(rt * 2.5 / peak), lastT)
        return AudioFrame(level: level, bass: lastB, mid: lastM, treble: lastT, beat: beat, bpm: bpm, beatCount: beatCount)
    }

    /// Tempo a partir de la mediana de los ultimos intervalos, plegado a 70...180. nil si no hay regularidad.
    private func estimateBPM() -> Double? {
        guard intervals.count >= 4 else { return nil }
        let sorted = intervals.sorted(), median = sorted[sorted.count / 2]
        let close = intervals.filter { abs($0 - median) / median < 0.18 }.count
        guard Double(close) / Double(intervals.count) >= 0.6, median > 0 else { return nil }
        var v = 60 / median
        while v < 70 { v *= 2 }
        while v > 180 { v /= 2 }
        return v
    }
}

/// Lo que la mascota sabe de la musica en un instante. Con `listening` viene del audio real; sin el, de lo que dicen las apps.
struct MusicPulse: Equatable {
    var playing = false
    var listening = false
    var level = 0.0, bass = 0.0, mid = 0.0, treble = 0.0
    /// Segundos desde el ultimo pulso; nil si no hay.
    var beatAge: TimeInterval?
    var beatCount = 0
    var bpm: Double?
    /// Volumen de la app de musica, 0...1.
    var volume = 0.5
    var startedAge: TimeInterval?
    var pausedAge: TimeInterval?
}

/// Como baila la mascota con la musica: puro, recibe el tiempo y el pulso y devuelve la pose.
enum MusicDance {
    static let beatLength: TimeInterval = 0.34
    static let startLength: TimeInterval = 0.9
    static let pauseLength: TimeInterval = 1.8

    /// Golpe seco y caida suave: 1 en el pulso, 0 al cabo de `beatLength`.
    static func envelope(beatAge: TimeInterval) -> Double {
        guard beatAge >= 0, beatAge < beatLength else { return 0 }
        let k = 1 - beatAge / beatLength
        return k * k
    }

    static func apply(_ p: inout PetPose, t: TimeInterval, music m: MusicPulse) {
        p.dancing = true
        if m.listening, let age = m.beatAge {
            let env = envelope(beatAge: age)
            let dir: Double = m.beatCount % 2 == 0 ? 1 : -1
            p.dy -= CGFloat((0.5 + 1.6 * m.bass) * env)                       // salta con el bombo
            p.scaleY *= CGFloat(1 - 0.05 * env * (0.5 + m.bass))
            p.scaleX *= CGFloat(1 + 0.03 * env)
            p.rotation = dir * (2 + 7 * m.level) * env + 1.2 * sin(t * 2 * .pi * 0.5)     // cabeceo alternado y balanceo lento
            p.happy = m.level > 0.45
        } else {
            // sin audio: ritmo fijo, pero la fuerza sigue al volumen de la app
            let v = 0.35 + 0.65 * min(1, max(0, m.volume))
            p.rotation = 6 * v * sin(t * 2 * .pi * 2)
            p.dy -= CGFloat(0.8 * v * abs(sin(t * 2 * .pi * 2)))
        }
    }

    /// Reacciones a lo que dicen las apps, sin necesidad de oir el audio: un salto al empezar y un suspiro al pausar.
    static func transients(_ p: inout PetPose, music m: MusicPulse) {
        if let s = m.startedAge, s >= 0, s < startLength {
            p.dy -= CGFloat(2.2 * sin(.pi * s / startLength))
            p.scaleY *= CGFloat(1 + 0.05 * sin(.pi * s / startLength))
        }
        if let a = m.pausedAge, a >= 0, a < pauseLength {
            let k = 1 - a / pauseLength
            p.scaleY *= CGFloat(1 - 0.06 * k)
            if a > 0.35 { p.blink = true }
        }
    }
}

/// Efectos del compas: un aro que sale en cada pulso y tres barras que enseñan graves, medios y agudos.
extension MusicFx {
    static let bandColors: [UInt32] = [0x7FD1FF, 0xFF9FD0, 0xFFD166]

    static func beat(pulse m: MusicPulse, colors: [UInt32]? = nil) -> [FxPixel] {
        let bandColors = colors ?? Self.bandColors
        guard m.listening else { return [] }
        var out: [FxPixel] = []
        // tres barras de ecualizador a los pies
        for (i, v) in [m.bass, m.mid, m.treble].enumerated() {
            let x = 0.05 + Double(i) * 0.06                     // a un lado, fuera de la mascota
            let h = max(1, Int((min(1, max(0, v)) * 7).rounded()))
            for k in 0..<h { out.append(FxPixel(x: x, y: 0.93 - Double(k) * 0.034, size: 2.4, color: bandColors[i], alpha: 0.55 + 0.4 * v)) }
        }
        // aro en cada pulso
        if let age = m.beatAge, age < MusicDance.beatLength {
            let p = age / MusicDance.beatLength, strong = 0.4 + 0.6 * m.bass
            for k in 0..<14 {
                let a = Double(k) / 14 * 2 * .pi
                out.append(FxPixel(x: 0.5 + cos(a) * (0.34 + 0.12 * p), y: 0.48 + sin(a) * (0.30 + 0.12 * p), size: 1.6, color: bandColors[k % 3], alpha: (1 - p) * strong))      // nace fuera de la cara y se abre
            }
        }
        return out
    }
}
