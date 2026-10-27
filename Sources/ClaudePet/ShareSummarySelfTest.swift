import Foundation

@MainActor
enum ShareSummarySelfTest {
    static func run() -> Bool {
        let mission = MissionControl()
        mission.recordLocal(state: .tool, project: "/tmp/claude-pet", workspace: "/tmp/claude-pet", tool: "Edit", session: "demo")
        let text = mission.shareSummary
        let ok = text.contains("claude-pet") && text.contains("agente claude") && !text.contains("/tmp")
        print(ok ? "RESUMEN OK" : "RESUMEN FALLOS")
        return ok
    }
}
