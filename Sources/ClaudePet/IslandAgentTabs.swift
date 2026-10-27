import Foundation

enum IslandAgentTab: String, CaseIterable { case claude, codex }

enum IslandAgentTabs {
    static func available(codex: Bool) -> [IslandAgentTab] { codex ? [.claude, .codex] : [.claude] }
    static func keep(_ tab: IslandAgentTab, codex: Bool) -> IslandAgentTab { available(codex: codex).contains(tab) ? tab : .claude }
}
