import Foundation

/// Lo que la burbuja muestra.
struct Activity: Equatable {
    var title: String
    var subtitle: String
    var origin: String
}

enum PetState: String, CaseIterable {
    case idle, starting, thinking, tool, waiting, done, error

    var label: String {
        switch self {
        case .idle: return "INACTIVO"
        case .starting: return "INICIANDO"
        case .thinking: return "PENSANDO"
        case .tool: return "EJECUTANDO"
        case .waiting: return "TU APROBACION"
        case .done: return "LISTO"
        case .error: return "ERROR"
        }
    }

    /// Con varias sesiones abiertas se muestra la de mayor prioridad.
    var priority: Int {
        switch self {
        case .waiting: return 6
        case .error: return 5
        case .tool: return 4
        case .thinking: return 3
        case .starting: return 2
        case .done: return 1
        case .idle: return 0
        }
    }
}

/// Lo unico que cruza el socket: estado, sesion corta y nombre de herramienta.
/// Nunca prompts, rutas, comandos ni salidas.
struct PetEvent {
    enum Kind { case state(PetState), end }
    let kind: Kind
    let session: String
    let tool: String
    let project: String
    let detail: String
    let origin: String
    /// Ruta local solo para el detector; nunca se muestra ni cruza el pet bus.
    let workspace: String
    /// "p:<mensaje>" o "t:<tarea en curso>" (vacio si este evento no la cambia)
    let task: String

    /// Formato de linea: "<estado>\t<sesion>\t<herramienta>[\t<proyecto>]"
    static func parse(_ line: String) -> PetEvent? {
        let parts = line.split(separator: "\t", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let kind: Kind
        if parts[0] == "end" { kind = .end }
        else if let s = PetState(rawValue: parts[0]) { kind = .state(s) }
        else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
        func clean(_ s: String, _ n: Int) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.filter { allowed.contains($0) }.prefix(n)))
        }
        /// Texto libre para mostrar: sin controles, recortado por caracteres.
        func text(_ s: String, _ n: Int) -> String {
            String(s.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init).prefix(n))
                .trimmingCharacters(in: .whitespaces)
        }
        return PetEvent(kind: kind, session: clean(parts[1], 16), tool: parts.count > 2 ? clean(parts[2], 40) : "",
                        project: parts.count > 3 ? clean(parts[3], 40) : "",
                        detail: parts.count > 4 ? text(parts[4], 80) : "",
                        origin: parts.count > 5 ? clean(parts[5], 12) : "",
                        workspace: parts.count > 7 && parts[7].hasPrefix("/") ? String(parts[7].prefix(1024)) : "",
                        task: parts.count > 6 ? text(parts[6], 140) : "")
    }
}
