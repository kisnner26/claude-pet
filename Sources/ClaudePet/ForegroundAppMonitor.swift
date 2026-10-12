import AppKit

/// Lee únicamente qué app está al frente. No captura pantalla, ventanas ni contenido.
@MainActor
final class ForegroundAppMonitor {
    private var token: NSObjectProtocol?
    private let onChange: (String) -> Void

    init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

    func start() {
        scan()
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        guard let app = NSWorkspace.shared.frontmostApplication else { onChange(""); return }
        onChange(app.localizedName ?? "otra app")
    }

    deinit { if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
}
