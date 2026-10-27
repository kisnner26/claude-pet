import Foundation

enum IslandStepsSelfTest {
    static func run() -> Bool {
        let first = IslandStep(agent: "claude", tool: "Edit", target: "main.swift", added: 4, deleted: 2, workspace: "/tmp/x", at: Date())
        let list = IslandSteps.append(first, to: [])
        let ok = list.count == 1 && list[0].delta == "+4 -2" && !list[0].workspace.isEmpty
        print(ok ? "STEPS OK" : "STEPS FALLOS"); return ok
    }
}
