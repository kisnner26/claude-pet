import Foundation

/// `ClaudePet --selftest-plugins`: validacion del manifiesto, seguridad de los ejecutables, entorno, plazos y ciclo de vida, con scripts reales.
enum PluginSelfTest {
    static func run() -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("plugins-test-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        func manifest(_ over: [String: Any] = [:]) -> [String: Any] {
            var m: [String: Any] = ["id": "demo", "name": "Demo", "version": "1.0.0", "author": "alguien", "description": "un plugin de prueba",
                                    "permissions": ["project", "notify", "clipboard"],
                                    "actions": [["id": "go", "title": "ir", "run": "go.sh", "needs": "project", "places": ["menu", "island"]]]]
            for (k, v) in over { m[k] = v }
            return m
        }
        func write(_ dir: URL, _ name: String, _ text: String, mode: Int = 0o755) {
            try? fm.createDirectory(at: dir.appendingPathComponent(name).deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data(text.utf8), attributes: [.posixPermissions: mode])
        }
        func make(_ root: URL, _ id: String, _ m: [String: Any], files: [String: String] = ["go.sh": "#!/bin/sh\necho '{\"toast\":\"hecho\"}'\n"]) -> URL {
            let dir = root.appendingPathComponent(id)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var mm = m; mm["id"] = id
            try? JSONSerialization.data(withJSONObject: mm).write(to: dir.appendingPathComponent("plugin.json"))
            for (n, t) in files { write(dir, n, t) }
            return dir
        }
        func decode(_ m: [String: Any]) -> PluginManifest? { (try? JSONSerialization.data(withJSONObject: m)).flatMap(PluginManifest.decode) }
        func problems(_ over: [String: Any]) -> [String] { decode(manifest(over))?.problems(appVersion: "2.1.0") ?? ["no decodifica"] }

        // 1. manifiesto
        check("manifest-minimal-decodes", PluginManifest.decode(Data("{\"id\":\"minimo\",\"name\":\"M\",\"version\":\"1.0.0\",\"author\":\"a\",\"description\":\"d\"}".utf8))?.problems(appVersion: "2.1.0").isEmpty == true)
        check("manifest-missing-required-fails", PluginManifest.decode(Data("{\"id\":\"minimo\"}".utf8)) == nil)
        check("manifest-valid", problems([:]).isEmpty)
        check("manifest-bad-id", !problems(["id": "Mal Id"]).isEmpty && !problems(["id": "../x"]).isEmpty && !problems(["id": "a"]).isEmpty)
        check("manifest-bad-version", !problems(["version": "1.0"]).isEmpty && !problems(["version": "uno"]).isEmpty)
        check("manifest-unknown-permission", !problems(["permissions": ["project", "root"]]).isEmpty)
        check("manifest-needs-project-requires-permission", !problems(["permissions": ["notify"]]).isEmpty)
        check("manifest-abs-run", !problems(["actions": [["id": "go", "title": "x", "run": "/bin/sh"]]]).isEmpty)
        check("manifest-dotdot-run", !problems(["actions": [["id": "go", "title": "x", "run": "../fuera.sh"]]]).isEmpty && !problems(["actions": [["id": "go", "title": "x", "run": "a/../../b.sh"]]]).isEmpty)
        check("manifest-dup-actions", !problems(["actions": [["id": "go", "title": "x", "run": "a.sh"], ["id": "go", "title": "y", "run": "b.sh"]]]).isEmpty)
        check("manifest-too-many-actions", !problems(["actions": (0..<13).map { ["id": "a\($0)", "title": "t", "run": "a.sh"] }]).isEmpty)
        check("manifest-events-need-permission", !problems(["events": ["session.done": "e.sh"]]).isEmpty && problems(["permissions": ["project", "events"], "events": ["session.done": "e.sh"]]).isEmpty)
        check("manifest-music-event-needs-music", !problems(["permissions": ["project", "events"], "events": ["music.track": "e.sh"]]).isEmpty && problems(["permissions": ["project", "events", "music"], "events": ["music.track": "e.sh"]]).isEmpty)
        check("manifest-unknown-event", !problems(["permissions": ["project", "events"], "events": ["disk.format": "e.sh"]]).isEmpty)
        check("manifest-homepage-https", !problems(["homepage": "http://x.com"]).isEmpty && problems(["homepage": "https://x.com/p"]).isEmpty)
        check("manifest-minapp", !problems(["minApp": "9.0.0"]).isEmpty && problems(["minApp": "2.0.0"]).isEmpty)
        check("manifest-settings", !problems(["settings": [["key": "Mal", "type": "text", "title": "t"]]]).isEmpty && !problems(["settings": [["key": "ok", "type": "raro", "title": "t"]]]).isEmpty
              && !problems(["settings": [["key": "ok", "type": "choice", "title": "t"]]]).isEmpty && problems(["settings": [["key": "ok", "type": "choice", "title": "t", "options": ["a", "b"]]]]).isEmpty)
        check("manifest-oversize", PluginManifest.decode(Data(repeating: 32, count: PluginManifest.maxBytes + 1)) == nil && PluginManifest.decode(Data("basura".utf8)) == nil)
        check("version-compare", PluginManifest.compare("2.1.0", "2.0.9") == .orderedDescending && PluginManifest.compare("2.0", "2.0.0") == .orderedSame && PluginManifest.compare("1.9.9", "2.0.0") == .orderedAscending)

        // 2. efectos
        let all: Set<String> = ["notify", "clipboard", "open-url"]
        check("fx-parse", PluginEffects.parse(stdout: "log\n{\"toast\":\"hola\",\"copy\":\"texto\",\"open\":\"https://example.com/a\"}\n", permissions: all) == PluginEffects(toast: "hola", copy: "texto", open: URL(string: "https://example.com/a")))
        check("fx-gated-by-permission", PluginEffects.parse(stdout: "{\"toast\":\"a\",\"copy\":\"b\",\"open\":\"https://x.com\"}", permissions: []) == PluginEffects())
        check("fx-only-notify", PluginEffects.parse(stdout: "{\"toast\":\"a\",\"copy\":\"b\"}", permissions: ["notify"]) == PluginEffects(toast: "a"))
        check("fx-rejects-non-https", PluginEffects.parse(stdout: "{\"open\":\"http://x.com\"}", permissions: all).open == nil && PluginEffects.parse(stdout: "{\"open\":\"file:///etc/passwd\"}", permissions: all).open == nil && PluginEffects.parse(stdout: "{\"open\":\"javascript:alert(1)\"}", permissions: all).open == nil)
        check("fx-truncates", PluginEffects.parse(stdout: "{\"toast\":\"\(String(repeating: "x", count: 500))\"}", permissions: all).toast?.count == 160)
        check("fx-strips-controls", PluginEffects.parse(stdout: "{\"toast\":\"a\\u0007b\\nc\"}", permissions: all).toast == "ab c")
        check("fx-junk", PluginEffects.parse(stdout: "no json", permissions: all) == PluginEffects() && PluginEffects.parse(stdout: "", permissions: all) == PluginEffects() && PluginEffects.parse(stdout: "[1,2]", permissions: all) == PluginEffects())

        // 3. carga util de eventos
        let proj = (path: "/Users/x/app", name: "app")
        let withProject = String(decoding: PluginEvents.payload(.permissionAsked, fields: ["tool": "Edit", "project": "app", "detail": "/secreto/ruta", "extra": "x"], permissions: ["events", "project"], project: proj), as: UTF8.self)
        check("event-payload-fields", withProject.contains("\"tool\":\"Edit\"") && withProject.contains("project_path") && !withProject.contains("detail") && !withProject.contains("secreto") && !withProject.contains("extra"))
        let without = String(decoding: PluginEvents.payload(.permissionAsked, fields: ["tool": "Edit"], permissions: ["events"], project: proj), as: UTF8.self)
        check("event-payload-no-project-without-permission", !without.contains("project_path") && !without.contains("/Users/x/app"))
        check("event-payload-music-fields", String(decoding: PluginEvents.payload(.musicTrack, fields: ["title": "T", "artist": "A", "tool": "no"], permissions: ["events", "music"]), as: UTF8.self).contains("\"artist\":\"A\""))

        // 4. seguridad de ejecutables
        let sec = make(tmp, "sec", manifest(), files: ["ok.sh": "#!/bin/sh\n"])
        write(sec, "plain.txt", "x", mode: 0o644)
        write(sec, "groupw.sh", "#!/bin/sh\n", mode: 0o775); write(sec, "noexec.sh", "#!/bin/sh\n", mode: 0o644); write(sec, "worldw.sh", "#!/bin/sh\n", mode: 0o757)
        try? fm.createSymbolicLink(atPath: sec.appendingPathComponent("escape.sh").path, withDestinationPath: "/bin/echo")
        try? fm.createSymbolicLink(atPath: sec.appendingPathComponent("inside.sh").path, withDestinationPath: sec.appendingPathComponent("ok.sh").path)
        try? fm.createDirectory(at: sec.appendingPathComponent("dir.sh"), withIntermediateDirectories: true)
        check("exec-ok", PluginSecurity.resolveExecutable("ok.sh", in: sec) != nil && PluginSecurity.resolveExecutable("./ok.sh", in: sec) != nil)
        check("exec-rejects-group-or-world-writable", PluginSecurity.resolveExecutable("groupw.sh", in: sec) == nil && PluginSecurity.resolveExecutable("worldw.sh", in: sec) == nil)
        check("exec-rejects-non-executable", PluginSecurity.resolveExecutable("noexec.sh", in: sec) == nil && PluginSecurity.resolveExecutable("plain.txt", in: sec) == nil)
        check("exec-rejects-escaping-symlink", PluginSecurity.resolveExecutable("escape.sh", in: sec) == nil)
        check("exec-allows-inside-symlink", PluginSecurity.resolveExecutable("inside.sh", in: sec) != nil)
        check("exec-rejects-traversal-and-abs", PluginSecurity.resolveExecutable("../sec/ok.sh", in: sec) == nil && PluginSecurity.resolveExecutable("/bin/sh", in: sec) == nil && PluginSecurity.resolveExecutable("dir.sh", in: sec) == nil && PluginSecurity.resolveExecutable("nope.sh", in: sec) == nil)

        // 5. entorno
        setenv("CLAUDE_PET_TEST_SECRET", "no-debe-llegar", 1)
        let envDir = make(tmp, "envp", manifest(["permissions": ["project"], "settings": [["key": "modo", "type": "choice", "title": "m", "options": ["a", "b"], "default": "a"], ["key": "auto", "type": "toggle", "title": "t"]]]),
                          files: ["go.sh": "#!/bin/sh\nenv | sort\n"])
        let sem = DispatchSemaphore(value: 0)
        var envOut = "", envOutNoProject = ""
        let reg0 = PluginRegistry(root: tmp, statePath: nil)
        let envPlugin = reg0.plugin("envp")!
        Task.detached {
            let exe = PluginSecurity.resolveExecutable("go.sh", in: envDir)!
            envOut = await PluginRunner.run(executable: exe, args: [], env: PluginSecurity.environment(plugin: envPlugin, settings: ["modo": "b"], project: (path: "/p/x", name: "x"), event: nil), cwd: envDir).stdout
            envOutNoProject = await PluginRunner.run(executable: exe, args: [], env: PluginSecurity.environment(plugin: LoadedPlugin(manifest: { var m = envPlugin.manifest; m.permissions = []; return m }(), dir: envDir, problems: []), settings: [:], project: (path: "/p/x", name: "x"), event: "session.done"), cwd: envDir).stdout
            sem.signal()
        }
        sem.wait()
        check("env-no-secrets", !envOut.contains("no-debe-llegar") && !envOut.contains("CLAUDE_PET_TEST_SECRET"))
        check("env-has-plugin-info", envOut.contains("CLAUDE_PET_PLUGIN_ID=envp") && envOut.contains("CLAUDE_PET=1") && envOut.contains("PATH=/usr/bin"))
        check("env-project-with-permission", envOut.contains("CLAUDE_PET_PROJECT=/p/x") && envOut.contains("CLAUDE_PET_PROJECT_NAME=x"))
        check("env-project-hidden-without-permission", !envOutNoProject.contains("CLAUDE_PET_PROJECT=") && envOutNoProject.contains("CLAUDE_PET_EVENT=session.done"))
        check("env-settings", envOut.contains("CLAUDE_PET_SETTING_MODO=b") && envOut.contains("CLAUDE_PET_SETTING_AUTO=false"))
        check("env-defaults", envOutNoProject.contains("CLAUDE_PET_SETTING_MODO=a"))

        // 6. ejecucion
        var rOK = PluginResult(), rFail = PluginResult(), rSlow = PluginResult(), rBig = PluginResult(), rStdin = PluginResult(), rMissing = PluginResult()
        var slowElapsed = 0.0
        let runDir = make(tmp, "runp", manifest(), files: ["ok.sh": "#!/bin/sh\necho hola\n", "fail.sh": "#!/bin/sh\necho mal >&2\nexit 3\n", "slow.sh": "#!/bin/sh\nsleep 8\n", "big.sh": "#!/bin/sh\nyes xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx | head -c 300000\n", "cat.sh": "#!/bin/sh\ncat\n"])
        Task.detached {
            func exe(_ n: String) -> URL { PluginSecurity.resolveExecutable(n, in: runDir)! }
            rOK = await PluginRunner.run(executable: exe("ok.sh"), args: [], env: ["PATH": "/usr/bin:/bin"], cwd: runDir)
            rFail = await PluginRunner.run(executable: exe("fail.sh"), args: [], env: ["PATH": "/usr/bin:/bin"], cwd: runDir)
            let t0 = Date()
            rSlow = await PluginRunner.run(executable: exe("slow.sh"), args: [], env: ["PATH": "/usr/bin:/bin"], cwd: runDir, timeout: 0.6)
            slowElapsed = Date().timeIntervalSince(t0)
            rBig = await PluginRunner.run(executable: exe("big.sh"), args: [], env: ["PATH": "/usr/bin:/bin"], cwd: runDir)
            rStdin = await PluginRunner.run(executable: exe("cat.sh"), args: [], env: ["PATH": "/usr/bin:/bin"], cwd: runDir, stdin: Data("entrada".utf8))
            rMissing = await PluginRunner.run(executable: runDir.appendingPathComponent("no-existe"), args: [], env: [:], cwd: runDir)
            sem.signal()
        }
        sem.wait()
        check("run-ok", rOK.ok && rOK.stdout == "hola\n")
        check("run-fail", !rFail.ok && rFail.status == 3 && rFail.stderr.contains("mal"))
        check("run-timeout-kills", rSlow.timedOut && !rSlow.ok && slowElapsed < 4)
        check("run-output-capped", rBig.stdout.utf8.count <= PluginRunner.maxOutput && rBig.stdout.utf8.count > 1000)
        check("run-stdin", rStdin.stdout == "entrada")
        check("run-launch-error", rMissing.launchError != nil && !rMissing.ok)

        // 7. registro: descubrimiento, aprobacion, ejecucion, permisos nuevos
        let root = tmp.appendingPathComponent("registry")
        _ = make(root, "bueno", manifest(["permissions": ["project", "notify"]]))
        let mismatch = make(root, "otro-nombre", manifest())
        try? JSONSerialization.data(withJSONObject: manifest(["id": "distinto"])).write(to: mismatch.appendingPathComponent("plugin.json"))     // la carpeta no coincide con el id
        let malo = make(root, "inseguro", manifest(), files: [:]); write(malo, "go.sh", "#!/bin/sh\n", mode: 0o777)
        let statePath = tmp.appendingPathComponent("state.json").path
        let reg = PluginRegistry(root: root, statePath: statePath)
        check("registry-discovers", reg.plugin("bueno")?.problems.isEmpty == true)
        check("registry-flags-id-mismatch", reg.plugin("otro-nombre")?.problems.isEmpty == false && reg.plugin("distinto") == nil && reg.status("otro-nombre") == .invalid)
        // y no puede apropiarse del estado de otro plugin
        let impostor = make(root, "impostor", manifest())
        try? JSONSerialization.data(withJSONObject: manifest(["id": "bueno", "permissions": ["project", "notify"]])).write(to: impostor.appendingPathComponent("plugin.json"))
        reg.reload()
        check("registry-impostor-cannot-shadow", reg.plugin("bueno")?.dir.lastPathComponent == "bueno" && reg.status("impostor") == .invalid)
        try? fm.removeItem(at: impostor); reg.reload()
        check("registry-flags-unsafe-executable", reg.plugin("inseguro")?.problems.contains { $0.contains("ejecutable seguro") } == true && reg.status("inseguro") == .invalid)
        check("registry-disabled-by-default", reg.status("bueno") == .disabled && reg.actions(place: "menu").isEmpty)
        check("registry-enable-needs-approval", !reg.setEnabled("bueno", true) && reg.status("bueno") == .disabled)
        check("registry-enable-with-approval", reg.setEnabled("bueno", true, approving: true) && reg.status("bueno") == .enabled)
        check("registry-cannot-enable-invalid", !reg.setEnabled("inseguro", true, approving: true))
        check("registry-actions-by-place", reg.actions(place: "menu").count == 1 && reg.actions(place: "island").count == 1 && reg.actions(place: "otro").isEmpty)
        var rAct: (result: PluginResult, effects: PluginEffects)?, rNoProj: (result: PluginResult, effects: PluginEffects)?, rDisabled: (result: PluginResult, effects: PluginEffects)?
        Task.detached {
            rAct = await reg.runAction("bueno", "go", project: (path: "/p", name: "p"))
            rNoProj = await reg.runAction("bueno", "go", project: nil)
            rDisabled = await reg.runAction("inseguro", "go", project: (path: "/p", name: "p"))
            sem.signal()
        }
        sem.wait()
        check("registry-runs-action-and-parses-effects", rAct?.result.ok == true && rAct?.effects.toast == "hecho")
        check("registry-needs-project", rNoProj == nil)
        check("registry-disabled-does-not-run", rDisabled == nil)
        // permisos nuevos: el plugin se para hasta que el usuario los acepte
        var m2 = manifest(["permissions": ["project", "notify", "clipboard"]]); m2["id"] = "bueno"
        try? JSONSerialization.data(withJSONObject: m2).write(to: root.appendingPathComponent("bueno/plugin.json"))
        reg.reload()
        check("registry-new-permission-pauses", reg.status("bueno") == .needsApproval(["clipboard"]) && reg.actions(place: "menu").isEmpty)
        var rPaused: (result: PluginResult, effects: PluginEffects)?
        Task.detached { rPaused = await reg.runAction("bueno", "go", project: (path: "/p", name: "p")); sem.signal() }
        sem.wait()
        check("registry-paused-does-not-run", rPaused == nil)
        check("registry-reapprove", reg.setEnabled("bueno", true, approving: true) && reg.status("bueno") == .enabled)
        check("registry-state-persists", PluginRegistry(root: root, statePath: statePath).status("bueno") == .enabled)
        check("state-file-0600", ((try? fm.attributesOfItem(atPath: statePath)[.posixPermissions] as? Int) ?? 0) == 0o600)
        reg.setEnabled("bueno", false)
        check("registry-disable", reg.status("bueno") == .disabled)

        // ajustes de plugin
        let setRoot = tmp.appendingPathComponent("settings")
        _ = make(setRoot, "ajustes", manifest(["permissions": [], "actions": [], "settings": [["key": "modo", "type": "choice", "title": "m", "options": ["a", "b"], "default": "a"], ["key": "auto", "type": "toggle", "title": "t"], ["key": "nota", "type": "text", "title": "n"]]]), files: [:])
        let regS = PluginRegistry(root: setRoot, statePath: nil)
        let modo = regS.plugin("ajustes")!.manifest.settings[0]
        check("setting-default", regS.settingValue("ajustes", modo) == "a")
        regS.setSetting("ajustes", key: "modo", value: "b"); regS.setSetting("ajustes", key: "auto", value: "yes"); regS.setSetting("ajustes", key: "nota", value: String(repeating: "z", count: 900))
        check("setting-choice-valid", regS.settingValue("ajustes", modo) == "b")
        regS.setSetting("ajustes", key: "modo", value: "zzz")
        check("setting-choice-rejects-unknown", regS.settingValue("ajustes", modo) == "b")
        check("setting-toggle-normalized", regS.state("ajustes").settings["auto"] == "false")
        check("setting-text-truncated", regS.state("ajustes").settings["nota"]?.count == 200)
        regS.setSetting("ajustes", key: "inexistente", value: "x")
        check("setting-unknown-key-ignored", regS.state("ajustes").settings["inexistente"] == nil)

        // eventos
        let evRoot = tmp.appendingPathComponent("events")
        _ = make(evRoot, "oyente", manifest(["permissions": ["events"], "actions": [], "events": ["session.done": "on-done.sh"]]), files: ["on-done.sh": "#!/bin/sh\ncat > \"$CLAUDE_PET_PLUGIN_DIR/last.json\"\n"])
        let regE = PluginRegistry(root: evRoot, statePath: nil)
        check("events-no-handlers-when-disabled", regE.handlers(for: .sessionDone).isEmpty)
        regE.setEnabled("oyente", true, approving: true)
        check("events-handler-registered", regE.handlers(for: .sessionDone).count == 1 && regE.handlers(for: .permissionAsked).isEmpty)
        let h = regE.handlers(for: .sessionDone)[0]
        Task.detached { _ = await regE.runEvent(.sessionDone, plugin: h.plugin, executable: h.executable, fields: ["agent": "claude", "seconds": "42", "secreto": "x"], project: (path: "/p/x", name: "x")); sem.signal() }
        sem.wait()
        let last = (try? String(contentsOf: evRoot.appendingPathComponent("oyente/last.json"))) ?? ""
        check("events-delivered-via-stdin", last.contains("\"event\":\"session.done\"") && last.contains("\"agent\":\"claude\"") && !last.contains("secreto") && !last.contains("project_path"))

        // instalacion
        let instRoot = tmp.appendingPathComponent("installed")
        let src = make(tmp.appendingPathComponent("src"), "nuevo", manifest(["permissions": ["project"]]), files: ["go.sh": "#!/bin/sh\necho ok\n", "lib/util.sh": "#!/bin/sh\n"])
        try? fm.setAttributes([.posixPermissions: 0o775], ofItemAtPath: src.appendingPathComponent("go.sh").path)   // el origen tiene escritura de grupo
        let regI = PluginRegistry(root: instRoot, statePath: nil)
        let installed = try? regI.install(from: src)
        check("install-copies", installed != nil && fm.fileExists(atPath: instRoot.appendingPathComponent("nuevo/go.sh").path))
        let mode = (try? fm.attributesOfItem(atPath: instRoot.appendingPathComponent("nuevo/go.sh").path)[.posixPermissions] as? Int) ?? 0
        check("install-strips-group-world-write", mode & 0o022 == 0 && mode & 0o100 != 0)
        check("install-not-enabled", regI.status("nuevo") == .disabled)
        check("install-twice-rejected", { do { _ = try regI.install(from: src); return false } catch { return (error as? PluginRegistry.InstallError) == .exists("nuevo") } }())
        let badSrc = tmp.appendingPathComponent("bad"); try? fm.createDirectory(at: badSrc, withIntermediateDirectories: true)
        check("install-no-manifest", { do { _ = try regI.install(from: badSrc); return false } catch { return (error as? PluginRegistry.InstallError) == .noManifest } }())
        let invSrc = make(tmp.appendingPathComponent("src"), "roto", manifest(["version": "x"]))
        check("install-invalid-manifest", { do { _ = try regI.install(from: invSrc); return false } catch { if case .invalid? = (error as? PluginRegistry.InstallError) { return true }; return false } }())
        let linkSrc = make(tmp.appendingPathComponent("src"), "enlace", manifest())
        try? fm.createSymbolicLink(atPath: linkSrc.appendingPathComponent("evil").path, withDestinationPath: "/etc")
        check("install-rejects-symlinks", { do { _ = try regI.install(from: linkSrc); return false } catch { return (error as? PluginRegistry.InstallError) == .symlink } }())
        let bigSrc = make(tmp.appendingPathComponent("src"), "grande", manifest())
        for i in 0..<(PluginRegistry.maxInstallFiles + 5) { write(bigSrc, "f/\(i).txt", "x", mode: 0o644) }
        check("install-rejects-too-many-files", { do { _ = try regI.install(from: bigSrc); return false } catch { return (error as? PluginRegistry.InstallError) == .tooBig } }())
        check("install-failed-leaves-nothing", regI.plugin("grande") == nil && regI.plugin("enlace") == nil && !fm.fileExists(atPath: instRoot.appendingPathComponent("grande").path))
        regI.setEnabled("nuevo", true, approving: true)
        regI.uninstall("nuevo")
        check("uninstall-removes-dir-and-state", regI.plugin("nuevo") == nil && !fm.fileExists(atPath: instRoot.appendingPathComponent("nuevo").path) && regI.state("nuevo") == PluginState())

        print(failures == 0 ? "PLUGINS OK" : "PLUGINS \(failures) FALLOS")
        return failures == 0
    }
}
