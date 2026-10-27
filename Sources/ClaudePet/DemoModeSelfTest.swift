import Foundation

@MainActor
enum DemoModeSelfTest {
    static func run() -> Bool {
        let store = PetStore()
        store.startDemo()
        let loaded = store.demoMode && store.permissionAsks.count == 1 && store.questionAsks.count == 1
            && store.pendingAttentionCount == 2 && store.attentionLabel == "2 decisiones pendientes"
            && store.attentionBadgeLabel == "2"
            && store.recentIslandSteps.count == 3 && store.contextReading?.pressure == .caution
            && store.codexContextLabel.contains("63%") && store.sessionSummary == "claude-pet · Edit"
        store.stopDemo()
        let clean = !store.demoMode && store.permissionAsks.isEmpty && store.questionAsks.isEmpty
            && store.recentIslandSteps.isEmpty && store.contextReading == nil && store.codexContextReading == nil
        print(loaded && clean ? "DEMO OK" : "DEMO FALLOS")
        return loaded && clean
    }
}
