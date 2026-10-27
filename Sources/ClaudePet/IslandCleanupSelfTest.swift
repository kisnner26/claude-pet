import Foundation

enum IslandCleanupSelfTest {
    static func run() -> Bool {
        let root = NSTemporaryDirectory() + "cleanup-\(UUID().uuidString)"; let path = root + "/.claude-pet/island-permissions"
        try? FileManager.default.createDirectory(atPath: root + "/.claude-pet", withIntermediateDirectories: true); FileManager.default.createFile(atPath: path, contents: Data()); IslandCleanup.removeFlag(home: root)
        let ok = !FileManager.default.fileExists(atPath: path); try? FileManager.default.removeItem(atPath: root); print(ok ? "LIMPIEZA OK" : "LIMPIEZA FALLOS"); return ok
    }
}
