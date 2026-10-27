import Foundation

enum GlobalShortcutSelfTest {
    static func run() -> Bool {
        let ok = GlobalShortcut.allow.rawValue == "allow" && GlobalShortcut.deny.rawValue == "deny" && GlobalShortcut.island.rawValue == "island"
        print(ok ? "ATAJOS OK" : "ATAJOS FALLOS"); return ok
    }
}
