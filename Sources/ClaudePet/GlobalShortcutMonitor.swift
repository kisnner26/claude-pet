import AppKit

enum GlobalShortcut: String { case allow, deny, island, snooze, pin }

final class GlobalShortcutMonitor {
    var onShortcut: ((GlobalShortcut) -> Void)?
    private var token: Any?
    func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.control, .option]) == [.control, .option], let key = event.charactersIgnoringModifiers?.lowercased(), let shortcut = ["a": GlobalShortcut.allow, "d": .deny, "i": .island, "s": .snooze, "p": .pin][key] else { return }
            self?.onShortcut?(shortcut)
        }
    }
    func stop() { if let token { NSEvent.removeMonitor(token); self.token = nil } }
    deinit { stop() }
}
