import AppKit

/// Descubre, instala y ejecuta plugins. Sin interfaz: se prueba con carpetas temporales.
final class PluginRegistry {
    static let maxPlugins = 30
    static let maxInstallBytes = 5 * 1024 * 1024
    static let maxInstallFiles = 200
    static var defaultRoot: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_PET_PLUGINS"] ?? (NSHomeDirectory() + "/.claude-pet/plugins"))
    }
    static var defaultStatePath: String { ProcessInfo.processInfo.environment["CLAUDE_PET_PLUGIN_STATE"] ?? (NSHomeDirectory() + "/.claude-pet/plugins.json") }

    enum InstallError: Error, Equatable, CustomStringConvertible {
        case noManifest, invalid([String]), exists(String), tooBig, symlink, limit
        var description: String {
            switch self {
            case .noManifest: return "la carpeta no tiene un plugin.json válido"
            case .invalid(let p): return "plugin.json no es válido: " + p.prefix(3).joined(separator: "; ")
            case .exists(let id): return "ya hay un plugin «\(id)»: quítalo antes de instalar otra versión"
            case .tooBig: return "el plugin pesa más de 5 MB o tiene más de 200 archivos"
            case .symlink: return "el plugin contiene enlaces simbólicos, que no se permiten"
            case .limit: return "ya hay demasiados plugins instalados"
            }
        }
    }

    let root: URL
    let statePath: String?
    private(set) var plugins: [LoadedPlugin] = []
    private(set) var states: [String: PluginState] = [:]

    init(root: URL = PluginRegistry.defaultRoot, statePath: String? = PluginRegistry.defaultStatePath) {
        self.root = root; self.statePath = statePath
        loadState(); reload()
    }

    // MARK: descubrimiento

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dirs = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        var out: [LoadedPlugin] = []
        for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(Self.maxPlugins) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("plugin.json")), let decoded = PluginManifest.decode(data) else {
                out.append(LoadedPlugin(manifest: PluginManifest(id: dir.lastPathComponent, name: dir.lastPathComponent, version: "0.0.0", author: "?", description: "sin plugin.json válido"), dir: dir, problems: ["falta plugin.json o no se puede leer"]))
                continue
            }
            var m = decoded
            var problems = m.problems()
            // se registra siempre bajo el nombre de su carpeta: un manifiesto que dice ser otro plugin no puede taparlo
            if m.id != dir.lastPathComponent { problems.append("la carpeta debe llamarse como el id (\(m.id))"); m.id = dir.lastPathComponent }
            // todo ejecutable declarado debe cumplir las reglas de seguridad
            for run in m.actions.map { $0.run } + Array(m.events.values) where PluginSecurity.resolveExecutable(run, in: dir) == nil {
                problems.append("«\(run)» no es un ejecutable seguro (debe estar dentro del plugin, con permiso de ejecución y sin escritura para otros)")
            }
            out.append(LoadedPlugin(manifest: m, dir: dir, problems: Array(Set(problems)).sorted()))
        }
        plugins = out
    }

    func plugin(_ id: String) -> LoadedPlugin? { plugins.first { $0.id == id } }
    func state(_ id: String) -> PluginState { states[id] ?? PluginState() }
    func status(_ id: String) -> PluginStatus { plugin(id).map { PluginSecurity.status($0, state: states[id]) } ?? .invalid }

    // MARK: estado

    private func loadState() {
        guard let path = statePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 256 * 1024,
              let decoded = try? JSONDecoder().decode([String: PluginState].self, from: data) else { return }
        states = decoded.filter { $0.key.range(of: "^[a-z0-9][a-z0-9-]{1,39}$", options: .regularExpression) != nil }
    }

    private func saveState() {
        guard let path = statePath else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder.pretty.encode(states) else { return }
        try? data.write(to: url, options: .atomic); chmod(path, 0o600)
    }

    /// Activar exige que el usuario ya haya visto los permisos: `approving` es su confirmacion.
    @discardableResult
    func setEnabled(_ id: String, _ on: Bool, approving: Bool = false) -> Bool {
        guard let p = plugin(id), p.problems.isEmpty else { return false }
        var s = state(id)
        if on {
            let fresh = p.manifest.permissions.filter { !s.approved.contains($0) }
            guard fresh.isEmpty || approving else { return false }
            s.approved = Array(Set(s.approved + p.manifest.permissions)).sorted(); s.approvedVersion = p.manifest.version
        }
        s.enabled = on
        states[id] = s; saveState()
        return true
    }

    func setSetting(_ id: String, key: String, value: String) {
        guard let p = plugin(id), let def = p.manifest.settings.first(where: { $0.key == key }) else { return }
        var v = String(value.prefix(200))
        if def.type == "toggle" { v = v == "true" ? "true" : "false" }
        if def.type == "choice", !(def.options ?? []).contains(v) { return }
        var s = state(id); s.settings[key] = v; states[id] = s; saveState()
    }

    func settingValue(_ id: String, _ def: PluginSetting) -> String { state(id).settings[def.key] ?? def.defaultValue ?? (def.type == "toggle" ? "false" : "") }

    // MARK: instalacion

    @discardableResult
    func install(from src: URL) throws -> LoadedPlugin {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: src.appendingPathComponent("plugin.json")), let m = PluginManifest.decode(data) else { throw InstallError.noManifest }
        let problems = m.problems()
        guard problems.isEmpty else { throw InstallError.invalid(problems) }
        guard plugins.count < Self.maxPlugins else { throw InstallError.limit }
        let dest = root.appendingPathComponent(m.id)
        guard !fm.fileExists(atPath: dest.path) else { throw InstallError.exists(m.id) }
        var bytes = 0, files = 0
        guard let walker = fm.enumerator(at: src, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) else { throw InstallError.noManifest }
        for case let u as URL in walker {
            let v = try? u.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
            if v?.isSymbolicLink == true { throw InstallError.symlink }
            if v?.isRegularFile == true { files += 1; bytes += v?.fileSize ?? 0 }
            if files > Self.maxInstallFiles || bytes > Self.maxInstallBytes { throw InstallError.tooBig }
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.copyItem(at: src, to: dest)
        // nadie mas que el usuario puede escribir lo instalado
        if let all = fm.enumerator(at: dest, includingPropertiesForKeys: nil) {
            for case let u as URL in all { if let mode = (try? fm.attributesOfItem(atPath: u.path)[.posixPermissions]) as? Int { try? fm.setAttributes([.posixPermissions: mode & ~0o022], ofItemAtPath: u.path) } }
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dest.path)
        reload()
        guard let loaded = plugin(m.id) else { throw InstallError.noManifest }
        return loaded
    }

    func uninstall(_ id: String) {
        guard let p = plugin(id), p.dir.deletingLastPathComponent().resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path else { return }
        try? FileManager.default.removeItem(at: p.dir)
        states[id] = nil; saveState(); reload()
    }

    // MARK: acciones y eventos

    /// Acciones de plugins activos para un sitio ("menu" o "island").
    func actions(place: String) -> [(plugin: LoadedPlugin, action: PluginAction)] {
        plugins.filter { status($0.id) == .enabled }.flatMap { p in p.manifest.actions.filter { ($0.places ?? ["menu"]).contains(place) }.map { (p, $0) } }
    }

    func handlers(for event: PluginEvent) -> [(plugin: LoadedPlugin, executable: URL)] {
        plugins.compactMap { p in
            guard status(p.id) == .enabled, p.manifest.permissions.contains("events"), let run = p.manifest.events[event.rawValue],
                  let exe = PluginSecurity.resolveExecutable(run, in: p.dir) else { return nil }
            return (p, exe)
        }
    }

    func runAction(_ pluginID: String, _ actionID: String, project: (path: String, name: String)?) async -> (result: PluginResult, effects: PluginEffects)? {
        guard status(pluginID) == .enabled, let p = plugin(pluginID), let a = p.manifest.actions.first(where: { $0.id == actionID }),
              let exe = PluginSecurity.resolveExecutable(a.run, in: p.dir) else { return nil }
        if a.needs == "project" && project == nil { return nil }
        PluginSecurity.ensureDataDirectory(pluginID)
        let env = PluginSecurity.environment(plugin: p, settings: state(pluginID).settings, project: project, event: nil)
        let r = await PluginRunner.run(executable: exe, args: a.args ?? [], env: env, cwd: p.dir)
        return (r, PluginEffects.parse(stdout: r.stdout, permissions: Set(p.manifest.permissions)))
    }

    func runEvent(_ event: PluginEvent, plugin p: LoadedPlugin, executable: URL, fields: [String: String], project: (path: String, name: String)?) async -> (result: PluginResult, effects: PluginEffects) {
        let perms = Set(p.manifest.permissions)
        let payload = PluginEvents.payload(event, fields: fields, permissions: perms, project: project)
        PluginSecurity.ensureDataDirectory(p.id)
        let env = PluginSecurity.environment(plugin: p, settings: state(p.id).settings, project: project, event: event.rawValue)
        let r = await PluginRunner.run(executable: executable, args: [], env: env, cwd: p.dir, stdin: payload)
        return (r, PluginEffects.parse(stdout: r.stdout, permissions: perms))
    }
}

/// Lo que ve la interfaz de cada plugin.
struct PluginRow: Identifiable, Equatable {
    let plugin: LoadedPlugin
    let status: PluginStatus
    let state: PluginState
    var id: String { plugin.id }
}

@MainActor
final class PluginHost: ObservableObject {
    @Published private(set) var rows: [PluginRow] = []
    @Published private(set) var toast: String?
    @Published private(set) var lastError: String?
    let registry: PluginRegistry
    private var running: Set<String> = []
    private var lastEvent: [String: Date] = [:]
    private var toastTask: Task<Void, Never>?

    init(registry: PluginRegistry = PluginRegistry()) { self.registry = registry; refresh() }

    func refresh() { rows = registry.plugins.map { PluginRow(plugin: $0, status: registry.status($0.id), state: registry.state($0.id)) } }
    func reload() { registry.reload(); refresh() }

    var hasMenuActions: Bool { !registry.actions(place: "menu").isEmpty }
    func actions(place: String) -> [(plugin: LoadedPlugin, action: PluginAction)] { registry.actions(place: place) }

    // MARK: ajustes de usuario

    /// Pide confirmacion con la lista de permisos antes de activar; es lo que hace de la aprobacion algo explicito.
    func setEnabled(_ id: String, _ on: Bool) {
        guard let p = registry.plugin(id) else { return }
        if on {
            let fresh = p.manifest.permissions.filter { !registry.state(id).approved.contains($0) }
            if !fresh.isEmpty || registry.state(id).approved.isEmpty {
                let alert = NSAlert()
                alert.messageText = "¿activar «\(p.manifest.name)»?"
                let perms = p.manifest.permissions.compactMap { PluginPermission(rawValue: $0)?.title }
                alert.informativeText = "de \(p.manifest.author) · versión \(p.manifest.version)\n\n" + (perms.isEmpty ? "no pide ningún permiso." : "podrá:\n" + perms.map { "• \($0)" }.joined(separator: "\n"))
                    + "\n\nlos plugins se ejecutan con tus mismos privilegios en este Mac: activa solo los de autores en los que confíes."
                alert.addButton(withTitle: "activar"); alert.addButton(withTitle: "cancelar"); alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                registry.setEnabled(id, true, approving: true)
            } else { registry.setEnabled(id, true) }
        } else { registry.setEnabled(id, false) }
        refresh()
    }

    func setSetting(_ id: String, key: String, value: String) { registry.setSetting(id, key: key, value: value); refresh() }
    func uninstall(_ id: String) { registry.uninstall(id); refresh() }

    func install(from url: URL) {
        do { let p = try registry.install(from: url); lastError = nil; show("«\(p.manifest.name)» instalado. actívalo para usarlo.") }
        catch { lastError = (error as? PluginRegistry.InstallError)?.description ?? error.localizedDescription }
        refresh()
    }

    // MARK: ejecucion

    func show(_ text: String) {
        toast = text; toastTask?.cancel()
        toastTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 4_500_000_000); if !Task.isCancelled { self?.toast = nil } }
    }

    private func project() -> (path: String, name: String)? {
        let w = PetStore.shared.mission.workspace
        return w.isEmpty ? nil : (w, (w as NSString).lastPathComponent)
    }

    private func apply(_ r: (result: PluginResult, effects: PluginEffects), name: String) {
        if let c = r.effects.copy { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c, forType: .string) }
        if let u = r.effects.open { NSWorkspace.shared.open(u) }
        if let t = r.effects.toast { show(t) }
        else if r.result.timedOut { show("«\(name)» tardó demasiado y se detuvo") }
        else if !r.result.ok { show("«\(name)» falló" + (r.result.launchError.map { ": \($0)" } ?? " (código \(r.result.status))")) }
    }

    func run(_ pluginID: String, _ action: PluginAction, name: String) {
        if action.needs == "project" && project() == nil { show("abre un proyecto para usar «\(action.title)»"); return }
        guard !running.contains(pluginID) else { show("«\(name)» ya está trabajando"); return }
        running.insert(pluginID)
        let proj = project()
        Task { [weak self] in
            let r = await self?.registry.runAction(pluginID, action.id, project: proj)
            await MainActor.run {
                guard let self else { return }
                self.running.remove(pluginID)
                if let r { self.apply(r, name: name) } else { self.show("«\(name)» no se pudo ejecutar") }
            }
        }
    }

    /// Avisa a los plugins que escuchan este evento. A lo sumo uno cada 2 s por plugin y evento, y uno a la vez por plugin.
    func emit(_ event: PluginEvent, fields: [String: String] = [:]) {
        let handlers = registry.handlers(for: event)
        guard !handlers.isEmpty else { return }
        let proj = project(), now = Date()
        for h in handlers {
            let key = h.plugin.id + "|" + event.rawValue
            if let last = lastEvent[key], now.timeIntervalSince(last) < 2 { continue }
            guard !running.contains(h.plugin.id) else { continue }
            lastEvent[key] = now; running.insert(h.plugin.id)
            Task { [weak self] in
                guard let self else { return }
                let r = await self.registry.runEvent(event, plugin: h.plugin, executable: h.executable, fields: fields, project: proj)
                await MainActor.run { self.running.remove(h.plugin.id); self.apply(r, name: h.plugin.manifest.name) }
            }
        }
    }
}
