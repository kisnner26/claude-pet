import AppKit

/// Detecta si las apps de escritorio de Claude y de Codex estan abiertas (sin leer nada de ellas).
/// Se actualiza con las notificaciones de lanzar/cerrar de NSWorkspace y un repaso cada 10 s.
@MainActor
final class AppPresence {
    static let claudeBundle = "com.anthropic.claudefordesktop"
    static let codexBundle = "com.openai.codex"

    private let onChange: (_ claude: Bool, _ codex: Bool) -> Void
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?

    init(onChange: @escaping (_ claude: Bool, _ codex: Bool) -> Void) { self.onChange = onChange }

    func start() {
        scan()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scan() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        // Solo para pruebas manuales: CLAUDE_PET_FAKE_APPS = claude | codex | both | none simula las apps abiertas.
        if let fake = ProcessInfo.processInfo.environment["CLAUDE_PET_FAKE_APPS"] {
            onChange(fake == "claude" || fake == "both", fake == "codex" || fake == "both")
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        onChange(apps.contains { $0.bundleIdentifier == Self.claudeBundle },
                 apps.contains { $0.bundleIdentifier == Self.codexBundle })
    }
}
