import Foundation
import Darwin

/// Hace el ensayo de verdad: clona, ejecuta en la caja de arena, compara y borra la copia.
/// Todo es bloqueante y esta pensado para llamarse fuera del hilo principal (`rehearse` asincrono lo hace).
enum RehearsalRunner {
    static let timeout: TimeInterval = 20
    static let maxOutput = 16 * 1024

    /// Carpeta de trabajo. Tiene que estar en el mismo volumen que el proyecto para que el clon sea instantaneo.
    static var baseDir: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_REHEARSAL_DIR"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/Library/Caches/claude-pet/ensayo"
    }

    static func rehearse(command: String, cwd: String, timeout: TimeInterval = RehearsalRunner.timeout) async -> Result<Rehearsal.Report, Rehearsal.Failure> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: run(command: command, cwd: cwd, timeout: timeout)) }
        }
    }

    static func run(command: String, cwd: String, timeout: TimeInterval = RehearsalRunner.timeout, base: String = RehearsalRunner.baseDir) -> Result<Rehearsal.Report, Rehearsal.Failure> {
        let fm = FileManager.default
        let realCwd = realPath(cwd)
        var isDir: ObjCBool = false
        guard !cwd.isEmpty, fm.fileExists(atPath: realCwd, isDirectory: &isDir), isDir.boolValue else { return .failure(.noProject) }
        // `root(for:)` normaliza la ruta al estilo de Foundation (sin /private): se vuelve a pedir la real
        let root = realPath(Rehearsal.root(for: realCwd))
        guard realCwd == root || realCwd.hasPrefix(root + "/") else { return .failure(.noProject) }
        guard Rehearsal.isSafeRoot(root) else { return .failure(.unsafeRoot) }

        // sin red un comando de red no llega a hacer su trabajo: no se ejecuta y se avisa al instante, en vez de esperar al plazo
        if Rehearsal.needsNetwork(command) { return .failure(.needsNetwork) }

        sweep(base: base)
        let work = base + "/" + UUID().uuidString
        let clone = work + "/p", home = work + "/home", tmp = work + "/tmp"
        do {
            try fm.createDirectory(atPath: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return .failure(.cannotClone(Int32((error as NSError).code))) }
        defer { discard(work, base: base) }

        // clon APFS: copia en escritura, no duplica datos
        guard clonefile(root, clone, 0) == 0 else { return .failure(.cannotClone(errno)) }
        let realClone = realPath(clone)
        let sub = realCwd == root ? "" : String(realCwd.dropFirst(root.count + 1))
        let runDir = sub.isEmpty ? realClone : realClone + "/" + sub

        let hasGit = fm.fileExists(atPath: realClone + "/.git")
        let gitBefore = hasGit ? gitState(realClone) : nil
        guard let before = Rehearsal.snapshot(root: realClone) else { return .failure(.tooBig) }

        var rewritten = Rehearsal.rewrite(command: command, project: root, clone: realClone)
        // la misma carpeta escrita por otro camino (un enlace simbolico como /tmp) tambien apunta a la copia
        let typed = (cwd as NSString).standardizingPath
        if typed != realCwd { rewritten = Rehearsal.rewrite(command: rewritten, project: typed, clone: runDir) }
        let realWork = realPath(work)
        let writable = [realWork] + userScratchDirs().filter { !root.hasPrefix($0) }
        let args = ["/usr/bin/sandbox-exec", "-p", Rehearsal.profile(writable: writable), "/bin/zsh", "-f", "-c", rewritten]
        let started = Date()
        guard let r = spawn(args: args, env: environment(home: home, tmp: tmp), cwd: runDir, timeout: timeout, maxOutput: maxOutput) else { return .failure(.cannotLaunch) }
        let seconds = Date().timeIntervalSince(started)
        let output = String(decoding: r.output, as: UTF8.self)
        if r.status == 71 && output.contains("sandbox_apply") { return .failure(.sandboxUnavailable) }

        guard let after = Rehearsal.snapshot(root: realClone) else { return .failure(.tooBig) }
        var report = Rehearsal.Report()
        report.changes = Rehearsal.diff(before: before, after: after)
        // un archivo reescrito con el mismo contenido (git lo hace al restaurar el arbol sobre un clon) no es un cambio:
        // se compara con el original, que solo se lee
        report.changes.modified.removeAll { path in
            guard let b = before[path], let a = after[path], !a.isDir, a.size == b.size, a.mode == b.mode, a.size <= 8 * 1024 * 1024 else { return false }
            return fm.contentsEqual(atPath: realClone + "/" + path, andPath: root + "/" + path)
        }
        report.gitBefore = gitBefore
        report.gitAfter = hasGit ? gitState(realClone) : nil
        report.homeWrites = (Rehearsal.snapshot(root: home, limit: 5_000) ?? [:]).filter { !$0.value.isDir && !Rehearsal.isHomeNoise($0.key) }.keys.sorted()
        report.exitCode = r.status
        report.timedOut = r.timedOut
        report.seconds = seconds
        report.usesNetwork = Rehearsal.needsNetwork(command) || Rehearsal.outputSaysNetwork(output)
        report.blockedOutside = Rehearsal.outputSaysBlocked(output) && !Rehearsal.outputSaysNetwork(output)
        report.outputTail = tail(output.replacingOccurrences(of: realClone, with: root).replacingOccurrences(of: home, with: "~"), lines: 12)
        return .success(report)
    }

    // MARK: piezas

    /// Ruta real segun el nucleo (`realpath`), que es la que compara la caja de arena. Foundation quita `/private` y no sirve aqui.
    static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return (path as NSString).standardizingPath }
        defer { free(r) }
        return String(cString: r)
    }

    /// Carpeta de cache del usuario (`/var/folders/.../C`): compiladores y xcrun escriben ahi y fallan sin ella.
    /// La temporal del usuario no se abre: el comando recibe una propia en `TMPDIR`.
    private static func userScratchDirs() -> [String] {
        [_CS_DARWIN_USER_CACHE_DIR].compactMap { name -> String? in
            var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
            guard confstr(name, &buf, buf.count) > 0 else { return nil }
            let p = realPath(String(cString: buf))
            return p.count > 12 ? p : nil
        }
    }

    /// Entorno minimo: carpeta personal y temporal de mentira, y la ruta de busqueda habitual de un desarrollador.
    /// La configuracion global de git se lee de la real (solo lectura) para que un commit ensayado tenga autor.
    static func environment(home: String, tmp: String, realHome: String = NSHomeDirectory(), inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var path = (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", realHome + "/.local/bin", realHome + "/.cargo/bin", realHome + "/.bun/bin",
                      realHome + "/.volta/bin", realHome + "/go/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !path.contains(extra) { path.append(extra) }
        var env = ["HOME": home, "TMPDIR": tmp + "/", "PATH": path.joined(separator: ":"), "TERM": "dumb", "LANG": inherited["LANG"] ?? "en_US.UTF-8",
                   "USER": NSUserName(), "LOGNAME": NSUserName(), "SHELL": "/bin/zsh", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0",
                   "CI": "1", "NO_COLOR": "1", "CLAUDE_PET_REHEARSAL": "1"]
        let gitconfig = realHome + "/.gitconfig"
        if FileManager.default.fileExists(atPath: gitconfig) { env["GIT_CONFIG_GLOBAL"] = gitconfig }
        return env
    }

    private static func gitState(_ repo: String) -> Rehearsal.GitState? {
        func git(_ a: [String]) -> String {
            let env = ["PATH": "/usr/bin:/bin", "HOME": "/var/empty", "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_NOSYSTEM": "1"]
            guard let r = spawn(args: ["/usr/bin/git", "-C", repo] + a, env: env, cwd: repo, timeout: 8, maxOutput: 256 * 1024) else { return "" }
            return String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let head = git(["rev-parse", "--short", "HEAD"])
        guard !head.isEmpty, !head.contains(" ") else { return Rehearsal.GitState(head: "", branch: git(["symbolic-ref", "--short", "-q", "HEAD"]), dirty: 0) }
        let branch = git(["symbolic-ref", "--short", "-q", "HEAD"])
        let dirty = git(["status", "--porcelain"]).split(separator: "\n").count
        return Rehearsal.GitState(head: head, branch: branch.isEmpty ? L.t("sin rama", "detached") : branch, dirty: dirty)
    }

    private static func tail(_ s: String, lines: Int) -> String {
        let all = s.split(separator: "\n", omittingEmptySubsequences: false)
        return all.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Borra la carpeta de un ensayo. Solo acepta una carpeta con nombre de UUID directamente dentro de `base`.
    static func discard(_ work: String, base: String) {
        let name = (work as NSString).lastPathComponent
        guard (work as NSString).deletingLastPathComponent == base, UUID(uuidString: name) != nil else { return }
        try? FileManager.default.removeItem(atPath: work)
    }

    /// Restos de ensayos que no llegaron a limpiarse (la app se cerro a medias): fuera si tienen mas de una hora.
    static func sweep(base: String, now: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: base) else { return }
        for n in names where UUID(uuidString: n) != nil {
            let p = base + "/" + n
            let made = (try? FileManager.default.attributesOfItem(atPath: p)[.creationDate] as? Date) ?? now
            if now.timeIntervalSince(made) > 3_600 { discard(p, base: base) }
        }
    }

    // MARK: proceso

    struct Spawned {
        var status: Int32
        var timedOut: Bool
        var output: Data
    }

    /// Lanza un proceso en su propio grupo, sin heredar ningun descriptor de la app, con la salida y los errores juntos.
    /// Al agotarse el plazo se mata el grupo entero. Nil si no se pudo lanzar.
    static func spawn(args: [String], env: [String: String], cwd: String, timeout: TimeInterval, maxOutput: Int) -> Spawned? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let rfd = fds[0], wfd = fds[1]

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, wfd, 1)
        posix_spawn_file_actions_adddup2(&actions, wfd, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)

        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for p in argv { free(p) }; for p in envp { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, args[0], &actions, &attr, &argv, &envp)
        close(wfd)
        guard rc == 0 else { close(rfd); return nil }
        defer { close(rfd) }

        var output = Data(), status: Int32 = 0
        var exited = false, eof = false, timedOut = false
        var exitedAt = Date.distantFuture, killAt = Date.distantFuture
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            var pfd = pollfd(fd: rfd, events: Int16(POLLIN), revents: 0)
            if !eof, poll(&pfd, 1, 100) > 0 {
                let n = read(rfd, &buf, buf.count)
                if n > 0 {
                    output.append(contentsOf: buf[0..<n])
                    // se guarda la cola: lo ultimo que dijo es lo que explica como acabo
                    if output.count > maxOutput * 2 { output = output.suffix(maxOutput) }
                } else if n == 0 { eof = true }
            } else if eof { usleep(50_000) }
            let now = Date()
            if !exited {
                var st: Int32 = 0
                if waitpid(pid, &st, WNOHANG) == pid { exited = true; exitedAt = now; status = st }
            }
            if exited && (eof || now.timeIntervalSince(exitedAt) > 0.3) { break }
            if !exited && !timedOut && now > deadline { timedOut = true; kill(-pid, SIGTERM); killAt = now.addingTimeInterval(1) }
            if timedOut && !exited && now > killAt { kill(-pid, SIGKILL); killAt = .distantFuture }
        }
        // lo que quede del grupo (hijos en segundo plano) no sobrevive al ensayo
        kill(-pid, SIGKILL)
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return Spawned(status: code, timedOut: timedOut, output: output.suffix(maxOutput))
    }
}
