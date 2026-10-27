import Foundation

struct LoopAlert: Equatable {
    enum Reason: String { case repeatedError = "el mismo error se repite", repeatedSearch = "la misma búsqueda se repite", repeatedEdit = "el mismo archivo se edita sin parar" }
    let reason: Reason
    let tool: String
    let target: String
    let count: Int

    var title: String { "posible bucle: \(reason.rawValue)" }
    var summary: String { "\(tool)\(target.isEmpty ? "" : " · \(target)") · \(count) veces seguidas" }
}

/// Detecta repeticiones sospechosas en los eventos de una sesion. Pura: no tiene reloj propio ni guarda contenido,
/// solo la herramienta y el objetivo recortado de los ultimos pasos.
struct LoopDetector {
    static let errorThreshold = 3
    static let searchThreshold = 4
    static let editThreshold = 6
    static let window: TimeInterval = 300
    static let quietAfterAlert: TimeInterval = 300
    private static let searchTools: Set<String> = ["Grep", "Glob", "WebSearch", "WebFetch"]

    private struct Step { let tool: String; let target: String; let failed: Bool; let at: TimeInterval }
    private var steps: [Step] = []
    private var quietUntil: [String: TimeInterval] = [:]

    mutating func reset() { steps = []; quietUntil = [:] }

    /// Registra un paso y devuelve una alerta si cierra un patron sospechoso.
    mutating func record(tool: String, target: String, failed: Bool, at now: TimeInterval) -> LoopAlert? {
        let t = String(target.prefix(120))
        steps.append(Step(tool: tool, target: t, failed: failed, at: now))
        steps.removeAll { now - $0.at > Self.window }
        if steps.count > 60 { steps.removeFirst(steps.count - 60) }

        func consecutive(where match: (Step) -> Bool) -> Int {
            var n = 0
            for s in steps.reversed() { if match(s) { n += 1 } else { break } }
            return n
        }
        let same = { (s: Step) in s.tool == tool && s.target == t }
        let candidate: LoopAlert?
        if failed, consecutive(where: { same($0) && $0.failed }) >= Self.errorThreshold {
            candidate = LoopAlert(reason: .repeatedError, tool: tool, target: t, count: consecutive(where: { same($0) && $0.failed }))
        } else if Self.searchTools.contains(tool), consecutive(where: same) >= Self.searchThreshold {
            candidate = LoopAlert(reason: .repeatedSearch, tool: tool, target: t, count: consecutive(where: same))
        } else if !failed, ["Edit", "Write", "MultiEdit"].contains(tool), consecutive(where: same) >= Self.editThreshold {
            candidate = LoopAlert(reason: .repeatedEdit, tool: tool, target: t, count: consecutive(where: same))
        } else { candidate = nil }

        guard let alert = candidate else { return nil }
        let key = "\(alert.reason.rawValue)|\(tool)|\(t)"
        if let until = quietUntil[key], now < until { return nil }
        quietUntil[key] = now + Self.quietAfterAlert
        return alert
    }
}
