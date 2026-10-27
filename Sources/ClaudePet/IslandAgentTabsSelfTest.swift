import Foundation

enum IslandAgentTabsSelfTest {
    static func run() -> Bool {
        let ok = IslandAgentTabs.available(codex: false) == [.claude] && IslandAgentTabs.available(codex: true).count == 2 && IslandAgentTabs.keep(.codex, codex: false) == .claude
        print(ok ? "TABS OK" : "TABS FALLOS"); return ok
    }
}
