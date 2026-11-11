import Foundation

struct SecretFinding: Equatable {
    let label: String
    let prefix: String
}

enum SecretDetector {
    static func find(in text: String, path: String = "") -> SecretFinding? {
        let lower = (text + " " + path).lowercased()
        if lower.contains(".env") { return SecretFinding(label: "archivo de entorno", prefix: prefix(text)) }
        if let label = contentLabel(lower) { return SecretFinding(label: label, prefix: prefix(text)) }
        return nil
    }

    /// Lineas anadidas por un cambio. Solo mira el contenido: el nombre del archivo ya lo revisa `find(in:path:)`, y `process.env` en
    /// codigo normal no es un archivo de entorno. La pista es el numero de linea, nunca caracteres de la credencial.
    static func find(inLines lines: [String]) -> SecretFinding? {
        for (i, line) in lines.enumerated() {
            if let label = contentLabel(line.lowercased()) { return SecretFinding(label: label, prefix: "línea \(i + 1)") }
        }
        return nil
    }

    private static func contentLabel(_ lower: String) -> String? {
        if lower.contains("-----begin") { return "bloque pem" }
        // «sk-» y «akia» dentro de una palabra («task-list», «mask-image») no son claves: deben empezar una y tener cuerpo
        if hasKey(lower, "sk-", minBody: 6, charset: { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) { return "posible credencial sk-" }
        if hasKey(lower, "akia", minBody: 12, charset: { $0.isASCII && ($0.isLetter || $0.isNumber) }) { return "posible credencial akia" }
        let labels = ["ghp_", "github_pat_", "xoxb-", "token=", "$token", "api_key", "secret="]
        if let label = labels.first(where: { lower.contains($0) }) { return "posible credencial \(label)" }
        return nil
    }

    private static func hasKey(_ lower: String, _ marker: String, minBody: Int, charset: (Character) -> Bool) -> Bool {
        var from = lower.startIndex
        while let r = lower.range(of: marker, range: from..<lower.endIndex) {
            let startsWord = r.lowerBound == lower.startIndex || !(lower[lower.index(before: r.lowerBound)].isLetter || lower[lower.index(before: r.lowerBound)].isNumber)
            if startsWord, lower[r.upperBound...].prefix(while: charset).count >= minBody { return true }
            from = r.upperBound
        }
        return false
    }

    private static func prefix(_ text: String) -> String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4)) }
}
