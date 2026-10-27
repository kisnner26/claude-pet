import Foundation
import AVFoundation

/// `ClaudePet --selftest-sound`: el banco de sonidos (escala, duraciones, direccion, limites) sin abrir el audio.
enum SoundSelfTest {
    @MainActor static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        check("hay un sonido por cada uso previsto", SoundCue.allCases.count == 13)
        for cue in SoundCue.allCases {
            let limit = cue == .done ? SoundCue.doneMaxDuration : SoundCue.maxDuration
            check("\(cue.rawValue): dura \(Int(cue.duration * 1000)) ms, dentro del limite", cue.duration <= limit && cue.duration > 0.015)
            check("\(cue.rawValue): sus notas tonales estan en la escala", cue.notes.filter { $0.voice != .tick }.allSatisfy { n in SoundCue.scale.contains { abs($0 - n.frequency) < 0.01 } })
            let s = SoundBank.samples(for: cue)
            check("\(cue.rawValue): sin saturar ni NaN", !s.isEmpty && s.allSatisfy { $0.isFinite && abs($0) <= 0.95 } && (s.map { abs($0) }.max() ?? 0) > 0.05)
            let peak = s.map { abs($0) }.max() ?? 0
            check("\(cue.rawValue): el nivel de pico es el de su categoria", abs(peak - cue.targetPeak) < 0.06)
            check("\(cue.rawValue): empieza y termina en silencio, sin clics", abs(s.first ?? 1) < 0.05 && abs(s.last ?? 1) < 0.01)
            check("\(cue.rawValue): la cola no pasa de \(Int(SoundCue.maxTail * 1000)) ms", Double(s.count) / SoundBank.sampleRate <= cue.duration + SoundCue.maxTail + 0.001)
            check("\(cue.rawValue): es determinista", s == SoundBank.samples(for: cue))
        }
        func rising(_ cue: SoundCue) -> Bool { let f = cue.notes.map(\.frequency); return zip(f, f.dropFirst()).allSatisfy { $0 < $1 } }
        func falling(_ cue: SoundCue) -> Bool { let f = cue.notes.map(\.frequency); return zip(f, f.dropFirst()).allSatisfy { $0 > $1 } }
        check("los sonidos de exito suben", rising(.allowed) && rising(.done) && rising(.open))
        check("los de error y negativa bajan", falling(.denied) && falling(.error) && falling(.fold))
        check("la subida de tono cambia las muestras pero no la duracion", SoundBank.samples(for: .permission, semitones: 3) != SoundBank.samples(for: .permission) && SoundBank.samples(for: .permission, semitones: 3).count == SoundBank.samples(for: .permission).count)
        check("la escalada se acota a 4 semitonos", SoundBank.escalation(previousCount: 99) == 4 && SoundBank.escalation(previousCount: -2) == 0)
        func rms(_ s: [Float]) -> Float { sqrt(s.reduce(0) { $0 + $1 * $1 } / Float(max(1, s.count))) }
        check("las alertas suenan mas fuerte que la interfaz", rms(SoundBank.samples(for: .permission)) > rms(SoundBank.samples(for: .open)) && rms(SoundBank.samples(for: .error)) > rms(SoundBank.samples(for: .hover)))
        check("el clic es corto y seco: casi toda su energia esta en los primeros 40 ms", { let s = SoundBank.samples(for: .click); let head = s.prefix(1764).reduce(0) { $0 + $1 * $1 }; let all = s.reduce(0) { $0 + $1 * $1 }; return head / max(1e-9, all) > 0.95 }())
        check("la campana tiene mas brillo que el golpe grave", { func zc(_ s: [Float]) -> Int { zip(s, s.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count }; return Double(zc(SoundBank.samples(for: .done))) / Double(SoundBank.samples(for: .done).count) > Double(zc(SoundBank.samples(for: .error))) / Double(SoundBank.samples(for: .error).count) }())
        check("el wav exportado tiene cabecera y el tamaño esperado", { let w = SoundBank.wav(SoundBank.samples(for: .done)); return w.prefix(4) == Data("RIFF".utf8) && w.count == 44 + SoundBank.samples(for: .done).count * 2 }())
        check("hay tres categorias", Set(SoundCue.allCases.map(\.category)).count == 3)

        // limites de repeticion y volumen
        let e = SoundEngine()
        check("un sonido por categoria cada 150 ms", e.plan(.click, now: 100) != nil && e.plan(.hover, now: 100.05) == nil && e.plan(.click, now: 100.2) != nil)
        check("categorias distintas no se bloquean entre si", e.plan(.done, now: 100.21) != nil)
        check("las alertas repetidas suben de tono", e.plan(.permission, now: 200) == 0 && e.plan(.permission, now: 201) == 1 && e.plan(.permission, now: 202) == 2)
        check("tras 30 s la escalada se reinicia", e.plan(.permission, now: 260) == 0)
        e.enabled = false
        check("en silencio no suena nada", e.plan(.error, now: 400) == nil)
        e.enabled = true; e.volume = 0
        check("con volumen cero no suena nada", e.plan(.error, now: 401) == nil)
        e.volume = 0.5; e.categoryVolume[.alert] = 0
        check("una categoria se silencia por separado", e.plan(.error, now: 402) == nil && e.plan(.click, now: 402) != nil)

        // reemplazo del usuario con validacion
        let dir = NSTemporaryDirectory() + "claudepet-sounds-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("CLAUDE_PET_SOUNDS", dir, 1)
        defer { try? FileManager.default.removeItem(atPath: dir); unsetenv("CLAUDE_PET_SOUNDS") }
        check("sin archivos no hay reemplazo", SoundOverrides.file(for: .click) == nil)
        func writeWav(_ name: String, seconds: Double) {
            let n = Int(seconds * 22_050)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true),
                  let file = try? AVAudioFile(forWriting: URL(fileURLWithPath: dir + "/" + name), settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true),
                  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return }
            buf.frameLength = AVAudioFrameCount(n)
            for i in 0..<n { buf.int16ChannelData![0][i] = Int16(sin(Double(i) * 0.1) * 8000) }
            try? file.write(from: buf)
        }
        writeWav("click.wav", seconds: 0.2)
        check("un wav valido reemplaza al sintetizado", SoundOverrides.file(for: .click) != nil)
        writeWav("open.wav", seconds: 5)
        check("un audio de mas de 3 s se rechaza", SoundOverrides.file(for: .open) == nil)
        try? Data(repeating: 1, count: 2_000_000).write(to: URL(fileURLWithPath: dir + "/fold.wav"))
        check("un archivo de mas de 1 MB se rechaza", SoundOverrides.file(for: .fold) == nil)
        try? Data("no es audio".utf8).write(to: URL(fileURLWithPath: dir + "/done.wav"))
        check("un archivo corrupto se rechaza", SoundOverrides.file(for: .done) == nil)
        try? FileManager.default.createSymbolicLink(atPath: dir + "/peek.wav", withDestinationPath: dir + "/click.wav")
        check("un enlace simbolico no se sigue", SoundOverrides.file(for: .peek) == nil)

        print(failures == 0 ? "SONIDO OK" : "SONIDO FALLOS: \(failures)")
        return failures == 0
    }
}
