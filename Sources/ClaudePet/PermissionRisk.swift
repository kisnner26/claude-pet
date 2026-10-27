import Foundation
import SwiftUI

enum PermissionRisk: String, CaseIterable {
    case low = "bajo"
    case medium = "medio"
    case high = "alto"

    var color: Color {
        switch self { case .low: return Color(hex: 0x6CCB8A); case .medium: return Color(hex: 0xE7B45B); case .high: return Color(hex: 0xD85C5C) }
    }
}

struct PermissionRiskReading: Equatable {
    let risk: PermissionRisk
    let reason: String
}

enum PermissionRiskClassifier {
    static func classify(tool: String, detail: String, project: String) -> PermissionRiskReading {
        let raw = "\(tool) \(detail)".lowercased()
        let compact = raw.replacingOccurrences(of: "\\\"", with: "").replacingOccurrences(of: "'", with: "")
        let high = ["rm -rf", "rm -fr", "git push --force", "git push -f", "git reset --hard", "chmod", "chown", "sudo ", "curl|sh", "curl | sh", "wget|sh", "wget | sh", ".env", ".ssh", "-----begin", "api_key", "apikey", "token=", "secret="]
        if high.contains(where: { compact.contains($0) }) { return .init(risk: .high, reason: "puede borrar, elevar privilegios o exponer credenciales") }
        if compact.contains("..") || compact.contains("~/") || compact.contains("/") && compact.contains("/users/") {
            return .init(risk: .high, reason: "la ruta puede salir del proyecto")
        }
        if tool == "ExitPlanMode" { return .init(risk: .medium, reason: "aprobar el plan deja a claude empezar a editar y ejecutar") }
        let editTools = ["edit", "write", "multiedit", "bash", "shell", "python", "node"]
        if editTools.contains(where: { tool.lowercased().contains($0) }) { return .init(risk: .medium, reason: "modifica archivos o ejecuta un comando") }
        return .init(risk: .low, reason: "solo parece leer información")
    }
}
