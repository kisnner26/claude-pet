import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Convierte lo que entrega la captura (planar o entrelazado, uno o varios canales) en un solo canal.
enum AudioMixdown {
    static func mono(interleaved: [Float], channels: Int) -> [Float] {
        guard channels > 0 else { return [] }
        if channels == 1 { return interleaved }
        let frames = interleaved.count / channels
        var out = [Float](repeating: 0, count: frames)
        for i in 0..<frames { var s: Float = 0; for c in 0..<channels { s += interleaved[i * channels + c] }; out[i] = s / Float(channels) }
        return out
    }

    static func mono(planar: [[Float]]) -> [Float] {
        guard let first = planar.first else { return [] }
        let n = planar.map(\.count).min() ?? first.count
        guard planar.count > 1 else { return Array(first.prefix(n)) }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { var s: Float = 0; for ch in planar { s += ch[i] }; out[i] = s / Float(planar.count) }
        return out
    }
}

/// Ultimos resultados del analizador, accesibles desde cualquier hilo: la captura escribe y la interfaz lee 60 veces por segundo.
final class AudioFeatureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var analyzer: AudioAnalyzer?
    private var rate = 0.0
    private var frame = AudioFrame()
    private var lastBeatAt: TimeInterval?
    private var lastFrameAt: TimeInterval = -100

    func feed(_ samples: [Float], rate sampleRate: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if analyzer == nil || rate != sampleRate { analyzer = AudioAnalyzer(sampleRate: sampleRate); rate = sampleRate }
        for f in analyzer!.process(samples) { frame = f; if f.beat { lastBeatAt = now } }
        lastFrameAt = now
    }

    func reset() { lock.lock(); analyzer = nil; frame = AudioFrame(); lastBeatAt = nil; lastFrameAt = -100; lock.unlock() }

    /// Rellena un pulso con lo que se oye; `listening` solo si la captura esta entregando audio ahora mismo.
    func fill(_ m: MusicPulse, now: TimeInterval) -> MusicPulse {
        lock.lock(); defer { lock.unlock() }
        guard now - lastFrameAt < 0.6 else { return m }
        var out = m
        out.listening = true
        out.level = frame.level; out.bass = frame.bass; out.mid = frame.mid; out.treble = frame.treble
        out.beatCount = frame.beatCount; out.bpm = frame.bpm
        out.beatAge = lastBeatAt.map { now - $0 }
        return out
    }
}

/// Oye el audio del Mac (solo mientras suena algo y el usuario lo ha activado) para que la mascota siga el ritmo de verdad.
/// macOS lo pide como "grabacion de pantalla y audio del sistema". Del audio solo se calculan unos numeros: no se guarda ni sale del Mac.
@MainActor
final class AudioReactor: ObservableObject {
    static let shared = AudioReactor()
    enum Status: Equatable { case off, starting, listening, needsPermission, failed(String) }

    @Published private(set) var status: Status = .off
    let box = AudioFeatureBox()
    private var stream: SCStream?
    private let output: AudioStreamOutput
    private let queue = DispatchQueue(label: "claudepet.audio", qos: .userInitiated)
    private var wanted = false
    private var starting = false

    private init() {
        output = AudioStreamOutput(box: box)
        output.onStop = { [weak self] message in Task { @MainActor in self?.stream = nil; self?.starting = false; self?.status = .failed(message); self?.box.reset() } }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    /// Muestra el aviso del sistema (solo la primera vez). Hay que llamarlo desde una accion del usuario.
    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    /// Enciende o apaga la escucha. Es idempotente: se llama cada vez que cambia algo (ajuste, reproduccion).
    func setActive(_ on: Bool) {
        wanted = on
        if on { start() } else { stop() }
    }

    private func start() {
        guard stream == nil, !starting else { return }
        guard Self.hasPermission else { status = .needsPermission; return }
        starting = true; status = .starting
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else { throw NSError(domain: "claudepet", code: 1, userInfo: [NSLocalizedDescriptionKey: "no hay pantalla"]) }
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true; cfg.excludesCurrentProcessAudio = true
                cfg.sampleRate = 48_000; cfg.channelCount = 2
                cfg.width = 2; cfg.height = 2; cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)     // el video no se usa
                let s = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []), configuration: cfg, delegate: self.output)
                try s.addStreamOutput(self.output, type: .audio, sampleHandlerQueue: self.queue)
                try s.addStreamOutput(self.output, type: .screen, sampleHandlerQueue: self.queue)
                try await s.startCapture()
                await MainActor.run {
                    self.starting = false
                    if self.wanted { self.stream = s; self.status = .listening } else { Task { try? await s.stopCapture() } }
                }
            } catch {
                await MainActor.run { self.starting = false; self.status = Self.hasPermission ? .failed(error.localizedDescription) : .needsPermission }
            }
        }
    }

    private func stop() {
        let s = stream; stream = nil
        if status != .needsPermission { status = .off }
        box.reset()
        if let s { Task { try? await s.stopCapture() } }
    }
}

/// Recibe el audio de la captura en su propia cola y lo pasa al analizador.
final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let box: AudioFeatureBox
    var onStop: ((String) -> Void)?
    init(box: AudioFeatureBox) { self.box = box }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let (samples, rate) = Self.mono(from: sampleBuffer) else { return }
        box.feed(samples, rate: rate)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop?(error.localizedDescription) }

    /// PCM float32, planar o entrelazado, a un solo canal.
    static func mono(from sb: CMSampleBuffer) -> ([Float], Double)? {
        guard let fmt = CMSampleBufferGetFormatDescription(sb), let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mBitsPerChannel == 32, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }
        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr, needed > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                                                                      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &block) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var planar: [[Float]] = []
        for b in buffers {
            guard let data = b.mData, b.mDataByteSize > 0 else { continue }
            let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let floats = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
            if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 { planar.append(floats) }
            else { return (AudioMixdown.mono(interleaved: floats, channels: max(1, Int(b.mNumberChannels))), asbd.mSampleRate) }
        }
        let mono = AudioMixdown.mono(planar: planar)
        return mono.isEmpty ? nil : (mono, asbd.mSampleRate)
    }
}
