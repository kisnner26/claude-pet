import Foundation

enum IslandCleanup {
    static func removeFlag(home: String) { try? FileManager.default.removeItem(atPath: home + "/.claude-pet/island-permissions") }
}
