import Foundation

struct ClaudePetConfig: Codable, Equatable {
    static let currentVersion = 1
    var version = currentVersion
    var layout = "flotante"
    var reduceMotion = false
    var soundEnabled = true
    var theme = "oscuro"
    var textScale = 1.0
    var compactDensity = "normal"
    var showClock = false
    var activationWidth = 240.0
    var activationDelay = 0.2
    var screenPreference = "pantalla del notch"

    static let defaults = ClaudePetConfig()
}

enum ConfigError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

final class ConfigStore {
    static let shared = ConfigStore()
    private(set) var value = ClaudePetConfig.defaults
    private(set) var lastError: String?

    static var path: String {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_PET_CONFIG"], !custom.isEmpty { return custom }
        return NSHomeDirectory() + "/.claude-pet/config.json"
    }

    @discardableResult
    func load(path: String = ConfigStore.path) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return true }
        do { value = try Self.decode(Data(contentsOf: URL(fileURLWithPath: path))); lastError = nil; return true }
        catch { lastError = error.localizedDescription; return false }
    }

    @discardableResult
    func save(path: String = ConfigStore.path) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder.pretty.encode(value)
            try data.write(to: url, options: .atomic)
            chmod(path, 0o600)
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    static func decode(_ data: Data) throws -> ClaudePetConfig {
        guard data.count <= 2 * 1024 * 1024 else { throw ConfigError.invalid("configuración demasiado grande") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConfigError.invalid("el archivo no es un objeto json") }
        let allowed = Set(["version", "layout", "reduceMotion", "soundEnabled", "theme", "textScale", "compactDensity", "showClock", "activationWidth", "activationDelay", "screenPreference"])
        if let unknown = object.keys.first(where: { !allowed.contains($0) }) { throw ConfigError.invalid("campo no permitido: \(unknown)") }
        let config = try JSONDecoder().decode(ClaudePetConfig.self, from: data)
        guard config.version == ClaudePetConfig.currentVersion else { throw ConfigError.invalid("versión no compatible") }
        guard ["flotante", "isla"].contains(config.layout), ["oscuro", "grafito", "crema", "coral"].contains(config.theme), ["minima", "normal", "amplia"].contains(config.compactDensity), ["pantalla del notch", "seguir al ratón"].contains(config.screenPreference), (0.75...2).contains(config.textScale), (120...400).contains(config.activationWidth), (0.05...1).contains(config.activationDelay) else { throw ConfigError.invalid("valor fuera de rango") }
        return config
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
