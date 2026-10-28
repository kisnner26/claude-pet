import Foundation
import AVFoundation
import Accelerate

/// Sincronia del video con una cancion: mide el tempo y el instante de los golpes con el bombo (banda grave) y con toda la señal,
/// y elige un trozo de la cancion que empiece en un golpe y tenga energia. Sirve para canciones de tempo fijo.
enum MusicSync {
    struct Result: Equatable {
        var bpm: Double
        /// Segundo de la cancion en el que cae un golpe de la rejilla.
        var phase: Double
        /// Segundo donde empezar el trozo (un golpe de la rejilla, al inicio de un compas).
        var start: Double
        /// Cuanto destaca el tempo elegido sobre los demas (1 = nada, mas = claro).
        var confidence: Double
        var duration: Double
    }

    static func analyze(path: String, clipSeconds: Double) -> Result? {
        guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)), (try? f.read(into: buf)) != nil,
              let ch = buf.floatChannelData, buf.frameLength > 0 else { return nil }
        let sr = f.processingFormat.sampleRate, len = Int(buf.frameLength), hop = 256
        let total = Double(len) / sr
        // dos envolventes: el bombo (paso bajo ~120 Hz) y la señal completa
        let a = Float(1 - exp(-2 * Double.pi * 120 / sr))
        var low = [Float](repeating: 0, count: len), y: Float = 0
        for i in 0..<len { y += a * (ch[0][i] - y); low[i] = y }
        func envelope(_ x: [Float]) -> [Float] {
            var out: [Float] = []; var i = 0
            x.withUnsafeBufferPointer { p in while i + hop <= len { var e: Float = 0; vDSP_measqv(p.baseAddress! + i, 1, &e, vDSP_Length(hop)); out.append(e.squareRoot()); i += hop } }
            return out
        }
        let full = Array(UnsafeBufferPointer(start: ch[0], count: len))
        let envLow = envelope(low), envFull = envelope(full)
        func onsets(_ e: [Float]) -> [Float] { var o = [Float](repeating: 0, count: e.count); for k in 1..<e.count { o[k] = max(0, e[k] - e[k - 1]) }; return o }
        let oL = onsets(envLow), oF = onsets(envFull)
        let fps = sr / Double(hop)
        // se normalizan y se mezclan: el bombo manda
        let mL = max(oL.max() ?? 1, 1e-9), mF = max(oF.max() ?? 1, 1e-9)
        let onset = (0..<oL.count).map { oL[$0] / mL * 0.65 + oF[$0] / mF * 0.35 }
        var scores: [(bpm: Double, score: Double, phase: Int)] = []
        for bpm in stride(from: 95.0, through: 175.0, by: 0.1) {
            let period = 60 / bpm * fps
            var best = 0.0, bestPh = 0
            for ph in 0..<Int(period) {
                var s = 0.0, c = 0.0, t = Double(ph)
                while Int(t) < onset.count { s += Double(onset[Int(t)]); c += 1; t += period }
                let m = s / max(1, c)
                if m > best { best = m; bestPh = ph }
            }
            scores.append((bpm, best, bestPh))
        }
        guard let top = scores.max(by: { $0.score < $1.score }) else { return nil }
        let sorted = scores.map(\.score).sorted()
        let median = sorted[sorted.count / 2]
        let confidence = top.score / max(1e-9, median)
        // refinar: el mejor entre vecinos (+-0.3) por si el maximo cayo en un lado
        let bpm = top.bpm, beat = 60 / bpm, phase = Double(top.phase) / fps
        // candidatos de inicio: golpes de la rejilla al inicio de un compas; se elige el de mas energia en los proximos `clipSeconds`
        let win = Int(clipSeconds * fps)
        guard envFull.count > win + 10 else { return Result(bpm: bpm, phase: phase, start: phase, confidence: confidence, duration: total) }
        var cum = [Float](repeating: 0, count: envFull.count + 1)
        for i in 0..<envFull.count { cum[i + 1] = cum[i] + envFull[i] }
        var bestStart = phase, bestE: Float = -1
        var k = 0
        while true {
            let t = phase + Double(k) * beat * 4            // inicio de compas cada 4 golpes
            let i0 = Int(t * fps)
            if i0 + win >= envFull.count { break }
            if t >= 4 {
                let e = cum[i0 + win] - cum[i0]
                if e > bestE { bestE = e; bestStart = t }
            }
            k += 1
        }
        return Result(bpm: bpm, phase: phase, start: bestStart, confidence: confidence, duration: total)
    }
}
