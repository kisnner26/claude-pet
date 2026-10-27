import Foundation

enum IslandStepsSelfTest {
    static func run() -> Bool {
        let first = IslandStep(agent: "claude", tool: "Edit", target: "main.swift", added: 4, deleted: 2, workspace: "/tmp/x", at: Date())
        let list = IslandSteps.append(first, to: [])
        let codex = IslandStep(agent: "codex", tool: "Apply", target: "README.md", added: 2, deleted: 0, workspace: "/tmp/x", at: Date())
        let mixed = [first, codex]
        let now = first.at.addingTimeInterval(65)
        let ok = list.count == 1 && list[0].delta == "+4 -2" && list[0].ageLabel(now: now) == "hace 1m" && !list[0].workspace.isEmpty
            && IslandSteps.forAgent(.claude, in: mixed).count == 1 && IslandSteps.forAgent(.codex, in: mixed).first?.tool == "Apply"
        print(ok ? "STEPS OK" : "STEPS FALLOS"); return ok
    }
}
