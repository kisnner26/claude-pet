import Foundation
import Darwin

struct IslandQuestion: Identifiable {
    let id: String
    let header: String
    let question: String
    let options: [(label: String, description: String)]
    let multiSelect: Bool
}

struct QuestionAsk: Identifiable {
    let id: String
    let session: String
    let project: String
    let questions: [IslandQuestion]
}

struct QuestionAnswer {
    let question: IslandQuestion
    var selected: Set<Int>
}

final class QuestionServer: @unchecked Sendable {
    static let defaultPath = PermissionServer.defaultPath
    private let permission = PermissionServer()
    private(set) var asks: [QuestionAsk] = []
    var onChange: (([QuestionAsk]) -> Void)?
    private var answers: [String: [QuestionAnswer]] = [:]

    func start() throws { try permission.start() }
    func stop() { permission.stop() }

    // El transporte común usa líneas `ask<TAB>sesión<TAB>proyecto<TAB>json`.
    // La implementación queda separada para que el protocolo de permisos no cambie.
    func enqueue(_ ask: QuestionAsk) {
        asks.append(ask); onChange?(asks)
    }

    @discardableResult
    func resolve(id: String, answers: [QuestionAnswer]) -> Bool {
        guard let i = asks.firstIndex(where: { $0.id == id }) else { return false }
        self.answers[id] = answers
        asks.remove(at: i); onChange?(asks); return true
    }

    static func parse(_ line: String) -> QuestionAsk? {
        let p = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard p.count == 4, p[0] == "ask", let data = Data(base64Encoded: p[3]),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !raw.isEmpty else { return nil }
        let qs: [IslandQuestion] = raw.prefix(4).compactMap { q in
            guard let question = q["question"] as? String, let options = q["options"] as? [[String: Any]], !question.isEmpty else { return nil }
            let choices = options.prefix(8).compactMap { o -> (String, String)? in
                guard let label = o["label"] as? String, !label.isEmpty else { return nil }
                func clean(_ value: String, _ limit: Int) -> String { String(value.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(limit).map(Character.init)) }
                return (clean(label, 120), clean(o["description"] as? String ?? "", 240))
            }
            func clean(_ value: String, _ limit: Int) -> String { String(value.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(limit).map(Character.init)) }
            return IslandQuestion(id: UUID().uuidString, header: clean(q["header"] as? String ?? "", 40), question: clean(question, 400), options: choices, multiSelect: q["multiSelect"] as? Bool ?? false)
        }
        guard !qs.isEmpty else { return nil }
        return QuestionAsk(id: UUID().uuidString, session: p[1], project: p[2], questions: qs)
    }
}
