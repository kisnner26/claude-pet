import Foundation

/// `ClaudePet --selftest-rehearsal`: el ensayo de comandos, primero la parte pura y luego de verdad sobre un proyecto temporal.
enum RehearsalSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let saved = L.current
        L.current = .es
        defer { L.current = saved }

        // MARK: comparacion
        func f(_ size: Int64, _ ino: UInt64, mtime: Int64 = 1) -> Rehearsal.Stamp { .init(size: size, mtime: mtime, inode: ino, mode: 0o100644, isDir: false) }
        func d(_ ino: UInt64) -> Rehearsal.Stamp { .init(size: 0, mtime: 1, inode: ino, mode: 0o040755, isDir: true) }
        let before: [String: Rehearsal.Stamp] = ["a.txt": f(4, 1), "build": d(2), "build/x.o": f(100, 3), "build/y.o": f(50, 4), "vacia": d(5),
                                                 ".git": d(6), ".git/index": f(10, 7), "src": d(8), "src/m.swift": f(20, 9)]
        var after = before
        after["a.txt"] = f(9, 1, mtime: 2)
        after["build"] = nil; after["build/x.o"] = nil; after["build/y.o"] = nil; after["vacia"] = nil
        after["nuevo.txt"] = f(6, 20); after["dir"] = d(21); after["dir/sub"] = d(22); after["out"] = d(23); after["out/r.txt"] = f(1, 24)
        after[".git/index"] = f(12, 7, mtime: 3); after[".git/objects"] = d(25)
        let c = Rehearsal.diff(before: before, after: after)
        check("lo creado: archivos y solo la carpeta vacia mas alta", c.created == ["dir/", "nuevo.txt", "out/r.txt"])
        check("lo cambiado", c.modified == ["a.txt"])
        check("lo borrado: los archivos explican su carpeta; la vacia sale sola", c.deleted == ["build/x.o", "build/y.o", "vacia/"])
        check("el interior de .git se cuenta y no se lista", c.gitInternal == 2 && !c.created.contains { $0.hasPrefix(".git") } && !c.modified.contains { $0.hasPrefix(".git") })
        check("los bytes cuentan lo creado, lo borrado y lo que crecio", c.bytesDelta == 6 + 1 + (9 - 4) - 150)
        check("sin cambios no hay nada", Rehearsal.diff(before: before, after: before).isEmpty)
        var replaced = before; replaced["a.txt"] = f(4, 99)
        check("un archivo sustituido por otro igual de grande cuenta como cambiado", Rehearsal.diff(before: before, after: replaced).modified == ["a.txt"])
        var moded = before; moded["a.txt"]?.mode = 0o100755
        check("un cambio de permisos cuenta", Rehearsal.diff(before: before, after: moded).modified == ["a.txt"])

        // MARK: agrupar
        let many = (0..<214).map { "build/o\($0).o" } + ["a.txt", "node_modules/x/1.js", "node_modules/x/2.js"]
        let g = Rehearsal.grouped(many, max: 6)
        check("muchas rutas se agrupan por carpeta, la mayor primero", g.first == "build/ (214)" && g.contains("node_modules/ (2)") && g.contains("a.txt") && g.count == 3)
        check("pocas rutas van tal cual", Rehearsal.grouped(["a", "b/c"], max: 6) == ["a", "b/c"])
        let wide = (0..<20).map { "d\($0)/f" }
        check("lo que no cabe se resume", Rehearsal.grouped(wide, max: 4).count == 4 && Rehearsal.grouped(wide, max: 4).last == "y 17 más")

        // MARK: raiz
        let fakeHome = "/Users/ana"
        check("la raiz es el repositorio que contiene la carpeta", Rehearsal.root(for: "/Users/ana/code/app/src/ui", home: fakeHome, exists: { $0 == "/Users/ana/code/app/.git" }) == "/Users/ana/code/app")
        check("sin repositorio la raiz es la propia carpeta", Rehearsal.root(for: "/Users/ana/code/app/src", home: fakeHome, exists: { _ in false }) == "/Users/ana/code/app/src")
        check("un .git en la carpeta personal no convierte la carpeta personal en raiz", Rehearsal.root(for: "/Users/ana/code/app", home: fakeHome, exists: { $0 == "/Users/ana/.git" }) == "/Users/ana/code/app")
        check("la carpeta personal, sus ancestros y el disco no se ensayan",
              !Rehearsal.isSafeRoot("/Users/ana", home: fakeHome) && !Rehearsal.isSafeRoot("/Users", home: fakeHome) && !Rehearsal.isSafeRoot("/", home: fakeHome) && !Rehearsal.isSafeRoot("relativa/x", home: fakeHome))
        check("un proyecto normal si", Rehearsal.isSafeRoot("/Users/ana/code/app", home: fakeHome) && Rehearsal.isSafeRoot("/tmp/x", home: fakeHome))

        // MARK: comando
        check("la ruta del proyecto se cambia por la de la copia", Rehearsal.rewrite(command: "cd /a/proj && rm -rf /a/proj/build", project: "/a/proj", clone: "/c/p") == "cd /c/p && rm -rf /c/p/build")
        check("un proyecto vecino con el mismo prefijo no se toca", Rehearsal.rewrite(command: "ls /a/proj-2 /a/proj.bak /a/proj2 '/a/proj'", project: "/a/proj", clone: "/c/p") == "ls /a/proj-2 /a/proj.bak /a/proj2 '/c/p'")
        check("sin la ruta no cambia nada", Rehearsal.rewrite(command: "make clean", project: "/a/proj", clone: "/c/p") == "make clean")
        check("los comandos de red se reconocen", ["curl -s https://x.dev", "cd a && npm install", "git push origin main", "FOO=1 pip install x", "make && gh pr create", "(brew update)"].allSatisfy(Rehearsal.needsNetwork))
        check("los que no usan red no", !["rm -rf build", "git commit -m listo", "swift build", "echo curling", "git status", "npm test", "sshd-config --help"].contains(where: Rehearsal.needsNetwork))
        check("la salida delata un intento de red", Rehearsal.outputSaysNetwork("curl: (6) Could not resolve host: example.com") && !Rehearsal.outputSaysNetwork("todo bien"))

        // MARK: perfil
        let profile = Rehearsal.profile(writable: ["/c/p", "/c/con \"comillas\"\\y"])
        check("el perfil niega red, apps y escritura, y abre solo lo dado", profile.contains("(deny network*)") && profile.contains("(deny file-write*)") && profile.contains("(subpath \"/c/p\")") && profile.contains("(deny lsopen)"))
        check("las rutas raras se escapan en el perfil", profile.contains("(subpath \"/c/con \\\"comillas\\\"\\\\y\")"))

        // MARK: texto
        var r = Rehearsal.Report()
        r.changes.deleted = (0..<214).map { "build/o\($0).o" }; r.changes.modified = ["a.txt"]; r.changes.bytesDelta = -2_000_000
        r.exitCode = 0; r.seconds = 1.24
        check("el titular va en condicional y cuenta bien", Rehearsal.headline(r) == "Borraría 214 archivos, cambiaría 1 archivo")
        check("como termino", Rehearsal.outcome(r).hasPrefix("terminó bien en 1"))
        r.gitBefore = .init(head: "aaa1111", branch: "main", dirty: 5); r.gitAfter = .init(head: "bbb2222", branch: "main", dirty: 0)
        check("git: mueve HEAD y descarta cambios", Rehearsal.headline(r).contains("movería HEAD: aaa1111 → bbb2222") && Rehearsal.headline(r).contains("descartaría 5 cambios sin commitear"))
        r.gitAfter?.branch = "otra"
        check("git: cambio de rama", Rehearsal.headline(r).contains("cambiaría de rama: main → otra"))
        check("sin cambios lo dice", Rehearsal.headline(Rehearsal.Report()) == "No cambiaría ningún archivo")
        var offline = Rehearsal.Report(); offline.usesNetwork = true; offline.exitCode = 6
        check("sin red y sin cambios no afirma que no pasaria nada", Rehearsal.headline(offline).hasPrefix("Sin red") && RehearsalSeverity.of(offline) == .unknown && RehearsalSeverity.of(Rehearsal.Report()) == .calm)
        check("borrar o descartar trabajo es lo mas serio", RehearsalSeverity.of(r) == .destructive)
        r.usesNetwork = true; r.timedOut = true; r.exitCode = 143
        let text = Rehearsal.text(r)
        check("el informe lleva lista agrupada, espacio y avisos", text.contains("- build/ (214)") && text.contains("~ a.txt") && text.contains("liberaría") && text.contains("! usa la red") && text.contains("se cortó"))
        L.current = .en
        check("en ingles tambien", Rehearsal.headline(r).hasPrefix("Would delete 214 files") && Rehearsal.Failure.tooBig.text.contains("too large"))
        L.current = .es

        // MARK: limpieza
        let tmpBase = NSTemporaryDirectory() + "claudepet-ensayo-\(getpid())"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: tmpBase) }
        let base = tmpBase + "/work"
        let stale = base + "/" + UUID().uuidString, keep = base + "/no-es-uuid"
        try? fm.createDirectory(atPath: stale, withIntermediateDirectories: true); try? fm.createDirectory(atPath: keep, withIntermediateDirectories: true)
        RehearsalRunner.discard(keep, base: base); RehearsalRunner.discard(tmpBase, base: base); RehearsalRunner.discard(base, base: base)
        check("solo se borra una carpeta de ensayo dentro de la base", fm.fileExists(atPath: keep) && fm.fileExists(atPath: base))
        RehearsalRunner.sweep(base: base, now: Date().addingTimeInterval(30))
        check("un resto reciente no se barre", fm.fileExists(atPath: stale))
        RehearsalRunner.sweep(base: base, now: Date().addingTimeInterval(7_200))
        check("un resto de mas de una hora si", !fm.fileExists(atPath: stale) && fm.fileExists(atPath: keep))

        // MARK: de verdad
        let proj = tmpBase + "/proyecto", outside = tmpBase + "/fuera"
        try? fm.createDirectory(atPath: proj + "/build", withIntermediateDirectories: true); try? fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        func write(_ rel: String, _ s: String) { try? s.write(toFile: proj + "/" + rel, atomically: true, encoding: .utf8) }
        write("a.txt", "uno\n"); write("build/x.o", String(repeating: "x", count: 1000)); write("build/y.o", "y")
        let real = RehearsalRunner.realPath(proj)
        func listing() -> [String] { (Rehearsal.snapshot(root: proj) ?? [:]).keys.sorted() }
        let original = listing()
        func rehearse(_ cmd: String, cwd: String? = nil, timeout: TimeInterval = 15) -> Result<Rehearsal.Report, Rehearsal.Failure> {
            RehearsalRunner.run(command: cmd, cwd: cwd ?? proj, timeout: timeout, base: base)
        }

        let first = rehearse("rm -rf build && echo dos >> a.txt && echo hola > nuevo.txt && mkdir -p out/deep")
        if case .failure(.sandboxUnavailable) = first {
            // dentro de otra caja de arena no se puede anidar una: la parte pura ya quedo comprobada
            print("SKIP ensayo real: la caja de arena no se puede anidar en este entorno")
            print(failures == 0 ? "OK ensayo (parte pura)" : "FALLOS: \(failures)")
            return failures == 0
        }
        guard case .success(let one) = first else { check("el ensayo corre: \(first)", false); return false }
        check("ve lo borrado, lo cambiado y lo creado", one.changes.deleted == ["build/x.o", "build/y.o"] && one.changes.modified == ["a.txt"] && one.changes.created == ["nuevo.txt", "out/"])
        check("termina bien y mide el tiempo", one.exitCode == 0 && !one.timedOut && one.seconds > 0 && one.seconds < 15)
        check("el proyecto real queda intacto", listing() == original && (try? String(contentsOfFile: proj + "/a.txt", encoding: .utf8)) == "uno\n")
        check("la copia se borra al terminar", ((try? fm.contentsOfDirectory(atPath: base)) ?? []).filter { UUID(uuidString: $0) != nil }.isEmpty)

        if case .success(let abs) = rehearse("cd \(real) && touch z.txt && echo \(real)") {
            check("la ruta absoluta del proyecto actua sobre la copia", abs.changes.created == ["z.txt"] && !fm.fileExists(atPath: proj + "/z.txt"))
            check("la salida muestra la ruta del proyecto, no la de la copia", abs.outputTail.contains(real) && !abs.outputTail.contains(base))
        } else { check("ruta absoluta", false) }

        if case .success(let out) = rehearse("echo fuga > '\(outside)/f.txt'; echo fuga > \"$HOME/.zshrc\"; echo ok") {
            check("escribir fuera del proyecto se impide", !fm.fileExists(atPath: outside + "/f.txt") && out.blockedOutside)
            check("lo escrito en la carpeta personal se captura sin tocar la real", out.homeWrites == [".zshrc"] && out.changes.total == 0)
        } else { check("fuera del proyecto", false) }

        if case .success(let slow) = rehearse("echo antes > t.txt; sleep 30; echo despues > u.txt", timeout: 1.5) {
            check("un comando lento se corta y se dice", slow.timedOut && slow.changes.created == ["t.txt"] && slow.seconds < 6)
        } else { check("plazo", false) }

        if case .success(let bad) = rehearse("echo roto >&2; exit 7") {
            check("el codigo de salida y la cola de la salida llegan", bad.exitCode == 7 && bad.outputTail == "roto" && bad.changes.isEmpty)
        } else { check("codigo de salida", false) }

        if case .success(let apps) = rehearse("open -g /System/Applications/Calculator.app; osascript -e 'return 1'; defaults write local.claudepet.ensayo k v; echo fin") {
            check("abrir apps, AppleScript y preferencias no pasan", apps.outputTail.hasSuffix("fin") && !apps.timedOut && apps.changes.isEmpty)
        } else { check("apps", false) }

        // git: un reset que descarta trabajo
        func git(_ a: [String]) {
            _ = RehearsalRunner.spawn(args: ["/usr/bin/git", "-C", proj, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + a,
                                      env: ["PATH": "/usr/bin:/bin", "HOME": tmpBase, "GIT_CONFIG_NOSYSTEM": "1"], cwd: proj, timeout: 20, maxOutput: 4096)
        }
        git(["init", "-q", "-b", "main"]); git(["add", "."]); git(["commit", "-q", "-m", "base"])
        write("a.txt", "trabajo sin guardar\n"); write("src.swift", "nuevo\n")
        if case .success(let reset) = rehearse("git reset -q --hard && cd .. && git clean -fdq", cwd: proj + "/build") {
            check("desde una subcarpeta se clona el repositorio entero", reset.gitBefore?.branch == "main" && reset.gitBefore?.dirty == 2)
            check("un reset que descarta trabajo se ve antes de hacerlo", reset.gitAfter?.dirty == 0 && reset.changes.deleted == ["src.swift"] && reset.changes.modified == ["a.txt"] && Rehearsal.headline(reset).contains("descartaría 2 cambios sin commitear"))
            check("y el trabajo sigue ahi", (try? String(contentsOfFile: proj + "/a.txt", encoding: .utf8)) == "trabajo sin guardar\n" && fm.fileExists(atPath: proj + "/src.swift"))
        } else { check("git", false) }

        check("una carpeta que no existe no se ensaya", rehearse("true", cwd: tmpBase + "/nada") == .failure(.noProject))
        check("la carpeta personal no se ensaya", RehearsalRunner.run(command: "true", cwd: NSHomeDirectory(), base: base) == .failure(.unsafeRoot))

        print(failures == 0 ? "OK ensayo" : "FALLOS: \(failures)")
        return failures == 0
    }
}
