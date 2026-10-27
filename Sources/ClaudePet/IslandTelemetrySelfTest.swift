import Foundation

@MainActor
enum IslandTelemetrySelfTest {
    static func run() -> Bool {
        let readings = [ContextReading(usedTokens: 10, compactAtTokens: 100, model: "x"), ContextReading(usedTokens: 70, compactAtTokens: 100, model: "x"), ContextReading(usedTokens: 95, compactAtTokens: 100, model: "x")]
        let files = [ChangedFile(path: "a.swift", added: 3, deleted: 1, untracked: false, staged: false, conflict: false, modified: nil)]
        let store = PetStore(); store.refreshTelemetryNow()
        let ok = readings.map(\.pressure) == [.normal, .caution, .critical] && !PetOverlayLayout.orbitItems(files).isEmpty
        print(ok ? "TELEMETRIA OK" : "TELEMETRIA FALLOS"); return ok
    }
}
