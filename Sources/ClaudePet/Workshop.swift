import Foundation
import CryptoKit

/// Taller: catalogo publico de plugins. El indice y los paquetes viven en el repositorio (`workshop/`); publicar es abrir un pull request.
/// Un paquete solo se instala si su sha256 coincide con el del indice y si su manifiesto dice lo mismo que el indice
/// (id, version y permisos), de modo que el catalogo no puede prometer menos permisos de los que el plugin pide.
struct WorkshopEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var version: String
    var author: String
    var description: String
    var permissions: [String]
    var official: Bool
    var url: String
    var sha256: String
    var size: Int
    var homepage: String?
}

enum Workshop {
    static let maxPackage = 2 * 1024 * 1024
    static let maxIndex = 256 * 1024
    static let maxEntries = 300
    static let allowedHosts: Set<String> = ["raw.githubusercontent.com", "objects.githubusercontent.com", "github.com", "codeload.github.com"]

    static var indexURL: URL {
        URL(string: ProcessInfo.processInfo.environment["CLAUDE_PET_WORKSHOP"] ?? "https://raw.githubusercontent.com/kisnner26/claude-pet/main/workshop/index.json")!
    }

    enum WorkshopError: Error, CustomStringConvertible {
        case network, badIndex, badURL(String), tooBig, hash, unzip, mismatch(String), noPlugin
        var description: String {
            switch self {
            case .network: return "no se pudo llegar al taller. revisa la conexión"
            case .badIndex: return "el catálogo del taller no es válido"
            case .badURL(let id): return "«\(id)» apunta a una dirección no permitida"
            case .tooBig: return "el paquete pesa más de lo permitido"
            case .hash: return "el paquete no coincide con su huella sha256: no se instala"
            case .unzip: return "no se pudo abrir el paquete"
            case .mismatch(let what): return "el paquete no coincide con el catálogo (\(what)): no se instala"
            case .noPlugin: return "el paquete no contiene un plugin"
            }
        }
    }

    /// Solo https a hosts de GitHub (salvo que se fije otro indice por variable de entorno, para pruebas).
    static func allowed(_ s: String) -> Bool {
        guard let u = URL(string: s), u.scheme == "https", let h = u.host?.lowercased() else { return false }
        return allowedHosts.contains(h)
    }

    static func decodeIndex(_ data: Data) throws -> [WorkshopEntry] {
        struct Index: Decodable { var schema: Int; var plugins: [WorkshopEntry] }
        guard data.count <= maxIndex, let idx = try? JSONDecoder().decode(Index.self, from: data), idx.schema == 1, idx.plugins.count <= maxEntries else { throw WorkshopError.badIndex }
        let idRe = try NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]{1,39}$"), shaRe = try NSRegularExpression(pattern: "^[0-9a-f]{64}$")
        func ok(_ s: String, _ re: NSRegularExpression) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        var seen = Set<String>()
        return idx.plugins.filter { e in
            guard ok(e.id, idRe), ok(e.sha256, shaRe), e.size > 0, e.size <= maxPackage, seen.insert(e.id).inserted else { return false }
            return e.permissions.allSatisfy { PluginPermission(rawValue: $0) != nil }
        }
    }

    typealias Fetch = @Sendable (URL, Int) async throws -> Data

    static let liveFetch: Fetch = { url, limit in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("claude-pet-workshop", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { throw WorkshopError.network }
        guard data.count <= limit else { throw WorkshopError.tooBig }
        return data
    }

    static func loadIndex(fetch: Fetch = liveFetch, from url: URL = indexURL) async throws -> [WorkshopEntry] {
        try decodeIndex(try await fetch(url, maxIndex))
    }

    /// Descarga, verifica y extrae el paquete; devuelve la carpeta del plugin dentro de `scratch`.
    static func prepare(_ e: WorkshopEntry, scratch: URL, fetch: Fetch = liveFetch, trustAnyHost: Bool = false) async throws -> URL {
        guard trustAnyHost || allowed(e.url), let url = URL(string: e.url) else { throw WorkshopError.badURL(e.id) }
        let data = try await fetch(url, maxPackage)
        guard data.count <= maxPackage else { throw WorkshopError.tooBig }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == e.sha256 else { throw WorkshopError.hash }
        let fm = FileManager.default
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let zip = scratch.appendingPathComponent("p.zip"), out = scratch.appendingPathComponent("x")
        try data.write(to: zip)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-x", "-k", zip.path, out.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw WorkshopError.unzip }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw WorkshopError.unzip }
        // nada fuera de `out`, aunque el zip trajera rutas con ..
        let top = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix("__MACOSX") && !$0.lastPathComponent.hasPrefix(".") }) ?? []
        let root: URL
        if fm.fileExists(atPath: out.appendingPathComponent("plugin.json").path) { root = out }
        else if top.count == 1, fm.fileExists(atPath: top[0].appendingPathComponent("plugin.json").path) { root = top[0] }
        else { throw WorkshopError.noPlugin }
        guard let m = (try? Data(contentsOf: root.appendingPathComponent("plugin.json"))).flatMap(PluginManifest.decode) else { throw WorkshopError.noPlugin }
        if m.id != e.id { throw WorkshopError.mismatch("id") }
        if m.version != e.version { throw WorkshopError.mismatch("versión") }
        if Set(m.permissions) != Set(e.permissions) { throw WorkshopError.mismatch("permisos") }
        return root
    }

    /// Instala (o actualiza) una entrada. Nunca la activa: eso pide permisos al usuario.
    static func install(_ e: WorkshopEntry, into registry: PluginRegistry, fetch: Fetch = liveFetch, trustAnyHost: Bool = false) async throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workshop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = try await prepare(e, scratch: scratch, fetch: fetch, trustAnyHost: trustAnyHost)
        if registry.plugin(e.id) != nil { registry.uninstall(e.id) }
        _ = try registry.install(from: root)
    }
}

@MainActor
final class WorkshopModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var entries: [WorkshopEntry] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var busy: Set<String> = []
    @Published var message: String?

    func load() {
        guard phase != .loading else { return }
        phase = .loading
        Task {
            do { entries = try await Workshop.loadIndex(); phase = .loaded }
            catch { phase = .failed((error as? Workshop.WorkshopError)?.description ?? "no se pudo cargar el taller") }
        }
    }

    func install(_ e: WorkshopEntry, host: PluginHost) {
        guard !busy.contains(e.id) else { return }
        busy.insert(e.id); message = nil
        Task {
            do { try await Workshop.install(e, into: host.registry); host.reload(); host.show("«\(e.name)» instalado. actívalo para usarlo.") }
            catch { message = (error as? Workshop.WorkshopError)?.description ?? (error as? PluginRegistry.InstallError)?.description ?? error.localizedDescription }
            busy.remove(e.id)
        }
    }
}
