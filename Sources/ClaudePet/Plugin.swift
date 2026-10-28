import Foundation

/// Plugins de claude-pet: una carpeta con `plugin.json` y los ejecutables que declara. Aportan acciones (menu, isla),
/// ajustes propios y reaccionan a eventos. Corren como procesos con los privilegios del usuario: no son una caja de arena.
/// Los permisos del manifiesto deciden lo que claude-pet LES ENTREGA (la ruta del proyecto, eventos) y los efectos que
/// acepta de vuelta (copiar, avisar, abrir una url); el usuario los aprueba antes de activar el plugin.
enum PluginPermission: String, CaseIterable {
    case project, events, clipboard, notify, openURL = "open-url", music

    var title: String {
        switch self {
        case .project: return "ver la ruta y el nombre del proyecto activo"
        case .events: return "recibir eventos (sesión terminada, permisos)"
        case .clipboard: return "copiar texto al portapapeles"
        case .notify: return "mostrar avisos en la isla"
        case .openURL: return "abrir enlaces https en el navegador"
        case .music: return "leer la canción que suena (título y artista)"
        }
    }
}

enum PluginEvent: String, CaseIterable {
    case sessionDone = "session.done", permissionAsked = "permission.asked", permissionDecided = "permission.decided", musicTrack = "music.track"
    /// Algunos eventos llevan datos extra que exigen su propio permiso.
    var extraPermission: PluginPermission? { self == .musicTrack ? .music : nil }
}

struct PluginAction: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var symbol: String?
    var run: String
    var args: [String]?
    /// "project": solo se puede lanzar con un proyecto activo y exige el permiso `project`.
    var needs: String?
    var places: [String]?          // "menu", "island"; por defecto solo menu
}

struct PluginSetting: Codable, Equatable, Identifiable {
    var key: String
    var type: String               // "toggle", "text", "choice"
    var title: String
    var detail: String?
    var defaultValue: String?
    var options: [String]?
    var id: String { key }
    enum CodingKeys: String, CodingKey { case key, type, title, detail, defaultValue = "default", options }
}

struct PluginManifest: Codable, Equatable {
    var id: String
    var name: String
    var version: String
    var author: String
    var description: String
    var homepage: String?
    var minApp: String?
    var permissions: [String] = []
    var actions: [PluginAction] = []
    var settings: [PluginSetting] = []
    var events: [String: String] = [:]

    /// Las listas son opcionales en el archivo: un plugin minimo solo necesita id, name, version, author y description.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); version = try c.decode(String.self, forKey: .version)
        author = try c.decode(String.self, forKey: .author); description = try c.decode(String.self, forKey: .description)
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage); minApp = try c.decodeIfPresent(String.self, forKey: .minApp)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        actions = try c.decodeIfPresent([PluginAction].self, forKey: .actions) ?? []
        settings = try c.decodeIfPresent([PluginSetting].self, forKey: .settings) ?? []
        events = try c.decodeIfPresent([String: String].self, forKey: .events) ?? [:]
    }
    init(id: String, name: String, version: String, author: String, description: String) {
        self.id = id; self.name = name; self.version = version; self.author = author; self.description = description
    }
    enum CodingKeys: String, CodingKey { case id, name, version, author, description, homepage, minApp, permissions, actions, settings, events }

    static let maxBytes = 64 * 1024

    private static func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
    private static func safeText(_ s: String, max: Int) -> Bool { !s.isEmpty && s.count <= max && !s.contains(where: { $0.isNewline || $0 == "\0" }) }

    /// Ruta relativa dentro del plugin: nada de absolutas, `..` ni caracteres raros.
    static func safeRelative(_ p: String) -> Bool {
        guard !p.isEmpty, p.count <= 120, !p.hasPrefix("/"), !p.contains("\0") else { return false }
        return !p.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }

    /// Lista de problemas; vacia = valido.
    func problems(appVersion: String = PluginManifest.appVersion) -> [String] {
        var out: [String] = []
        if !Self.matches(id, "^[a-z0-9][a-z0-9-]{1,39}$") { out.append("id no válido (minúsculas, números y guiones, 2 a 40)") }
        if !Self.safeText(name, max: 40) { out.append("name vacío o demasiado largo") }
        if !Self.matches(version, "^\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}$") { out.append("version debe ser x.y.z") }
        if !Self.safeText(author, max: 60) { out.append("author vacío o demasiado largo") }
        if !Self.safeText(description, max: 240) { out.append("description vacía o demasiado larga") }
        if let h = homepage, !(h.hasPrefix("https://") && h.count <= 200 && URL(string: h) != nil) { out.append("homepage debe ser https") }
        if let m = minApp, Self.matches(m, "^\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}$") == false { out.append("minApp debe ser x.y.z") }
        else if let m = minApp, Self.compare(m, appVersion) == .orderedDescending { out.append("necesita claude-pet \(m) o superior") }
        let known = Set(PluginPermission.allCases.map(\.rawValue))
        for p in permissions where !known.contains(p) { out.append("permiso desconocido: \(p)") }
        if Set(permissions).count != permissions.count { out.append("permisos repetidos") }
        if actions.count > 12 { out.append("máximo 12 acciones") }
        if Set(actions.map(\.id)).count != actions.count { out.append("ids de acción repetidos") }
        for a in actions {
            if !Self.matches(a.id, "^[a-z0-9][a-z0-9-]{0,39}$") { out.append("acción \(a.id): id no válido") }
            if !Self.safeText(a.title, max: 40) { out.append("acción \(a.id): título no válido") }
            if !Self.safeRelative(a.run) { out.append("acción \(a.id): run debe ser una ruta relativa dentro del plugin") }
            if let args = a.args, args.count > 8 || args.contains(where: { $0.count > 200 || $0.contains("\0") }) { out.append("acción \(a.id): argumentos no válidos") }
            if let s = a.symbol, !Self.matches(s, "^[a-z0-9.]{1,40}$") { out.append("acción \(a.id): symbol no válido") }
            if let n = a.needs, n != "project" { out.append("acción \(a.id): needs solo admite \"project\"") }
            if a.needs == "project" && !permissions.contains("project") { out.append("acción \(a.id): needs project exige el permiso project") }
            if let pl = a.places, pl.contains(where: { !["menu", "island"].contains($0) }) { out.append("acción \(a.id): places solo admite menu o island") }
        }
        if settings.count > 20 { out.append("máximo 20 ajustes") }
        if Set(settings.map(\.key)).count != settings.count { out.append("claves de ajuste repetidas") }
        for s in settings {
            if !Self.matches(s.key, "^[a-z][a-z0-9_]{0,31}$") { out.append("ajuste \(s.key): clave no válida") }
            if !["toggle", "text", "choice"].contains(s.type) { out.append("ajuste \(s.key): tipo desconocido") }
            if !Self.safeText(s.title, max: 60) { out.append("ajuste \(s.key): título no válido") }
            if s.type == "choice", (s.options ?? []).isEmpty || (s.options ?? []).count > 12 || (s.options ?? []).contains(where: { !Self.safeText($0, max: 40) }) { out.append("ajuste \(s.key): opciones no válidas") }
            if let d = s.defaultValue, d.count > 200 { out.append("ajuste \(s.key): default demasiado largo") }
        }
        let eventNames = Set(PluginEvent.allCases.map(\.rawValue))
        if !events.isEmpty && !permissions.contains("events") { out.append("events exige el permiso events") }
        for (name, run) in events {
            if !eventNames.contains(name) { out.append("evento desconocido: \(name)") }
            if !Self.safeRelative(run) { out.append("evento \(name): run debe ser una ruta relativa dentro del plugin") }
            if let e = PluginEvent(rawValue: name), let need = e.extraPermission, !permissions.contains(need.rawValue) { out.append("evento \(name) exige el permiso \(need.rawValue)") }
        }
        return out
    }

    static var appVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "9999.0.0" }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func decode(_ data: Data) -> PluginManifest? {
        guard data.count <= maxBytes else { return nil }
        return try? JSONDecoder().decode(PluginManifest.self, from: data)
    }
}

/// Lo que un plugin puede pedir de vuelta en la ultima linea JSON de su salida. Solo con el permiso correspondiente.
struct PluginEffects: Equatable {
    var toast: String?
    var copy: String?
    var open: URL?

    static func parse(stdout: String, permissions: Set<String>) -> PluginEffects {
        guard let line = stdout.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              line.count <= 8_000, let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return PluginEffects() }
        func clean(_ s: String, _ n: Int) -> String { String(s.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 || $0 == "\n" }.prefix(n).map(Character.init)) }
        var e = PluginEffects()
        if permissions.contains("notify"), let t = obj["toast"] as? String { let c = clean(t, 160).replacingOccurrences(of: "\n", with: " "); if !c.isEmpty { e.toast = c } }
        if permissions.contains("clipboard"), let c = obj["copy"] as? String { let t = clean(c, 4_000); if !t.isEmpty { e.copy = t } }
        if permissions.contains("open-url"), let u = obj["open"] as? String, u.count <= 300, u.hasPrefix("https://"), let url = URL(string: u), url.host?.isEmpty == false { e.open = url }
        return e
    }
}

enum PluginEvents {
    /// Carga util de cada evento: solo nombres y estados, nunca rutas de archivos ni contenido. Cada plugin recibe lo que su permiso permite.
    static func payload(_ event: PluginEvent, fields: [String: String], permissions: Set<String>, project: (path: String, name: String)? = nil, now: Date = Date()) -> Data {
        var out: [String: Any] = ["event": event.rawValue, "time": ISO8601DateFormatter().string(from: now), "app": "claude-pet", "version": PluginManifest.appVersion]
        let allowed: [PluginEvent: [String]] = [.sessionDone: ["agent", "seconds"], .permissionAsked: ["tool", "project"], .permissionDecided: ["tool", "project", "decision", "source"], .musicTrack: ["title", "artist", "album", "app"]]
        for k in allowed[event] ?? [] { if let v = fields[k] { out[k] = String(v.prefix(200)) } }
        if permissions.contains("project"), let p = project { out["project_path"] = p.path; out["project_name"] = p.name }
        return (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    }
}

/// Un plugin encontrado en disco.
struct LoadedPlugin: Identifiable, Equatable {
    let manifest: PluginManifest
    let dir: URL
    let problems: [String]
    var id: String { manifest.id }
}

/// Estado por plugin que decide el usuario.
struct PluginState: Codable, Equatable {
    var enabled = false
    var approved: [String] = []          // permisos que el usuario acepto
    var approvedVersion = ""
    var settings: [String: String] = [:]
}

enum PluginStatus: Equatable {
    case invalid
    case disabled
    case needsApproval([String])         // permisos nuevos que aun no ha aceptado
    case enabled
}

enum PluginSecurity {
    /// Un ejecutable solo vale si, ya resueltos los enlaces, esta dentro de la carpeta del plugin, es un archivo normal,
    /// ejecutable, del propio usuario y nadie mas puede escribirlo.
    static func resolveExecutable(_ relative: String, in dir: URL) -> URL? {
        guard PluginManifest.safeRelative(relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative) else { return nil }
        let root = dir.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path), attrs[.type] as? FileAttributeType == .typeRegular,
              let mode = attrs[.posixPermissions] as? Int, mode & 0o100 != 0, mode & 0o022 == 0,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return nil }
        return file
    }

    /// Entorno minimo: nada de las variables del usuario (claves, tokens). Solo lo que el plugin tiene permiso de ver.
    static func environment(plugin: LoadedPlugin, settings: [String: String], project: (path: String, name: String)?, event: String?) -> [String: String] {
        var env: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "HOME": NSHomeDirectory(), "LANG": "es_ES.UTF-8", "TMPDIR": NSTemporaryDirectory(),
            "CLAUDE_PET": "1", "CLAUDE_PET_VERSION": PluginManifest.appVersion, "CLAUDE_PET_PLUGIN_ID": plugin.manifest.id, "CLAUDE_PET_PLUGIN_DIR": plugin.dir.path,
        ]
        let perms = Set(plugin.manifest.permissions)
        if perms.contains("project"), let p = project { env["CLAUDE_PET_PROJECT"] = p.path; env["CLAUDE_PET_PROJECT_NAME"] = p.name }
        if let e = event { env["CLAUDE_PET_EVENT"] = e }
        for s in plugin.manifest.settings {
            let v = settings[s.key] ?? s.defaultValue ?? (s.type == "toggle" ? "false" : "")
            env["CLAUDE_PET_SETTING_" + s.key.uppercased()] = String(v.prefix(500))
        }
        return env
    }

    /// Estado efectivo segun lo aprobado: un plugin que pide permisos nuevos queda parado hasta que se acepten.
    static func status(_ p: LoadedPlugin, state: PluginState?) -> PluginStatus {
        guard p.problems.isEmpty else { return .invalid }
        guard let s = state, s.enabled else { return .disabled }
        let fresh = p.manifest.permissions.filter { !s.approved.contains($0) }
        return fresh.isEmpty ? .enabled : .needsApproval(fresh)
    }
}

struct PluginResult: Equatable {
    var status: Int32 = -1
    var stdout = ""
    var stderr = ""
    var timedOut = false
    var launchError: String?
    var ok: Bool { launchError == nil && !timedOut && status == 0 }
}

/// Estado compartido entre los hilos de lectura, el de fin de proceso y el del plazo; todo bajo un unico candado.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var timedOutFlag = false, done = false
    let maxOut: Int
    init(maxOut: Int) { self.maxOut = maxOut }

    func addOut(_ d: Data) { lock.lock(); if out.count < maxOut { out.append(d.prefix(maxOut - out.count)) }; lock.unlock() }
    func addErr(_ d: Data) { lock.lock(); if err.count < 4_096 { err.append(d.prefix(4_096 - err.count)) }; lock.unlock() }
    func markTimedOutIfAlive(_ alive: Bool) -> Bool { lock.lock(); defer { lock.unlock() }; guard alive, !done else { return false }; timedOutFlag = true; return true }
    /// Devuelve el resultado la primera vez; despues nil (el proceso puede avisar dos veces si falla al arrancar).
    func finish(status: Int32, tailOut: Data) -> PluginResult? {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return nil }
        done = true
        if out.count < maxOut { out.append(tailOut.prefix(maxOut - out.count)) }
        return PluginResult(status: status, stdout: String(decoding: out, as: UTF8.self), stderr: String(decoding: err, as: UTF8.self), timedOut: timedOutFlag, launchError: nil)
    }
    func failLaunch() -> Bool { lock.lock(); defer { lock.unlock() }; guard !done else { return false }; done = true; return true }
}

/// Lanza un ejecutable con tiempo y salida limitados.
enum PluginRunner {
    static let timeout: TimeInterval = 15
    static let maxOutput = 64 * 1024

    static func run(executable: URL, args: [String], env: [String: String], cwd: URL, stdin: Data? = nil, timeout: TimeInterval = PluginRunner.timeout, maxOutput: Int = PluginRunner.maxOutput) async -> PluginResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = executable; p.arguments = args; p.environment = env; p.currentDirectoryURL = cwd
            let out = Pipe(), err = Pipe(), inp = Pipe()
            p.standardOutput = out; p.standardError = err
            p.standardInput = stdin == nil ? FileHandle.nullDevice : inp
            let state = RunState(maxOut: maxOutput)
            out.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if d.isEmpty { h.readabilityHandler = nil } else { state.addOut(d) } }
            err.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if d.isEmpty { h.readabilityHandler = nil } else { state.addErr(d) } }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                if let r = state.finish(status: proc.terminationStatus, tailOut: out.fileHandleForReading.availableData) { cont.resume(returning: r) }
            }
            do { try p.run() } catch {
                if state.failLaunch() { cont.resume(returning: PluginResult(launchError: error.localizedDescription)) }
                return
            }
            if let stdin { try? inp.fileHandleForWriting.write(contentsOf: stdin); try? inp.fileHandleForWriting.close() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard state.markTimedOutIfAlive(p.isRunning) else { return }
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
            }
        }
    }
}
