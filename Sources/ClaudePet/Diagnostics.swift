import Foundation
import os

/// Registro de diagnostico central, sobre `os.Logger`: se lee con Consola.app o
/// `log show --predicate 'subsystem == "local.claudepet.app"' --last 1h`.
///
/// Regla de privacidad: solo entran nombres de componentes, codigos de error y contadores.
/// Nunca comandos, rutas de archivos del usuario, contenido, codigos de emparejamiento ni titulos.
/// Por eso los errores se registran con `Diag.code(_:)` (dominio y numero) y nunca con su mensaje,
/// que en Foundation suele traer la ruta. No hay temporizadores ni trabajo periodico: cada linea es un evento puntual.
enum Diag {
    static let subsystem = "local.claudepet.app"
    /// Arranque, cierre y version.
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Sockets locales: eventos, bus y permisos.
    static let sockets = Logger(subsystem: subsystem, category: "sockets")
    /// Enlace remoto (Visto, relay) y servidor de Quest.
    static let remote = Logger(subsystem: subsystem, category: "remoto")
    /// Carga y ejecucion de plugins.
    static let plugins = Logger(subsystem: subsystem, category: "plugins")
    /// Abrir al iniciar sesion.
    static let login = Logger(subsystem: subsystem, category: "inicio")

    /// Codigo de error sin mensaje: "NSPOSIXErrorDomain:48". El mensaje queda fuera a proposito.
    static func code(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain):\(e.code)"
    }

    /// Version corta de la app; "desarrollo" si se ejecuta sin bundle.
    static var appVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "desarrollo" }

    static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "otra"
        #endif
    }

    /// Anota el estado de un socket o servicio: lo usa el diagnostico para copiar, sin consultar nada a la red.
    static func socket(_ name: String, _ state: ComponentState) {
        ComponentStates.shared.set(name, state)
        switch state {
        case .up: sockets.info("\(name, privacy: .public): activo")
        case .down: sockets.info("\(name, privacy: .public): parado")
        case .failed(let code): sockets.error("\(name, privacy: .public): fallo \(code, privacy: .public)")
        }
    }
}

/// Estado de un componente de red local, tal y como lo vio la app por ultima vez.
enum ComponentState: Equatable {
    case up, down
    case failed(String)

    var label: String {
        switch self {
        case .up: return "activo"
        case .down: return "parado"
        case .failed(let code): return "error \(code)"
        }
    }
}

/// Ultimo estado conocido de cada componente. Se escribe solo en arranque, parada o fallo.
final class ComponentStates: @unchecked Sendable {
    static let shared = ComponentStates()
    private let lock = NSLock()
    private var states: [String: ComponentState] = [:]

    func set(_ name: String, _ state: ComponentState) { lock.lock(); states[name] = state; lock.unlock() }
    func snapshot() -> [String: ComponentState] { lock.lock(); defer { lock.unlock() }; return states }
}
