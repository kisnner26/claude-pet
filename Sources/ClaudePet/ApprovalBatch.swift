import Foundation

/// Agrupa peticiones de solo lectura iguales para aprobarlas con un clic. Nunca agrupa riesgo medio ni alto.
enum ApprovalBatch {
    static let minimum = 2
    static let maximum = 8

    /// Las peticiones que se pueden aprobar junto con la primera: misma herramienta de lectura, misma carpeta y mismo proyecto.
    static func group(_ asks: [PermissionAsk]) -> [PermissionAsk] {
        guard let first = asks.first, ["Read", "Glob", "Grep", "LS"].contains(first.tool),
              PermissionRiskClassifier.classify(tool: first.tool, detail: first.detail, project: first.project).risk == .low,
              let key = ApprovalRules.key(tool: first.tool, detail: first.detail) else { return [] }
        let same = asks.filter { ask in
            ask.tool == first.tool && ask.project == first.project && ask.session == first.session
                && ApprovalRules.key(tool: ask.tool, detail: ask.detail) == key
                && PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk == .low
        }
        return same.count >= minimum ? Array(same.prefix(maximum)) : []
    }
}
