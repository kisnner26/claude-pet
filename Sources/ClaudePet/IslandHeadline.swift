import Foundation

/// Lo que "dice" la mascota: una frase corta y humana sobre lo que esta haciendo el agente.
/// Pura: recibe el estado y el ultimo paso, devuelve texto. Nunca incluye comandos ni rutas, solo el nombre del archivo.
enum IslandHeadline {
    private static let idlePhrases = ["descansando", "lista para lo que venga", "atenta", "esperando la siguiente tarea"]

    private static func file(_ target: String) -> String {
        let name = (target as NSString).lastPathComponent
        return name.isEmpty ? "" : String(name.prefix(36))
    }

    /// `tool` y `target` salen del ultimo paso del agente (`target` puede ser una ruta).
    static func make(state: PetState, tool: String, target: String, asking: Bool = false, idleSeconds: TimeInterval = 0) -> String {
        if asking { return "esperando tu permiso" }
        switch state {
        case .waiting: return "esperando tu respuesta"
        case .error: return "algo falló, échale un ojo"
        case .done: return "listo"
        case .starting: return "arrancando"
        case .thinking: return "pensando"
        case .idle:
            if idleSeconds >= PetAnimator.sleepAfter { return "dormida, tócame para despertarme" }
            return idlePhrases[Int(max(0, idleSeconds) / 20) % idlePhrases.count]
        case .tool:
            let f = file(target)
            switch tool {
            case "Read": return f.isEmpty ? "leyendo" : "leyendo \(f)"
            case "Edit", "MultiEdit", "NotebookEdit": return f.isEmpty ? "editando" : "editando \(f)"
            case "Write": return f.isEmpty ? "escribiendo" : "escribiendo \(f)"
            case "Bash", "test": return "ejecutando un comando"
            case "Grep", "Glob", "LS": return "buscando en el proyecto"
            case "WebFetch", "WebSearch": return "consultando la web"
            case "Task": return "delegando una tarea"
            case "TodoWrite": return "actualizando la lista"
            case "": return "trabajando"
            default: return "usando \(tool.prefix(24))"
            }
        }
    }
}
