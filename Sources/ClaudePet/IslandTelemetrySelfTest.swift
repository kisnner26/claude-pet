import Foundation

@MainActor
enum IslandTelemetrySelfTest {
    static func run() -> Bool {
        let readings = [ContextReading(usedTokens: 10, compactAtTokens: 100, model: "x"), ContextReading(usedTokens: 70, compactAtTokens: 100, model: "x"), ContextReading(usedTokens: 95, compactAtTokens: 100, model: "x")]
        let files = [ChangedFile(path: "a.swift", added: 3, deleted: 1, untracked: false, staged: false, conflict: false, modified: nil)]
        let store = PetStore(); store.refreshTelemetryNow()
        let ok = readings.map(\.pressure) == [.normal, .caution, .critical] && !PetOverlayLayout.orbitItems(files).isEmpty
        let demo = PetStore(); demo.startDemo()
        let labelOK = demo.contextLabel.contains("30%")
        demo.stopDemo()
        let final = ok && labelOK
        print(final ? "TELEMETRIA OK" : "TELEMETRIA FALLOS"); return final
    }
}
