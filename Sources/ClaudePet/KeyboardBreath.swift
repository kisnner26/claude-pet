import Foundation
import AppKit

/// El teclado respira (experimental): mueve la retroiluminacion siguiendo el estado de los agentes y SIEMPRE devuelve tu brillo.
/// - Al apagarlo, al cerrar la app o cuando todo vuelve a la calma, restaura el brillo que tenias.
/// - Si la app se cae a mitad, lo restaura al volver a abrirse (el brillo original se guarda mientras se mueve).
/// - Si el sistema atenua o suprime la luz (inactividad, tapa), no la despierta.
@MainActor final class KeyboardBreath: ObservableObject {
    static let shared = KeyboardBreath()
    private static let enabledKey = "claudepet.keyboardBreath"
    private static let recoveryKey = "claudepet.keyboardBreath.original"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { schedule(fast: false) } else { restore() }
        }
    }

    private let light = KeyboardBacklight()
    private var original: Float?
    private var timer: Timer?
    private var runningFast = false
    private var state: PetState = .idle
    private var since = Date()
    private weak var store: PetStore?

    var available: Bool { light.available }

    private init() { enabled = UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func start(store: PetStore) {
        self.store = store
        // si la app se cayo moviendo la luz, devuelve el brillo que tenias
        if let saved = UserDefaults.standard.object(forKey: Self.recoveryKey) as? Float, light.available {
            light.set(saved)
            UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardBreath.shared.restore() }
        }
        if enabled { schedule(fast: false) }
    }

    private func schedule(fast: Bool) {
        guard timer == nil || fast != runningFast else { return }
        timer?.invalidate()
        runningFast = fast
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 15.0 : 0.5, repeats: true) { _ in MainActor.assumeIsolated { KeyboardBreath.shared.tick() } }
    }

    func tick() {
        guard enabled, light.available, let store else { restore(); return }
        if light.systemOwnsLight { restore(); schedule(fast: false); return }
        let now = KeyboardWave.combined(store.state, store.codexPresent ? store.codexState : .idle)
        if now != state { state = now; since = Date() }
        let base = original ?? light.brightness ?? 0
        if let target = KeyboardWave.level(state: state, age: Date().timeIntervalSince(since), time: ProcessInfo.processInfo.systemUptime, base: base) {
            if original == nil { original = base; UserDefaults.standard.set(base, forKey: Self.recoveryKey) }
            light.set(target)
            schedule(fast: true)
        } else {
            restore()
            schedule(fast: false)
        }
    }

    /// Devuelve el brillo que tenia el usuario (con un fundido corto) y deja de tener el control.
    func restore() {
        guard let o = original else { return }
        light.set(o, fade: 150)
        original = nil
        UserDefaults.standard.removeObject(forKey: Self.recoveryKey)
        if !enabled { timer?.invalidate(); timer = nil }
    }
}
