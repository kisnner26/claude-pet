import Foundation

/// Ajustes de la recuperacion inteligente del cerebro. Viven en su propio archivo (0600) y no en config.json a proposito:
/// los lee el comando `--brain` en un proceso aparte, y config.json lo reescribe la app en marcha con su copia en memoria.
/// Por defecto esta APAGADA: el cerebro se comporta como siempre hasta que se enciende con `--brain config smart on`.
enum BrainSettings {
    struct Values: Codable, Equatable {
        var smartRecall = false
        /// presupuesto en tokens estimados de lo que se inyecta en cada mensaje; al abrir la sesion se usa el doble
        var recallBudget = 400

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: Key.self)
            smartRecall = (try? c.decode(Bool.self, forKey: .smartRecall)) ?? false
            recallBudget = BrainSettings.clampBudget((try? c.decode(Int.self, forKey: .recallBudget)) ?? 400)
        }
        enum Key: String, CodingKey { case smartRecall, recallBudget }
    }

    static let budgetRange = 100...2000

    static func clampBudget(_ n: Int) -> Int { min(budgetRange.upperBound, max(budgetRange.lowerBound, n)) }

    static var path: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_BRAIN_SETTINGS"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/brain-settings.json"
    }

    /// Falla abierto: archivo ausente o roto = valores por defecto. CLAUDE_PET_BRAIN_SMART=1|0 manda sobre el archivo.
    static func load(path: String = BrainSettings.path, applyEnv: Bool = true) -> Values {
        var v = Values()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 4096, let d = try? JSONDecoder().decode(Values.self, from: data) { v = d }
        guard applyEnv else { return v }
        switch ProcessInfo.processInfo.environment["CLAUDE_PET_BRAIN_SMART"] {
        case "1": v.smartRecall = true
        case "0": v.smartRecall = false
        default: break
        }
        return v
    }

    @discardableResult
    static func save(_ v: Values, path: String = BrainSettings.path) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder.pretty.encode(v).write(to: url, options: .atomic)
            chmod(path, 0o600)
            return true
        } catch { return false }
    }
}
