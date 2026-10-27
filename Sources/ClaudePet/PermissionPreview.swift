import Foundation

struct PermissionPreview: Equatable {
    let title: String
    let lines: [String]
    let truncated: Bool
}

enum PermissionPreviewBuilder {
    static func make(tool: String, detail: String, project: String) -> PermissionPreview {
        let lower = tool.lowercased()
        if lower.contains("bash") || lower.contains("shell") {
            return PermissionPreview(title: "comando · \(project.isEmpty ? "directorio no indicado" : project)", lines: [detail], truncated: false)
        }
        if tool == "ExitPlanMode" {
            let steps = detail.components(separatedBy: " ~ ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return PermissionPreview(title: "plan propuesto", lines: Array(steps.prefix(40)), truncated: steps.count > 40)
        }
        let source = detail.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let shown = Array(source.prefix(40))
        return PermissionPreview(title: "cambio previsto", lines: shown, truncated: source.count > shown.count)
    }
}
