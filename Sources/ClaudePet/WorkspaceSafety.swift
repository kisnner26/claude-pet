import Foundation

/// Deteccion de cambios en el proyecto por metadatos: nombres relativos, tamano y fecha.
/// Nunca lee contenido.
enum WorkspaceSafety {
    /// Sin eventos durante tanto tiempo, una sesion "parece bloqueada". Las herramientas largas
    /// (builds, tests) tienen mas margen que el pensamiento.
    static let thinkingStall: TimeInterval = 300
    static let toolStall: TimeInterval = 900
    static let maxFiles = 8_000

    /// Carpetas y archivos generados que no cuentan como "el proyecto cambio".
    static let ignoredDirs: Set<String> = [".git", "node_modules", ".build", "build", "dist", ".next", ".nuxt", "__pycache__",
                                           ".venv", "venv", "target", "DerivedData", "coverage", ".cache", ".gradle", ".idea"]
    static let ignoredSuffixes = [".log", ".tmp", ".swp", ".pyc"]

    static func fingerprint(_ root: String) -> UInt64? {
        guard root.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        let base = url.path.count + 1
        var hash: UInt64 = 1469598103934665603
        var count = 0
        while let file = items.nextObject() as? URL {
            guard let v = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            let name = file.lastPathComponent
            if v.isDirectory == true {
                if ignoredDirs.contains(name) { items.skipDescendants() }
                continue
            }
            if ignoredSuffixes.contains(where: { name.hasSuffix($0) }) { continue }
            count += 1
            if count > maxFiles { return nil }      // un monorepo gigante: se desactiva en vez de escanear siempre
            for byte in file.path.dropFirst(base).utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            hash = (hash ^ UInt64(v.fileSize ?? 0)) &* 1099511628211
            hash = (hash ^ UInt64((v.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000)) &* 1099511628211
        }
        return hash
    }

    // MARK: marcas del bloqueo opcional (las lee hooks/pet-hook.sh)

    private static var petDir: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude-pet") }
    private static var flagURL: URL { petDir.appendingPathComponent("block-on-change") }
    private static func markerURL(_ session: String) -> URL {
        petDir.appendingPathComponent("context-changed/\(session)")
    }
    private static func safe(_ session: String) -> Bool {
        !session.isEmpty && session.count <= 16 && session.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Activa o desactiva el bloqueo opcional: es una bandera que el hook comprueba.
    static func setBlocking(_ on: Bool) {
        if on {
            try? FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: flagURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        } else {
            try? FileManager.default.removeItem(at: flagURL)
            try? FileManager.default.removeItem(at: petDir.appendingPathComponent("context-changed"))
        }
    }

    static func markChanged(session: String) {
        guard safe(session) else { return }
        let url = markerURL(session)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    static func clearMarker(session: String) {
        guard safe(session) else { return }
        try? FileManager.default.removeItem(at: markerURL(session))
    }
}

/// Vigila el proyecto de cada sesion SIN bloquear el hilo principal: los escaneos corren en una cola
/// de baja prioridad, nunca se solapan por sesion, y los resultados obsoletos se descartan.
/// Seguro entre hilos (todo el estado va detras de un candado).
final class WorkspaceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "claudepet.workspace", qos: .utility)
    private var baselines: [String: UInt64] = [:]
    private var generations: [String: Int] = [:]
    private var pending = Set<String>()
    private var changedSet = Set<String>()
    /// Se llama en el hilo principal la primera vez que una sesion cambia.
    var onChange: (@Sendable (String) -> Void)?

    var changed: Set<String> { lock.lock(); defer { lock.unlock() }; return changedSet }

    /// Toma la linea base (al empezar a pensar, o al volver de una herramienta: asi los cambios que
    /// hace la propia sesion no cuentan) y borra un aviso anterior.
    func arm(session: String, workspace: String) {
        lock.lock()
        let g = (generations[session] ?? 0) + 1
        generations[session] = g; baselines[session] = nil; changedSet.remove(session)
        lock.unlock()
        queue.async { [self] in
            let fp = WorkspaceSafety.fingerprint(workspace)
            lock.lock(); defer { lock.unlock() }
            if generations[session] == g, let fp { baselines[session] = fp }
        }
    }

    func check(session: String, workspace: String) {
        lock.lock()
        guard let base = baselines[session], let g = generations[session], !pending.contains(session), !changedSet.contains(session) else {
            lock.unlock(); return
        }
        pending.insert(session)
        lock.unlock()
        queue.async { [self] in
            let cur = WorkspaceSafety.fingerprint(workspace)
            lock.lock()
            pending.remove(session)
            var fire = false
            if generations[session] == g, let cur, cur != base, !changedSet.contains(session) { changedSet.insert(session); fire = true }
            lock.unlock()
            if fire { DispatchQueue.main.async { [self] in onChange?(session) } }
        }
    }

    func forget(session: String) {
        lock.lock()
        baselines[session] = nil; generations[session] = nil; pending.remove(session); changedSet.remove(session)
        lock.unlock()
    }
}
