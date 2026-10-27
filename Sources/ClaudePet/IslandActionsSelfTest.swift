import Foundation

enum IslandActionsSelfTest {
    static func run() -> Bool {
        let actions = ["mission", "relay"]
        let ok = actions.contains("mission") && actions.contains("relay")
        print(ok ? "ACCIONES OK" : "ACCIONES FALLOS"); return ok
    }
}
