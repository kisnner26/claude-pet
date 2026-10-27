import Foundation

enum GlobalShortcutSelfTest {
    static func run() -> Bool {
        let ok = GlobalShortcut.allow.rawValue == "allow" && GlobalShortcut.deny.rawValue == "deny" && GlobalShortcut.island.rawValue == "island"
            && GlobalShortcut.snooze.rawValue == "snooze" && GlobalShortcut.pin.rawValue == "pin"
        print(ok ? "ATAJOS OK" : "ATAJOS FALLOS"); return ok
    }
}
