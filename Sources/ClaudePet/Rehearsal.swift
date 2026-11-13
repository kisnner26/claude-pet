import Foundation
import Darwin

/// Ensayo: antes de aprobar un comando, se ejecuta en una copia instantanea del proyecto (clon APFS, que no ocupa
/// espacio hasta que algo cambia), dentro de una caja de arena sin red y sin escritura fuera de la copia, y se compara
/// la copia antes y despues. El proyecto real no se toca en ningun momento.
///
/// Este archivo es la parte pura (perfil, reescritura del comando, comparacion y texto); `RehearsalRunner` hace el trabajo.
/// Es un ensayo y no una boveda: evita accidentes, no detiene a un programa hecho para escapar.
enum Rehearsal {
    // MARK: huella de un archivo

    /// Lo justo de `lstat` para saber si un archivo es el mismo: tamano, fecha, inodo y modo.
    struct Stamp: Equatable {
        var size: Int64
        var mtime: Int64          // nanosegundos
        var inode: UInt64
        var mode: UInt16
        var isDir: Bool
    }

    /// Recorre `root` y devuelve la huella de cada entrada por su ruta relativa. Nil si pasa de `limit` entradas.
    /// No sigue enlaces simbolicos: un enlace es una entrada mas.
    static func snapshot(root: String, limit: Int = 400_000) -> [String: Stamp]? {
        var out: [String: Stamp] = [:]
        var stack = [""]
        while let rel = stack.popLast() {
            let dirPath = rel.isEmpty ? root : root + "/" + rel
            guard let d = opendir(dirPath) else { continue }
            defer { closedir(d) }
            while let e = readdir(d) {
                let name = withUnsafePointer(to: &e.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(e.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let r = rel.isEmpty ? name : rel + "/" + name
                var st = stat()
                guard lstat(root + "/" + r, &st) == 0 else { continue }
                let isDir = (st.st_mode & S_IFMT) == S_IFDIR
                out[r] = Stamp(size: Int64(st.st_size), mtime: Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec),
                               inode: UInt64(st.st_ino), mode: UInt16(st.st_mode), isDir: isDir)
                if out.count > limit { return nil }
                if isDir { stack.append(r) }
            }
        }
        return out
    }

    // MARK: comparacion

    struct Changes: Equatable {
        var created: [String] = []
        var modified: [String] = []
        var deleted: [String] = []
        /// Entradas que cambiaron dentro de `.git` (objetos, indice, referencias): se cuentan, no se listan.
        var gitInternal = 0
        /// Bytes de mas (o de menos) contando solo archivos.
        var bytesDelta: Int64 = 0

        var isEmpty: Bool { created.isEmpty && modified.isEmpty && deleted.isEmpty && gitInternal == 0 }
        var total: Int { created.count + modified.count + deleted.count }
    }

    private static func inGit(_ p: String) -> Bool { p == ".git" || p.hasPrefix(".git/") }

    /// Lo que cambio entre dos recorridos. Las carpetas solo aparecen cuando son el cambio en si (una carpeta vacia
    /// creada o borrada); si dentro hay archivos creados o borrados, basta con ellos. Las rutas de carpeta acaban en "/".
    static func diff(before: [String: Stamp], after: [String: Stamp]) -> Changes {
        var c = Changes()
        var createdDirs: [String] = [], deletedDirs: [String] = []
        for (path, a) in after {
            guard let b = before[path] else {
                if inGit(path) { c.gitInternal += 1; continue }
                if a.isDir { createdDirs.append(path) } else { c.created.append(path); c.bytesDelta += a.size }
                continue
            }
            if a.isDir && b.isDir { continue }
            if a != b {
                if inGit(path) { c.gitInternal += 1; continue }
                c.modified.append(path)
                c.bytesDelta += (a.isDir ? 0 : a.size) - (b.isDir ? 0 : b.size)
            }
        }
        for (path, b) in before where after[path] == nil {
            if inGit(path) { c.gitInternal += 1; continue }
            if b.isDir { deletedDirs.append(path) } else { c.deleted.append(path); c.bytesDelta -= b.size }
        }
        c.created += lonely(dirs: createdDirs, files: c.created)
        c.deleted += lonely(dirs: deletedDirs, files: c.deleted)
        c.created.sort(); c.modified.sort(); c.deleted.sort()
        return c
    }

    /// Carpetas que no quedan explicadas por un archivo de la lista: se devuelve solo la mas alta de cada rama.
    private static func lonely(dirs: [String], files: [String]) -> [String] {
        var covered = Set<String>()
        for f in files {
            var p = f
            while let slash = p.lastIndex(of: "/") { p = String(p[..<slash]); if !covered.insert(p).inserted { break } }
        }
        let empty = dirs.filter { !covered.contains($0) }.sorted()
        var kept: [String] = []
        for d in empty where !kept.contains(where: { d.hasPrefix($0) }) { kept.append(d + "/") }
        return kept
    }

    /// Lista corta para mostrar: si hay muchas rutas se agrupan por su primera carpeta («build/ (214)»).
    static func grouped(_ paths: [String], max: Int = 6) -> [String] {
        guard paths.count > max else { return paths }
        var counts: [String: Int] = [:], order: [String] = []
        for p in paths {
            let key = p.firstIndex(of: "/").map { String(p[...$0]) } ?? p
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        let ranked = order.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
        var out = ranked.prefix(max - 1).map { k -> String in (counts[k] ?? 1) > 1 || k.hasSuffix("/") ? "\(k) (\(counts[k] ?? 1))" : k }
        let rest = ranked.dropFirst(max - 1).reduce(0) { $0 + (counts[$1] ?? 0) }
        if rest > 0 { out.append(L.t("y \(rest) más", "and \(rest) more")) }
        return out
    }

    // MARK: raiz del proyecto

    /// La carpeta que se clona: la raiz del repositorio que contiene a `cwd` (para que git funcione en la copia) o `cwd` si no hay.
    /// Nunca sube hasta la carpeta personal ni mas arriba.
    static func root(for cwd: String, home: String = NSHomeDirectory(), exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        var dir = (cwd as NSString).standardizingPath
        let start = dir
        while isSafeRoot(dir, home: home) {
            if exists(dir + "/.git") { return dir }
            let up = (dir as NSString).deletingLastPathComponent
            if up == dir { break }
            dir = up
        }
        return start
    }

    /// Una carpeta personal entera, la raiz del disco o algo que las contenga no se ensaya: clonarlas no tiene sentido.
    static func isSafeRoot(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let p = (path as NSString).standardizingPath, h = (home as NSString).standardizingPath
        guard p.hasPrefix("/"), p != "/", p != h, !h.hasPrefix(p + "/") else { return false }
        return p.split(separator: "/").count >= 2
    }

    // MARK: comando

    /// Sustituye la ruta absoluta del proyecto por la de la copia, para que `cd /ruta/del/proyecto && ...` actue sobre la copia.
    /// Solo en limite de ruta: `/a/proyecto-2` no se toca al ensayar `/a/proyecto`.
    static func rewrite(command: String, project: String, clone: String) -> String {
        guard !project.isEmpty, project != "/" else { return command }
        var out = "", rest = Substring(command)
        while let r = rest.range(of: project) {
            let next = r.upperBound < rest.endIndex ? rest[r.upperBound] : nil
            let boundary = next.map { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") } ?? true
            out += rest[..<r.lowerBound]
            out += boundary ? clone : project
            rest = rest[r.upperBound...]
        }
        return out + rest
    }

    /// Comandos cuyo efecto depende de internet: el ensayo corre sin red, asi que su resultado no dice lo que pasara de verdad.
    static func needsNetwork(_ command: String) -> Bool {
        let padded = " " + command.replacingOccurrences(of: "\n", with: " ; ").replacingOccurrences(of: "\t", with: " ") + " "
        let starts = ["curl", "wget", "ssh", "scp", "rsync", "sftp", "ftp", "brew", "gh", "docker", "vercel", "nc", "ping", "telnet"]
        let phrases = ["npm install", "npm i", "npm ci", "npm publish", "npm update", "pnpm install", "pnpm add", "pnpm i", "yarn install", "yarn add",
                       "bun install", "bun add", "pip install", "pip3 install", "pipx install", "uv pip", "uv sync", "poetry install", "cargo install",
                       "cargo fetch", "cargo update", "gem install", "bundle install", "go get", "go mod download", "composer install", "composer require",
                       "git push", "git pull", "git fetch", "git clone", "git ls-remote", "swift package resolve", "swift package update", "pod install", "npx", "bunx"]
        for sep in [" ", ";", "&", "|", "(", "`"] {
            for s in starts where padded.contains(sep + s + " ") { return true }
            for p in phrases where padded.contains(sep + p + " ") { return true }
        }
        return false
    }

    /// Pistas en la salida de que el comando quiso salir a la red y no pudo.
    static func outputSaysNetwork(_ output: String) -> Bool {
        let low = output.lowercased()
        return ["could not resolve host", "enotfound", "eai_again", "network is unreachable", "getaddrinfo", "nodename nor servname",
                "failed to connect", "connection refused", "no route to host", "network request failed", "unable to access 'http",
                "temporary failure in name resolution", "couldn't connect to server", "socket: operation not permitted", "connect eperm"].contains { low.contains($0) }
    }

    /// Pistas de que quiso escribir fuera de la copia y la caja de arena lo paro.
    static func outputSaysBlocked(_ output: String) -> Bool {
        let low = output.lowercased()
        return low.contains("operation not permitted") || low.contains("read-only file system") || low.contains("eperm")
    }

    // MARK: caja de arena

    private static func sb(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// Perfil de `sandbox-exec`: todo permitido para leer y calcular; nada de red (tampoco sockets locales), nada de abrir apps ni
    /// hablarles, nada de preferencias ni portapapeles, y escribir solo en las carpetas dadas.
    static func profile(writable: [String]) -> String {
        let subpaths = writable.map { "(subpath \(sb($0)))" }.joined(separator: " ")
        return """
        (version 1)
        (allow default)
        (deny network*)
        (deny appleevent-send)
        (deny lsopen)
        (deny process-exec (literal "/usr/bin/osascript") (literal "/usr/bin/open") (literal "/usr/bin/shortcuts") (literal "/usr/bin/automator") (literal "/bin/launchctl") (literal "/usr/bin/defaults") (literal "/usr/bin/security") (literal "/usr/bin/sudo") (literal "/usr/bin/su"))
        (deny mach-lookup (global-name "com.apple.coreservices.appleevents") (global-name "com.apple.coreservices.launchservicesd") (global-name "com.apple.lsd.mapdb") (global-name "com.apple.lsd.open") (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent") (global-name "com.apple.pasteboard.1"))
        (deny file-write*)
        (allow file-write* \(subpaths) (literal "/dev/null") (literal "/dev/zero") (literal "/dev/dtracehelper") (regex #"^/dev/tty") (regex #"^/dev/fd/"))
        """
    }

    // MARK: ruido de la carpeta personal

    /// Registros, cachés e historiales que casi cualquier herramienta escribe en la carpeta personal (ruta relativa a `~`).
    /// No son lo que el usuario quiere saber de un comando: se descartan del informe.
    static func isHomeNoise(_ path: String) -> Bool {
        let prefixes = [".npm/_logs/", ".npm/_cacache/", ".npm/_update-notifier-last-checked", ".cache/", "Library/Caches/", "Library/Logs/",
                        ".zsh_sessions/", ".yarn/cache/", ".bun/install/cache/", ".cargo/registry/cache/", ".gradle/caches/"]
        let names = [".zsh_history", ".bash_history", ".node_repl_history", ".lesshst", ".python_history", ".viminfo", ".zcompdump"]
        if prefixes.contains(where: { path.hasPrefix($0) }) { return true }
        return names.contains { path == $0 || path.hasPrefix($0 + "-") || path.hasPrefix($0 + ".") }
    }

    // MARK: informe

    struct GitState: Equatable {
        var head: String
        var branch: String
        var dirty: Int
    }

    struct Report: Equatable {
        var changes = Changes()
        /// Lo que escribio en la carpeta personal de mentira (rutas relativas a `~`).
        var homeWrites: [String] = []
        var gitBefore: GitState?
        var gitAfter: GitState?
        var exitCode: Int32 = 0
        var timedOut = false
        var seconds: Double = 0
        var usesNetwork = false
        var blockedOutside = false
        /// Cola de la salida del comando, con la ruta de la copia ya cambiada por la del proyecto.
        var outputTail = ""
    }

    enum Failure: Error, Equatable {
        case noProject, unsafeRoot, cannotClone(Int32), tooBig, sandboxUnavailable, cannotLaunch, needsNetwork

        var text: String {
            switch self {
            case .noProject: return L.t("no hay carpeta de proyecto que ensayar", "there is no project folder to rehearse")
            case .unsafeRoot: return L.t("no se ensaya sobre tu carpeta personal ni sobre el disco entero", "your home folder or the whole disk can't be rehearsed")
            case .cannotClone(let e): return L.t("no se pudo copiar el proyecto (código \(e)): hace falta un disco APFS", "the project could not be cloned (code \(e)): an APFS disk is required")
            case .tooBig: return L.t("el proyecto es demasiado grande para ensayarlo", "the project is too large to rehearse")
            case .sandboxUnavailable: return L.t("la caja de arena no está disponible aquí", "the sandbox is not available here")
            case .needsNetwork: return L.t("usa la red y el ensayo corre sin ella: no se puede saber qué haría", "it uses the network and the rehearsal runs without it: it can't tell what it would do")
            case .cannotLaunch: return L.t("no se pudo lanzar el comando", "the command could not be launched")
            }
        }
    }

    private static func count(_ n: Int, _ oneEs: String, _ manyEs: String, _ oneEn: String, _ manyEn: String) -> String {
        L.t("\(n) \(n == 1 ? oneEs : manyEs)", "\(n) \(n == 1 ? oneEn : manyEn)")
    }

    /// Una frase con lo esencial, en condicional: es lo que pasaria, no lo que paso.
    static func headline(_ r: Report) -> String {
        let c = r.changes
        var parts: [String] = []
        if !c.deleted.isEmpty { parts.append(L.t("borraría ", "would delete ") + count(c.deleted.count, "archivo", "archivos", "file", "files")) }
        if !c.modified.isEmpty { parts.append(L.t("cambiaría ", "would change ") + count(c.modified.count, "archivo", "archivos", "file", "files")) }
        if !c.created.isEmpty { parts.append(L.t("crearía ", "would create ") + count(c.created.count, "archivo", "archivos", "file", "files")) }
        if let b = r.gitBefore, let a = r.gitAfter {
            if b.branch != a.branch { parts.append(L.t("cambiaría de rama: \(b.branch) → \(a.branch)", "would switch branch: \(b.branch) → \(a.branch)")) }
            else if b.head != a.head { parts.append(L.t("movería HEAD: \(b.head) → \(a.head)", "would move HEAD: \(b.head) → \(a.head)")) }
            if a.dirty < b.dirty { parts.append(L.t("descartaría ", "would discard ") + count(b.dirty - a.dirty, "cambio sin commitear", "cambios sin commitear", "uncommitted change", "uncommitted changes")) }
        }
        if parts.isEmpty && c.gitInternal > 0 { parts.append(L.t("solo tocaría el interior de .git", "would only touch .git internals")) }
        if !r.homeWrites.isEmpty { parts.append(L.t("escribiría en tu carpeta personal", "would write to your home folder")) }
        // sin red y sin cambios no hay nada que contar: decir "no cambiaria nada" seria enganar
        if parts.isEmpty && r.usesNetwork { return L.t("Sin red no llega a hacer nada: no se puede saber", "Without the network it does nothing: can't tell") }
        if parts.isEmpty { parts.append(L.t("no cambiaría ningún archivo", "would not change any file")) }
        var s = parts.joined(separator: ", ")
        s = s.prefix(1).uppercased() + s.dropFirst()
        return s
    }

    /// Como termino: bien, con error o cortado por tiempo.
    static func outcome(_ r: Report) -> String {
        let secs = String(format: "%.1f s", r.seconds)
        if r.timedOut { return L.t("se cortó a los \(secs): no terminó", "cut off at \(secs): it did not finish") }
        if r.exitCode == 0 { return L.t("terminó bien en \(secs)", "finished fine in \(secs)") }
        return L.t("falló con código \(r.exitCode) en \(secs)", "failed with code \(r.exitCode) in \(secs)")
    }

    /// Avisos que cambian cuanto fiarse del ensayo.
    static func caveats(_ r: Report) -> [String] {
        var out: [String] = []
        if r.usesNetwork { out.append(L.t("usa la red y el ensayo corre sin ella: el resultado real puede ser distinto", "it uses the network and the rehearsal runs without it: the real result may differ")) }
        if r.blockedOutside { out.append(L.t("quiso escribir fuera del proyecto y se le impidió", "it tried to write outside the project and was stopped")) }
        if r.timedOut { out.append(L.t("los cambios son los de antes de cortarlo", "the changes are those made before the cut-off")) }
        return out
    }

    /// Informe completo en texto, para la terminal y para copiar.
    static func text(_ r: Report) -> String {
        var lines = [headline(r), outcome(r)]
        func block(_ title: String, _ sign: String, _ paths: [String]) {
            guard !paths.isEmpty else { return }
            lines.append("")
            lines.append("\(title) (\(paths.count))")
            lines += grouped(paths, max: 10).map { "  \(sign) \($0)" }
        }
        block(L.t("borraría", "would delete"), "-", r.changes.deleted)
        block(L.t("cambiaría", "would change"), "~", r.changes.modified)
        block(L.t("crearía", "would create"), "+", r.changes.created)
        block(L.t("en tu carpeta personal", "in your home folder"), "+", r.homeWrites.map { "~/" + $0 })
        if r.changes.gitInternal > 0 { lines += ["", L.t("dentro de .git: \(r.changes.gitInternal) entradas", "inside .git: \(r.changes.gitInternal) entries")] }
        if r.changes.bytesDelta != 0 {
            let f = ByteCountFormatter.string(fromByteCount: abs(r.changes.bytesDelta), countStyle: .file)
            lines.append(r.changes.bytesDelta < 0 ? L.t("liberaría \(f)", "would free \(f)") : L.t("ocuparía \(f) más", "would use \(f) more"))
        }
        let notes = caveats(r)
        if !notes.isEmpty { lines.append(""); lines += notes.map { "! " + $0 } }
        return lines.joined(separator: "\n")
    }
}
