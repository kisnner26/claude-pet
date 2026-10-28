import Foundation
import CryptoKit

/// `ClaudePet --selftest-workshop <workshop> <malos>`: el catalogo real se instala entero sin red (fetch desde disco) y los paquetes
/// manipulados (huella, permisos, id, zip con `..`, enlaces simbolicos) se rechazan.
enum WorkshopSelfTest {
    static func run(workshop: String, evil: String) -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workshop-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let reg = PluginRegistry(root: tmp.appendingPathComponent("plugins"), statePath: nil)
        let disk: Workshop.Fetch = { url, limit in
            let d = try Data(contentsOf: URL(fileURLWithPath: url.path)); if d.count > limit { throw Workshop.WorkshopError.tooBig }; return d
        }
        func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
        func entry(_ file: String, id: String, perms: [String], version: String = "1.0.0", hash: String? = nil) -> WorkshopEntry {
            let path = (evil as NSString).appendingPathComponent(file)
            let d = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
            return WorkshopEntry(id: id, name: id, version: version, author: "x", description: "x", permissions: perms, official: false, url: path, sha256: hash ?? sha(d), size: max(1, d.count))
        }
        let sem = DispatchSemaphore(value: 0)
        var results: [String: Bool] = [:]
        var errors: [String: String] = [:]
        var catalog: [WorkshopEntry] = []
        Task.detached {
            func attempt(_ key: String, _ e: WorkshopEntry, trust: Bool = true) async {
                do { try await Workshop.install(e, into: reg, fetch: disk, trustAnyHost: trust); results[key] = true }
                catch { results[key] = false; errors[key] = String(reflecting: error) }
            }
            let indexURL = URL(fileURLWithPath: (workshop as NSString).appendingPathComponent("index.json"))
            catalog = (try? await Workshop.loadIndex(fetch: disk, from: indexURL)) ?? []
            for var e in catalog {
                e.url = (workshop as NSString).appendingPathComponent("packages/" + (e.url as NSString).lastPathComponent)
                await attempt("real:" + e.id, e)
            }
            if let first = catalog.first {
                var again = first; again.url = (workshop as NSString).appendingPathComponent("packages/" + (first.url as NSString).lastPathComponent)
                await attempt("reinstalar", again)
            }
            await attempt("hash", entry("buen.zip", id: "buen", perms: [], hash: String(repeating: "0", count: 64)))
            await attempt("permisos", entry("permisos.zip", id: "permisos", perms: []))
            await attempt("id", entry("id.zip", id: "otro-id", perms: []))
            await attempt("version", entry("buen.zip", id: "buen", perms: [], version: "9.9.9"))
            await attempt("host", entry("buen.zip", id: "buen", perms: []), trust: false)
            await attempt("simbolico", entry("simbolico.zip", id: "simbolico", perms: []))
            await attempt("slip", entry("slip.zip", id: "slip", perms: []))
            await attempt("buen", entry("buen.zip", id: "buen", perms: []))
            sem.signal()
        }
        sem.wait()

        check("catalogo real: hay plugins", catalog.count >= 10)
        for e in catalog { check("real \(e.id): se instala", results["real:" + e.id] == true); check("real \(e.id): queda desactivado y valido", reg.plugin(e.id)?.problems.isEmpty == true && reg.status(e.id) == .disabled) }
        check("reinstalar el mismo plugin actualiza sin error", results["reinstalar"] == true)
        check("huella distinta se rechaza", results["hash"] == false && errors["hash"]?.contains("huella") == true)
        check("permisos distintos al catalogo se rechazan", results["permisos"] == false && errors["permisos"]?.contains("(permisos)") == true && reg.plugin("permisos") == nil)
        check("id distinto al catalogo se rechaza", results["id"] == false && reg.plugin("otro-id") == nil)
        check("version distinta se rechaza", results["version"] == false)
        check("host no permitido se rechaza", results["host"] == false && errors["host"]?.contains("no permitida") == true)
        check("enlace simbolico dentro del paquete se rechaza", results["simbolico"] == false && reg.plugin("simbolico") == nil)
        check("zip con .. no escribe fuera ni rompe la instalacion", !fm.fileExists(atPath: NSTemporaryDirectory() + "/escapada-workshop.txt") && !fm.fileExists(atPath: tmp.appendingPathComponent("escapada-workshop.txt").path))
        check("paquete bueno manipulado en otro caso si se instala", results["buen"] == true && reg.plugin("buen") != nil)

        check("host permitido: raw.githubusercontent.com", Workshop.allowed("https://raw.githubusercontent.com/a/b/c.zip"))
        check("host no permitido: otro dominio", !Workshop.allowed("https://evil.example/c.zip"))
        check("host no permitido: http", !Workshop.allowed("http://raw.githubusercontent.com/c.zip"))
        check("host no permitido: parecido", !Workshop.allowed("https://raw.githubusercontent.com.evil.example/c.zip"))
        check("host no permitido: file", !Workshop.allowed("file:///tmp/x.zip"))

        let bad = #"{"schema":1,"plugins":[{"id":"ok-id","name":"a","version":"1.0.0","author":"a","description":"a","permissions":["notify"],"official":false,"url":"https://raw.githubusercontent.com/x","sha256":"\#(String(repeating: "a", count: 64))","size":10},{"id":"Mal Id","name":"a","version":"1.0.0","author":"a","description":"a","permissions":[],"official":false,"url":"u","sha256":"\#(String(repeating: "a", count: 64))","size":10},{"id":"perm-raro","name":"a","version":"1.0.0","author":"a","description":"a","permissions":["root"],"official":false,"url":"u","sha256":"\#(String(repeating: "a", count: 64))","size":10},{"id":"sha-corto","name":"a","version":"1.0.0","author":"a","description":"a","permissions":[],"official":false,"url":"u","sha256":"abc","size":10},{"id":"ok-id","name":"dup","version":"1.0.0","author":"a","description":"a","permissions":[],"official":false,"url":"u","sha256":"\#(String(repeating: "a", count: 64))","size":10}]}"#
        let filtered = (try? Workshop.decodeIndex(Data(bad.utf8))) ?? []
        check("indice: descarta ids raros, permisos desconocidos, huellas cortas y repetidos", filtered.map(\.id) == ["ok-id"] && filtered.first?.name == "a")
        check("indice: basura se rechaza", (try? Workshop.decodeIndex(Data("no es json".utf8))) == nil)
        check("indice: otro esquema se rechaza", (try? Workshop.decodeIndex(Data(#"{"schema":2,"plugins":[]}"#.utf8))) == nil)

        print(failures == 0 ? "TALLER OK" : "TALLER \(failures) FALLOS")
        return failures == 0
    }
}
