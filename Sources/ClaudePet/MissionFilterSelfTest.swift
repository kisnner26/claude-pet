import Foundation

@MainActor
enum MissionFilterSelfTest {
    static func run() -> Bool {
        let mission = MissionControl()
        mission.recordLocal(state: .thinking, project: "demo", workspace: "/tmp/demo", session: "a")
        mission.recordPeer(state: .tool, project: "demo")
        mission.timelineFilter = .claude
        let claudeOnly = mission.filteredTimeline.allSatisfy { $0.agent == "claude" }
        mission.timelineFilter = .codex
        let codexOnly = mission.filteredTimeline.allSatisfy { $0.agent == "codex" }
        mission.timelineFilter = .all
        let all = mission.filteredTimeline.count >= 2
        let label = mission.filteredTimelineLabel == "2 eventos"
        mission.clearTimeline()
        let cleared = mission.filteredTimeline.isEmpty
        let ok = claudeOnly && codexOnly && all && label && cleared
        print(ok ? "FILTRO OK" : "FILTRO FALLOS")
        return ok
    }
}
