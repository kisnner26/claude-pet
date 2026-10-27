import Foundation

@MainActor
enum ShareSummarySelfTest {
    static func run() -> Bool {
        let mission = MissionControl()
        mission.recordLocal(state: .tool, project: "/tmp/claude-pet", workspace: "/tmp/claude-pet", tool: "Edit", session: "demo")
        let text = mission.shareSummary
        let report = mission.diagnosticReport
        let timeline = mission.timelineExport
        let agents = mission.activeAgents
        let ok = text.contains("claude-pet") && text.contains("agente claude") && !text.contains("/tmp")
            && report.contains("eventos recientes") && !report.contains("/tmp")
            && timeline.contains("claude\t") && agents == ["claude"]
        print(ok ? "RESUMEN OK" : "RESUMEN FALLOS")
        return ok
    }
}
