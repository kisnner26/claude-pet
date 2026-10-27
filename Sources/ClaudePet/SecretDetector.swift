import Foundation

struct SecretFinding: Equatable {
    let label: String
    let prefix: String
}

enum SecretDetector {
    static func find(in text: String, path: String = "") -> SecretFinding? {
        let lower = (text + " " + path).lowercased()
        if lower.contains(".env") { return SecretFinding(label: "archivo de entorno", prefix: prefix(text)) }
        if lower.contains("-----begin") { return SecretFinding(label: "bloque pem", prefix: prefix(text)) }
        let labels = ["sk-", "ghp_", "github_pat_", "xoxb-", "akia", "token=", "$token", "api_key", "secret="]
        if let label = labels.first(where: { lower.contains($0) }) { return SecretFinding(label: "posible credencial \(label)", prefix: prefix(text)) }
        return nil
    }

    private static func prefix(_ text: String) -> String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4)) }
}
