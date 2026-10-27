import Foundation

struct IslandStep: Identifiable, Equatable {
    let id = UUID()
    let agent: String
    let tool: String
    let target: String
    let added: Int
    let deleted: Int
    let workspace: String
    let at: Date

    var label: String { "\(tool) · \(target)" }
    var delta: String { added == 0 && deleted == 0 ? "" : "+\(added) -\(deleted)" }
}

enum IslandSteps {
    static func append(_ step: IslandStep, to steps: [IslandStep], limit: Int = 8) -> [IslandStep] {
        Array((steps + [step]).suffix(limit))
    }
}
