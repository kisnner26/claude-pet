import Foundation

enum TerminalTargetSelfTest {
    static func run() -> Bool {
        let one = [TerminalCandidate(pid: 1, app: "Ghostty", title: "claude-pet — zsh")]
        let two = one + [TerminalCandidate(pid: 2, app: "Ghostty", title: "claude-pet — zsh")]
        let ok = TerminalTargetResolver.choose(project: "claude-pet", candidates: one)?.pid == 1
        let ambiguous = TerminalTargetResolver.choose(project: "claude-pet", candidates: two) == nil
        let unrelated = TerminalTargetResolver.choose(project: "claude-pet", candidates: [TerminalCandidate(pid: 3, app: "Safari", title: "claude-pet")]) == nil
        print(ok && ambiguous && unrelated ? "TERMINAL OK" : "TERMINAL FALLOS")
        return ok && ambiguous && unrelated
    }
}
