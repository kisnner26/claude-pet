import AVFoundation
import CoreHaptics
import CoreMotion
import SwiftUI
import UIKit
import VistoCore

/// Todo lo que el iPhone puede hacer sentir y oír: sonidos sintetizados (sin archivos), patrones del motor háptico, voz, destello de la linterna
/// y el giroscopio para inclinar la mascota. Cada cosa se activa o apaga en Ajustes.
@MainActor
final class Feel: ObservableObject {
    static let shared = Feel()

    @Published var sounds: Bool { didSet { save("feel.sounds", sounds) } }
    @Published var haptics: Bool { didSet { save("feel.haptics", haptics) } }
    @Published var voice: Bool { didSet { save("feel.voice", voice) } }
    @Published var torch: Bool { didSet { save("feel.torch", torch) } }
    @Published var tilt: Bool { didSet { save("feel.tilt", tilt); tilt ? startMotion() : stopMotion() } }
    @Published var tiltOffset = CGSize.zero
    /// Destello de pantalla: color y momento, para el borde de luz.
    @Published var flash: (color: Color, at: Date)?

    private func save(_ k: String, _ v: Bool) { UserDefaults.standard.set(v, forKey: k) }
    private static func load(_ k: String, _ d: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? d }

    private var hapticEngine: CHHapticEngine?
    private let audio = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let synth = AVSpeechSynthesizer()
    private let motion = CMMotionManager()
    private var lastTick = Date.distantPast
    private var audioReady = false

    init() {
        sounds = Self.load("feel.sounds", true); haptics = Self.load("feel.haptics", true)
        voice = Self.load("feel.voice", false); torch = Self.load("feel.torch", false); tilt = Self.load("feel.tilt", true)
    }

    // MARK: motor

    private func prepare() {
        if hapticEngine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            hapticEngine = try? CHHapticEngine()
            hapticEngine?.isAutoShutdownEnabled = true
            hapticEngine?.resetHandler = { [weak self] in try? self?.hapticEngine?.start() }
        }
        if !audioReady {
            // .ambient respeta el interruptor de silencio y no corta la música del usuario
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            audio.attach(node); audio.connect(node, to: audio.mainMixerNode, format: format)
            audio.mainMixerNode.outputVolume = 0.7
            try? audio.start(); audioReady = true
        }
        if audioReady, !audio.isRunning { try? audio.start() }
    }

    // MARK: háptica

    private struct Tap { var t: Double; var intensity: Float; var sharp: Float; var dur: Double = 0 }

    private func buzz(_ taps: [Tap]) {
        guard haptics else { return }
        prepare()
        guard let engine = hapticEngine else { fallback(taps); return }
        let events = taps.map { tap -> CHHapticEvent in
            let p = [CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity), CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharp)]
            return tap.dur > 0 ? CHHapticEvent(eventType: .hapticContinuous, parameters: p, relativeTime: tap.t, duration: tap.dur) : CHHapticEvent(eventType: .hapticTransient, parameters: p, relativeTime: tap.t)
        }
        do { try engine.start(); try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: 0) } catch { fallback(taps) }
    }

    private func fallback(_ taps: [Tap]) { UIImpactFeedbackGenerator(style: (taps.first?.intensity ?? 0.5) > 0.6 ? .heavy : .light).impactOccurred() }

    // MARK: sonido

    private enum Wave { case sine, triangle, square }
    private struct Note { var f: Double; var f2: Double? = nil; var t: Double; var d: Double; var g: Float = 0.35; var w: Wave = .sine }

    private func chime(_ notes: [Note]) {
        guard sounds else { return }
        prepare()
        let rate = format.sampleRate
        let total = (notes.map { $0.t + $0.d }.max() ?? 0.1) + 0.05
        let frames = AVAudioFrameCount(total * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let out = buf.floatChannelData?[0] else { return }
        buf.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }
        for n in notes {
            let start = Int(n.t * rate), len = Int(n.d * rate)
            var phase = 0.0
            for i in 0..<len where start + i < Int(frames) {
                let p = Double(i) / Double(len)
                let f = n.f + ((n.f2 ?? n.f) - n.f) * p
                phase += f / rate
                let x = phase - floor(phase)
                let s: Double
                switch n.w { case .sine: s = sin(2 * .pi * x); case .triangle: s = 4 * abs(x - 0.5) - 1; case .square: s = x < 0.5 ? 0.6 : -0.6 }
                let env = min(1, Double(i) / (0.004 * rate)) * exp(-4.5 * p)
                out[start + i] += Float(s * env) * n.g
            }
        }
        node.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    // MARK: voz, linterna, destello

    private func speak(_ text: String) {
        guard voice else { return }
        prepare()
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        u.rate = 0.5; u.volume = 0.9
        synth.stopSpeaking(at: .word)
        synth.speak(u)
    }

    private func pulseTorch(_ times: Int) {
        guard torch, let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        Task {
            for _ in 0..<times {
                try? d.lockForConfiguration(); try? d.setTorchModeOn(level: 0.6); d.unlockForConfiguration()
                try? await Task.sleep(nanoseconds: 110_000_000)
                try? d.lockForConfiguration(); d.torchMode = .off; d.unlockForConfiguration()
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }
    }

    private func glow(_ c: Color) { flash = (c, Date()) }

    // MARK: giroscopio

    func startMotion() {
        guard tilt, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            // gravedad en x/y: inclinar a los lados o hacia ti mueve la mascota, suavizado para que no tiemble
            let target = CGSize(width: max(-1, min(1, g.x * 2.2)), height: max(-1, min(1, (g.y + 0.6) * 2.2)))
            self.tiltOffset = CGSize(width: self.tiltOffset.width * 0.85 + target.width * 0.15, height: self.tiltOffset.height * 0.85 + target.height * 0.15)
        }
    }

    func stopMotion() { motion.stopDeviceMotionUpdates(); tiltOffset = .zero }

    // MARK: eventos

    func ask(tool: String, project: String, risky: Bool) {
        buzz([Tap(t: 0, intensity: 0.7, sharp: 0.6), Tap(t: 0.14, intensity: 1, sharp: 0.9)] + (risky ? [Tap(t: 0.3, intensity: 1, sharp: 1), Tap(t: 0.42, intensity: 1, sharp: 1)] : []))
        chime(risky ? [Note(f: 659, t: 0, d: 0.16, w: .triangle), Note(f: 622, t: 0.15, d: 0.16, w: .triangle), Note(f: 659, t: 0.3, d: 0.3, w: .triangle)]
                    : [Note(f: 659, t: 0, d: 0.14, w: .triangle), Note(f: 880, t: 0.12, d: 0.34, w: .triangle)])
        speak(L.t("Claude pide permiso para \(tool) en \(project)", "Claude asks permission for \(tool) in \(project)"))
        pulseTorch(risky ? 3 : 2)
        glow(VT.amber)
    }

    func question(project: String) {
        buzz([Tap(t: 0, intensity: 0.5, sharp: 0.4), Tap(t: 0.1, intensity: 0.7, sharp: 0.5), Tap(t: 0.2, intensity: 0.9, sharp: 0.7)])
        chime([Note(f: 523, t: 0, d: 0.12), Note(f: 659, t: 0.1, d: 0.12), Note(f: 784, t: 0.2, d: 0.3)])
        speak(L.t("Claude te hace una pregunta en \(project)", "Claude has a question in \(project)"))
        glow(VT.codex)
    }

    func done(agent: String, project: String) {
        buzz([Tap(t: 0, intensity: 0.4, sharp: 0.3, dur: 0.25), Tap(t: 0.28, intensity: 1, sharp: 0.8), Tap(t: 0.4, intensity: 0.8, sharp: 0.7), Tap(t: 0.52, intensity: 0.6, sharp: 0.6)])
        chime([Note(f: 523, t: 0, d: 0.5, g: 0.28), Note(f: 659, t: 0.09, d: 0.5, g: 0.28), Note(f: 784, t: 0.18, d: 0.5, g: 0.28), Note(f: 1047, t: 0.27, d: 0.7, g: 0.3)])
        speak(L.t("\(VTFormat.agentName(agent)) terminó en \(project)", "\(VTFormat.agentName(agent)) finished in \(project)"))
        glow(VT.green)
    }

    func failed(agent: String, project: String) {
        buzz([Tap(t: 0, intensity: 1, sharp: 0.2, dur: 0.35), Tap(t: 0.4, intensity: 1, sharp: 1), Tap(t: 0.5, intensity: 1, sharp: 1)])
        chime([Note(f: 220, f2: 110, t: 0, d: 0.45, g: 0.3, w: .square), Note(f: 165, f2: 82, t: 0.18, d: 0.5, g: 0.25, w: .square)])
        speak(L.t("\(VTFormat.agentName(agent)) falló en \(project)", "\(VTFormat.agentName(agent)) failed in \(project)"))
        pulseTorch(3)
        glow(VT.red)
    }

    func allowed() { buzz([Tap(t: 0, intensity: 0.6, sharp: 1), Tap(t: 0.07, intensity: 0.9, sharp: 1)]); chime([Note(f: 784, f2: 1568, t: 0, d: 0.12, g: 0.3)]); glow(VT.blue) }
    func denied() { buzz([Tap(t: 0, intensity: 1, sharp: 0.1, dur: 0.12)]); chime([Note(f: 140, f2: 60, t: 0, d: 0.22, g: 0.5)]); glow(VT.red) }
    // la realidad aumentada: tocar, acariciar y jugar con la mascota
    func boop() { buzz([Tap(t: 0, intensity: 0.5, sharp: 0.9)]); chime([Note(f: 520, f2: 780, t: 0, d: 0.09, g: 0.25)]) }
    func purr() { buzz([Tap(t: 0, intensity: 0.22, sharp: 0.1, dur: 0.3)]) }
    func cuddle() { buzz([Tap(t: 0, intensity: 0.35, sharp: 0.2, dur: 0.2), Tap(t: 0.22, intensity: 0.5, sharp: 0.5)]); chime([Note(f: 880, f2: 1320, t: 0, d: 0.14, g: 0.18), Note(f: 1175, t: 0.13, d: 0.2, g: 0.16)]) }
    func cheer() { buzz([Tap(t: 0, intensity: 0.5, sharp: 0.6), Tap(t: 0.1, intensity: 0.7, sharp: 0.8), Tap(t: 0.2, intensity: 0.9, sharp: 1)]); chime([Note(f: 523, t: 0, d: 0.12), Note(f: 659, t: 0.1, d: 0.12), Note(f: 784, t: 0.2, d: 0.12), Note(f: 1047, t: 0.3, d: 0.3)]) }
    func threshold() { buzz([Tap(t: 0, intensity: 0.55, sharp: 0.7)]) }

    /// Mientras un agente ejecuta herramientas, cada paso se nota: un tic casi imperceptible.
    func tick() {
        guard Date().timeIntervalSince(lastTick) > 0.7 else { return }
        lastTick = Date()
        buzz([Tap(t: 0, intensity: 0.22, sharp: 0.9)])
        chime([Note(f: 1900, f2: 1500, t: 0, d: 0.018, g: 0.10)])
    }

    func thinking() { buzz([Tap(t: 0, intensity: 0.3, sharp: 0.2, dur: 0.18)]); chime([Note(f: 392, f2: 466, t: 0, d: 0.16, g: 0.16)]) }
}

/// Borde de luz que recorre la pantalla: ámbar mientras algo espera tu respuesta y un destello breve al terminar, fallar o decidir.
struct EdgeGlow: View {
    let pending: Bool
    @ObservedObject var feel: Feel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let flash = feel.flash.map { max(0, 1 - ctx.date.timeIntervalSince($0.at) / 1.3) } ?? 0
            let color = flash > 0 ? (feel.flash?.color ?? VT.amber) : VT.amber
            let level = max(flash, pending ? 0.35 + 0.25 * (sin(t * 4) + 1) / 2 : 0)
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .strokeBorder(AngularGradient(colors: [color, color.opacity(0.1), color, color.opacity(0.1), color], center: .center, angle: .degrees(t * 90)), lineWidth: 5 + 9 * flash)
                .blur(radius: 9).opacity(level).ignoresSafeArea().allowsHitTesting(false)
        }
    }
}
