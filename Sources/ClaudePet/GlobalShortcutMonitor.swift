import AppKit

enum GlobalShortcut: String, CaseIterable { case allow, deny, island, snooze, pin }

final class GlobalShortcutMonitor {
    var onShortcut: ((GlobalShortcut) -> Void)?
    /// Las letras se pueden cambiar en ajustes; el monitor siempre lee el mapa vigente.
    var map = ShortcutMap.standard
    private var token: Any?
    func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.control, .option], !event.isARepeat,
                  let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1,
                  let shortcut = self?.map.shortcut(for: key) else { return }
            self?.onShortcut?(shortcut)
        }
    }
    func stop() { if let token { NSEvent.removeMonitor(token); self.token = nil } }
    deinit { stop() }
}
