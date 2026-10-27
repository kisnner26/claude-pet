import Foundation
import AVFoundation

/// Reemplazos de sonido del usuario en ~/.claude-pet/sounds/<sonido>.(wav|aiff|caf|m4a), con validacion.
enum SoundOverrides {
    static let maxBytes = 1_048_576
    static let maxSeconds = 3.0
    static var directory: String { ProcessInfo.processInfo.environment["CLAUDE_PET_SOUNDS"] ?? (NSHomeDirectory() + "/.claude-pet/sounds") }

    /// Un archivo valido de reemplazo para el sonido, o nil si no existe o no pasa las comprobaciones.
    static func file(for cue: SoundCue) -> URL? {
        for ext in ["wav", "aiff", "caf", "m4a"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(cue.rawValue).\(ext)")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.size] as? Int ?? .max) <= maxBytes, let file = try? AVAudioFile(forReading: url),
                  file.processingFormat.sampleRate > 0, Double(file.length) / file.processingFormat.sampleRate <= maxSeconds else { continue }
            return url
        }
        return nil
    }
}

/// Reproduce los sonidos. Limita un sonido por categoria cada 150 ms y sube el tono de las alertas repetidas.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    static let minimumGap: TimeInterval = 0.15

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var lastPlayed: [SoundCue.Category: TimeInterval] = [:]
    private var repeats: [SoundCue: (count: Int, at: TimeInterval)] = [:]
    var enabled = true
    var volume: Float = 0.5
    var categoryVolume: [SoundCue.Category: Float] = [:]

    /// Decide si un sonido suena ahora y con cuanta subida de tono. Pura respecto al reloj que recibe.
    func plan(_ cue: SoundCue, now: TimeInterval) -> Int? {
        guard enabled, volume > 0, (categoryVolume[cue.category] ?? 1) > 0 else { return nil }
        if let last = lastPlayed[cue.category], now - last < Self.minimumGap { return nil }
        lastPlayed[cue.category] = now
        guard cue.category == .alert else { return 0 }
        let prior = repeats[cue].flatMap { now - $0.at < 30 ? $0.count : nil } ?? 0
        repeats[cue] = (prior + 1, now)
        return SoundBank.escalation(previousCount: prior)
    }

    func play(_ cue: SoundCue) {
        guard let semitones = plan(cue, now: ProcessInfo.processInfo.systemUptime) else { return }
        let gain = volume * (categoryVolume[cue.category] ?? 1)
        if let url = SoundOverrides.file(for: cue) { playFile(url, gain: gain); return }
        let data = SoundBank.samples(for: cue, semitones: semitones)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundBank.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(data.count)
        data.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: data.count) }
        schedule(buffer, format: format, gain: gain)
    }

    private func playFile(_ url: URL, gain: Float) {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return }
        schedule(buffer, format: file.processingFormat, gain: gain)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, gain: Float) {
        if engine == nil {
            let e = AVAudioEngine(), p = AVAudioPlayerNode()
            e.attach(p); e.connect(p, to: e.mainMixerNode, format: format)
            guard (try? e.start()) != nil else { return }
            engine = e; player = p
        }
        guard let engine, let player else { return }
        if !engine.isRunning { guard (try? engine.start()) != nil else { return } }
        player.volume = max(0, min(1, gain))
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
