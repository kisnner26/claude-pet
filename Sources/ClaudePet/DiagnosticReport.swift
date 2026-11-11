import Foundation
import AppKit

// MARK: diagnostico para copiar

/// Datos del texto «copiar diagnostico». Separado de la recoleccion para poder probar el texto con datos inventados.
struct DiagnosticInfo {
    var appVersion: String
    var build: String
    var packaged: Bool
    var macOS: String
    var arch: String
    var model: String
    var hasNotch: Bool
    var language: String
    var loginItem: String
    var features: [(name: String, on: Bool)]
    var components: [(name: String, state: String)]
    var plugins: (enabled: Int, total: Int)
}

enum DiagnosticReport {
    /// Texto corto en espanol, una linea por dato. Todo pasa por `scrub`.
    static func text(_ i: DiagnosticInfo, home: String = NSHomeDirectory(), user: String = NSUserName()) -> String {
        func yn(_ b: Bool) -> String { b ? "sí" : "no" }
        var lines = [
            "claude-pet \(i.appVersion) (\(i.build))",
            "macOS \(i.macOS) · \(i.arch) · \(i.model)",
            "empaquetada: \(yn(i.packaged)) · notch: \(yn(i.hasNotch)) · idioma: \(i.language)",
            "abrir al iniciar sesión: \(i.loginItem)",
            "",
            "funciones opcionales"
        ]
        lines += i.features.map { "  \($0.name): \(yn($0.on))" }
        lines.append("  plugins activos: \(i.plugins.enabled) de \(i.plugins.total)")
        lines += ["", "sockets y servicios"]
        lines += i.components.map { "  \($0.name): \($0.state)" }
        return scrub(lines.joined(separator: "\n"), home: home, user: user)
    }

    /// Defensa final: si por error se coló la carpeta personal o el nombre de usuario, no sale del equipo.
    static func scrub(_ s: String, home: String, user: String) -> String {
        var out = s
        if home.count > 1 { out = out.replacingOccurrences(of: home, with: "~") }
        if user.count > 1, user != "root" { out = out.replacingOccurrences(of: user, with: "usuario") }
        return out
    }

    /// Nombre estable de cada componente para el texto (y para el registro).
    static let componentOrder = ["eventos", "bus", "permisos", "visto", "quest"]

    static func components(from states: [String: ComponentState]) -> [(name: String, state: String)] {
        componentOrder.map { ($0, states[$0]?.label ?? "sin iniciar") }
    }

    /// Modelo de Mac ("Mac14,5"); es un identificador de hardware, no un dato personal.
    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 1 else { return "desconocido" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    @MainActor static func gather(store: PetStore) -> DiagnosticInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let features: [(name: String, on: Bool)] = [
            ("aprobar desde el iPhone o el Watch", store.remoteApprovals),
            ("relay", store.relayEnabled),
            ("Meta Quest", store.questEnabled),
            ("atajos globales", store.globalShortcutsEnabled),
            ("ritmo de escritura", store.typingRhythm),
            ("escritorio vivo", store.deskWorld),
            ("reproductor de música", store.musicPlayer),
            ("pronóstico del tiempo", store.weatherEnabled)
        ]
        let rows = store.plugins.rows
        return DiagnosticInfo(
            appVersion: Diag.appVersion,
            build: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "-",
            packaged: Bundle.main.bundleURL.pathExtension == "app",
            macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            arch: Diag.architecture(),
            model: hardwareModel(),
            hasNotch: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 },
            language: L.current.rawValue,
            loginItem: LoginItem.describe(LoginItem.state()),
            features: features,
            components: components(from: ComponentStates.shared.snapshot()),
            plugins: (rows.filter { $0.status == .enabled }.count, rows.count))
    }
}
