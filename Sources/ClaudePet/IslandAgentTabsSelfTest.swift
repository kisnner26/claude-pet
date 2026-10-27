import Foundation

enum IslandAgentTabsSelfTest {
    static func run() -> Bool {
        let start = ContextReading(usedTokens: 10, compactAtTokens: 100, model: "codex")
        let end = ContextReading(usedTokens: 70, compactAtTokens: 100, model: "codex")
        var history = ContextTrend.append(start, to: [], at: Date(timeIntervalSince1970: 1))
        history = ContextTrend.append(end, to: history, at: Date(timeIntervalSince1970: 2))
        let ok = IslandAgentTabs.available(codex: false) == [.claude] && IslandAgentTabs.available(codex: true).count == 2 && IslandAgentTabs.keep(.codex, codex: false) == .claude && ContextTrend.label(history) == "-60 puntos"
        print(ok ? "TABS OK" : "TABS FALLOS"); return ok
    }
}
