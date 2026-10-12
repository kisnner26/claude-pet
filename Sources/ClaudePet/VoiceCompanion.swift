import AVFoundation
import Speech
import AppKit

enum VoiceCommand: Equatable {
    case showPets, hidePets, dashboard, refreshGit, openDiff, football, showBubble, hideBubble, status

    static func parse(_ transcript: String) -> VoiceCommand? {
        let text = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        if text.contains("muestra") && text.contains("mascota") { return .showPets }
        if text.contains("oculta") && text.contains("mascota") { return .hidePets }
        if text.contains("tablero") || text.contains("mission control") { return .dashboard }
        if text.contains("actualiza") && text.contains("git") { return .refreshGit }
        if text.contains("abre") && text.contains("diff") { return .openDiff }
        if text.contains("futbol") || text.contains("fútbol") { return .football }
        if text.contains("muestra") && text.contains("burbuja") { return .showBubble }
        if text.contains("oculta") && text.contains("burbuja") { return .hideBubble }
        if text.contains("estado") { return .status }
        return nil
    }
}

@MainActor
final class VoiceCompanion: NSObject, ObservableObject {
    enum Status: Equatable { case idle, listening, unavailable(String) }

    @Published private(set) var status: Status = .idle
    @Published private(set) var transcript = ""
    var onCommand: ((VoiceCommand) -> Void)?

    private let engine = AVAudioEngine()
    private let speaker = NSSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { status == .listening ? stop() : start() }

    func start() {
        guard recognizer?.isAvailable == true else { status = .unavailable("reconocimiento no disponible"); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            Task { @MainActor in
                guard authorization == .authorized else { self?.status = .unavailable("permiso de voz denegado"); return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Task { @MainActor in
                        guard allowed else { self?.status = .unavailable("permiso de micrófono denegado"); return }
                        self?.beginRecognition()
                    }
                }
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        status = .idle
    }

    private func beginRecognition() {
        stop()
        guard let recognizer else { status = .unavailable("reconocimiento no disponible"); return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in self?.request?.append(buffer) }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal, let command = VoiceCommand.parse(self.transcript) {
                        self.onCommand?(command)
                        self.speakConfirmation(for: command)
                        self.stop()
                    }
                }
                if error != nil { self.stop() }
            }
        }
        do { engine.prepare(); try engine.start(); status = .listening }
        catch { stop(); status = .unavailable("no se pudo iniciar el micrófono") }
    }

    private func speakConfirmation(for command: VoiceCommand) {
        let text: String = switch command {
        case .showPets: "mascotas visibles"
        case .hidePets: "mascotas ocultas"
        case .dashboard: "abriendo tablero"
        case .refreshGit: "actualizando git"
        case .openDiff: "abriendo diff"
        case .football: "partido iniciado"
        case .showBubble: "burbuja visible"
        case .hideBubble: "burbuja oculta"
        case .status: "claude está \(PetStore.shared.state.label.lowercased())"
        }
        speaker.startSpeaking(text)
    }
}
