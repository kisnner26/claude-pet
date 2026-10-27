import Foundation

/// Abre commitero (el sistema que agrupa cambios en commits atomicos) para el proyecto del agente.
/// commitero es un programa aparte: claude pet solo lo busca y lo lanza; no comparte datos con el.
enum CommiteroLauncher {
    /// Carpetas donde buscar el comando ademas de PATH (una app de la barra de menus hereda un PATH muy corto).
    static func defaultExtraDirectories(home: String) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin"]
    }

    static func searchDirectories(path: String?, home: String, extra: [String]? = nil) -> [String] {
        let extra = extra ?? defaultExtraDirectories(home: home)
        let fromPath = (path ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>(), out: [String] = []
        for d in fromPath + extra where !d.isEmpty && seen.insert(d).inserted { out.append(d) }
        return out
    }

    /// Ruta del ejecutable `commitero`, o nil. `override` (un ajuste del usuario) tiene prioridad si es ejecutable.
    static func find(path: String? = ProcessInfo.processInfo.environment["PATH"], home: String = NSHomeDirectory(),
                     override: String? = nil, extra: [String]? = nil, fileManager: FileManager = .default) -> String? {
        func isExecutableFile(_ p: String) -> Bool {
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: p, isDirectory: &isDir) && !isDir.boolValue && fileManager.isExecutableFile(atPath: p)
        }
        if let override, !override.isEmpty, isExecutableFile(override) { return override }
        for dir in searchDirectories(path: path, home: home, extra: extra) {
            let candidate = dir + "/commitero"
            if isExecutableFile(candidate) { return candidate }
        }
        return nil
    }

    private static var cache: (path: String?, at: Date)?
    /// La busqueda toca el disco; el menu se redibuja a menudo, asi que se recuerda un minuto.
    static func available(now: Date = Date()) -> Bool {
        if let c = cache, now.timeIntervalSince(c.at) < 60 { return c.path != nil }
        let found = find(override: UserDefaults.standard.string(forKey: "commiteroPath"))
        cache = (found, now)
        return found != nil
    }

    /// Solo carpetas absolutas, existentes y que no empiecen con "-" (para que nunca se lea como una opcion).
    static func isLaunchableWorkspace(_ workspace: String, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return workspace.hasPrefix("/") && !workspace.contains("\0") && fileManager.fileExists(atPath: workspace, isDirectory: &isDir) && isDir.boolValue
    }

    static func environmentPath(home: String = NSHomeDirectory()) -> String {
        searchDirectories(path: "/usr/bin:/bin:/usr/sbin:/sbin", home: home).joined(separator: ":")
    }

    /// Lanza commitero para la carpeta. Devuelve false si no existe el comando o la carpeta no es valida.
    @discardableResult
    static func launch(workspace: String, override: String? = nil) -> Bool {
        guard isLaunchableWorkspace(workspace), RestorePoints.isRepo(workspace), let exe = find(override: override ?? UserDefaults.standard.string(forKey: "commiteroPath")) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = [workspace]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = environmentPath()
        p.environment = env
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run(); return true } catch { return false }
    }
}
