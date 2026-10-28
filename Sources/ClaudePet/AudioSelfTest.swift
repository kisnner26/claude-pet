import Foundation

enum AudioSelfTest {
    /// Tren de clics de bombo a `bpm`: ráfagas de 60 Hz que decaen, sobre un poco de ruido de fondo.
    static func kicks(bpm: Double, seconds: Double, rate: Double, noise: Float = 0.002) -> [Float] {
        let n = Int(seconds * rate), period = 60 / bpm
        var out = [Float](repeating: 0, count: n)
        var seed: UInt32 = 12345
        for i in 0..<n {
            let t = Double(i) / rate
            let since = t.truncatingRemainder(dividingBy: period)
            var v = 0.0
            if since < 0.12 { v = 0.8 * exp(-since / 0.03) * sin(2 * .pi * 60 * since) }
            seed = seed &* 1664525 &+ 1013904223
            out[i] = Float(v) + noise * (Float(seed >> 9) / Float(1 << 23) - 0.5)
        }
        return out
    }

    static func run() -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func analyze(_ samples: [Float], rate: Double) -> [AudioFrame] {
            var a = AudioAnalyzer(sampleRate: rate); var out: [AudioFrame] = []
            var i = 0; while i < samples.count { let j = min(samples.count, i + 1_000); out += a.process(Array(samples[i..<j])); i = j }   // en trozos, como llega de la captura
            return out
        }

        for (bpm, rate) in [(120.0, 48_000.0), (90.0, 48_000.0), (150.0, 44_100.0), (100.0, 48_000.0)] {
            let frames = analyze(kicks(bpm: bpm, seconds: 12, rate: rate), rate: rate)
            let beats = frames.filter(\.beat).count, expected = Int(12 * bpm / 60)
            check("beats \(Int(bpm)) bpm @\(Int(rate))", abs(beats - expected) <= 2)
            let est = frames.last?.bpm
            check("bpm \(Int(bpm)) estimado", est.map { abs($0 - bpm) < 6 } ?? false)
            check("bass domina en un bombo \(Int(bpm))", (frames.map(\.bass).max() ?? 0) > 0.9 && frames.dropFirst(200).map(\.treble).max().map { $0 < 0.6 } ?? false)
        }

        // una mezcla mas realista: bombo a 124, hi-hat al doble, caja en los tiempos 2 y 4, y un colchon armonico constante
        func mix(bpm: Double, seconds: Double, rate: Double) -> [Float] {
            let kick = kicks(bpm: bpm, seconds: seconds, rate: rate, noise: 0)
            var out = kick, seed: UInt32 = 99
            let beat = 60 / bpm
            for i in 0..<out.count {
                let t = Double(i) / rate
                seed = seed &* 1664525 &+ 1013904223
                let white = Double(Float(seed >> 9) / Float(1 << 23) - 0.5)
                let hatPhase = t.truncatingRemainder(dividingBy: beat / 2)
                let hat = hatPhase < 0.03 ? white * 0.25 * exp(-hatPhase / 0.01) : 0
                let barPhase = t.truncatingRemainder(dividingBy: beat * 2)
                let snare = (barPhase >= beat && barPhase < beat + 0.12) ? white * 0.5 * exp(-(barPhase - beat) / 0.05) : 0
                let pad = 0.12 * (sin(2 * .pi * 196 * t) + sin(2 * .pi * 247 * t) + sin(2 * .pi * 294 * t)) / 3
                out[i] += Float(hat + snare + pad)
            }
            return out
        }
        let busy = analyze(mix(bpm: 124, seconds: 14, rate: 48_000), rate: 48_000)
        let busyBeats = busy.filter(\.beat).count
        check("mezcla realista: pulsos en el orden de los tiempos (no uno por nota)", busyBeats >= 20 && busyBeats <= 48)
        check("mezcla realista: tempo cerca de 124 (o su doble/mitad plegado)", busy.last?.bpm.map { abs($0 - 124) < 10 || abs($0 - 62) < 6 || abs($0 - 248) < 12 } ?? false)

        let silence = analyze([Float](repeating: 0, count: 48_000 * 3), rate: 48_000)
        check("silencio: sin pulsos ni nivel", silence.allSatisfy { !$0.beat && $0.level == 0 && $0.bass == 0 } && silence.last?.bpm == nil)
        let tone = analyze((0..<(48_000 * 5)).map { Float(0.4 * sin(2 * .pi * 440 * Double($0) / 48_000)) }, rate: 48_000)
        check("tono constante: casi sin pulsos y con nivel", tone.filter(\.beat).count <= 2 && (tone.last?.level ?? 0) > 0.5)
        var seed: UInt32 = 7
        let noise = analyze((0..<(48_000 * 6)).map { _ in seed = seed &* 1664525 &+ 1013904223; return Float(seed >> 9) / Float(1 << 23) - 0.5 }, rate: 48_000)
        check("ruido estacionario: casi sin pulsos", noise.filter(\.beat).count <= 6)
        check("todo acotado 0...1", (silence + tone + noise).allSatisfy { (0...1).contains($0.level) && (0...1).contains($0.bass) && (0...1).contains($0.mid) && (0...1).contains($0.treble) })
        let hostile = analyze([Float.nan, .infinity, -.infinity, 1e30, -1e30] + [Float](repeating: 0.1, count: 2_000), rate: 48_000)
        check("muestras hostiles no rompen nada", hostile.allSatisfy { $0.level.isFinite && $0.bass.isFinite && (0...1).contains($0.level) })
        let tinyRate = analyze(kicks(bpm: 120, seconds: 2, rate: 8_000), rate: 8_000)
        check("tasa de muestreo baja funciona", !tinyRate.isEmpty)
        // pulsos refractarios: nunca mas rapido de lo razonable
        let fast = analyze(kicks(bpm: 400, seconds: 6, rate: 48_000), rate: 48_000)
        check("limite de pulsos por segundo", fast.filter(\.beat).count <= Int(6 / AudioAnalyzer.refractory) + 1)
        // pausa larga: el tempo se olvida
        let gap = kicks(bpm: 120, seconds: 6, rate: 48_000) + [Float](repeating: 0, count: 48_000 * 3)
        check("tras silencio el tempo desaparece", analyze(gap, rate: 48_000).last?.bpm == nil)

        // baile
        var calm = PetPose()
        MusicDance.apply(&calm, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 1, mid: 0.5, treble: 0.2, beatAge: 0, beatCount: 2, bpm: 120, volume: 0.5))
        var later = PetPose()
        MusicDance.apply(&later, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 1, mid: 0.5, treble: 0.2, beatAge: 0.3, beatCount: 2, bpm: 120, volume: 0.5))
        check("el salto es maximo en el pulso y cae despues", calm.dy < later.dy && calm.dy < -1.5 && later.dy > -0.3)
        check("el cabeceo alterna segun el pulso", { var a = PetPose(), b = PetPose()
            MusicDance.apply(&a, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 1, beatAge: 0, beatCount: 2)); MusicDance.apply(&b, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 1, beatAge: 0, beatCount: 3))
            return a.rotation > 3 && b.rotation < -3 }())
        check("graves fuertes saltan mas que graves flojos", { var a = PetPose(), b = PetPose()
            MusicDance.apply(&a, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 1, beatAge: 0)); MusicDance.apply(&b, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.8, bass: 0.1, beatAge: 0))
            return a.dy < b.dy }())
        check("ojos contentos solo si suena fuerte", calm.happy && { var q = PetPose(); MusicDance.apply(&q, t: 0, music: MusicPulse(playing: true, listening: true, level: 0.2, bass: 0.5, beatAge: 0)); return !q.happy }())
        var legacyLoud = PetPose(), legacyQuiet = PetPose()
        MusicDance.apply(&legacyLoud, t: 0.125, music: MusicPulse(playing: true, volume: 1)); MusicDance.apply(&legacyQuiet, t: 0.125, music: MusicPulse(playing: true, volume: 0.1))
        check("sin audio el baile sigue al volumen", abs(legacyLoud.rotation) > abs(legacyQuiet.rotation) && legacyLoud.dancing)
        check("envolvente: 1 en el pulso, 0 fuera", MusicDance.envelope(beatAge: 0) == 1 && MusicDance.envelope(beatAge: MusicDance.beatLength) == 0 && MusicDance.envelope(beatAge: -1) == 0 && MusicDance.envelope(beatAge: 5) == 0)
        var start = PetPose(), paused = PetPose(), none = PetPose()
        MusicDance.transients(&start, music: MusicPulse(startedAge: 0.45)); MusicDance.transients(&paused, music: MusicPulse(pausedAge: 0.8)); MusicDance.transients(&none, music: MusicPulse(startedAge: 5, pausedAge: 9))
        check("salta al empezar y suspira al pausar", start.dy < -1.5 && paused.scaleY < 1 && paused.blink && none == PetPose())

        // efectos
        check("sin audio no hay ecualizador", MusicFx.beat(pulse: MusicPulse(playing: true)).isEmpty)
        let eq = MusicFx.beat(pulse: MusicPulse(playing: true, listening: true, level: 1, bass: 1, mid: 0.5, treble: 0.1, beatAge: 0.05))
        check("ecualizador y aro con audio", eq.count > 15 && eq.allSatisfy { $0.x > 0 && $0.x < 1 && $0.alpha >= 0 && $0.alpha <= 1 })
        let barsOnly = MusicFx.beat(pulse: MusicPulse(playing: true, listening: true, level: 1, bass: 1, mid: 0.5, treble: 0.1, beatAge: 5))
        check("el aro solo dura un pulso", eq.count > barsOnly.count && !barsOnly.isEmpty)

        // mezclador a mono
        check("mono entrelazado", AudioMixdown.mono(interleaved: [1, 3, 2, 4, 0, 2], channels: 2) == [2, 3, 1] && AudioMixdown.mono(interleaved: [1, 2, 3], channels: 1) == [1, 2, 3])
        check("mono planar", AudioMixdown.mono(planar: [[1, 2, 3], [3, 4, 5]]) == [2, 3, 4] && AudioMixdown.mono(planar: [[1, 2, 3]]) == [1, 2, 3] && AudioMixdown.mono(planar: []).isEmpty)
        check("mono planar con canales de distinta longitud", AudioMixdown.mono(planar: [[1, 2, 3], [3, 4]]).count == 2)
        check("mono con 0 canales", AudioMixdown.mono(interleaved: [1, 2], channels: 0).isEmpty)

        // caja de resultados: solo hay escucha mientras llega audio
        let box = AudioFeatureBox()
        let base = MusicPulse(playing: true, volume: 0.7)
        check("sin audio no hay escucha", box.fill(base, now: 100) == base)
        let clip = kicks(bpm: 120, seconds: 3, rate: 48_000)
        var i = 0; while i < clip.count { box.feed(Array(clip[i..<min(clip.count, i + 960)]), rate: 48_000, now: 100 + Double(i) / 48_000); i += 960 }
        let live = box.fill(base, now: 103)
        check("con audio hay escucha, pulsos y volumen de la app", live.listening && live.beatCount >= 4 && live.beatAge != nil && live.volume == 0.7 && live.playing)
        check("el audio caduca: si deja de llegar, vuelve a las apps", box.fill(base, now: 104) == base)
        box.feed(clip, rate: 44_100, now: 200)
        check("cambio de tasa de muestreo reinicia el analizador", box.fill(base, now: 200.1).listening)
        box.reset()
        check("reset apaga la escucha", box.fill(base, now: 200.2) == base)
        box.feed([], rate: 48_000, now: 300); box.feed([1, 2, 3], rate: 0, now: 300)
        check("entradas vacias o con tasa 0 se ignoran", box.fill(base, now: 300.1) == base)

        print(failures == 0 ? "AUDIO OK" : "AUDIO \(failures) FALLOS")
        return failures == 0
    }
}
