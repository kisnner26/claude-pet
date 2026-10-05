import Foundation

/// `ClaudePet --selftest-safety`: huella del proyecto, monitor asincrono, DiffOpener y parseo de eventos.
/// PASS/FAIL por caso; codigo de salida 0 solo si todo pasa.
@MainActor
enum SafetySelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        func spin(_ seconds: Double, until cond: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !cond() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        func sh(_ args: [String], in dir: String) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", dir] + args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "claudepet-selftest-\(getpid())"
        try? fm.removeItem(atPath: root)
        try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }
        func write(_ rel: String, _ text: String = "x") {
            let path = root + "/" + rel
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }

        // 1. huella
        write("a.swift", "uno"); write("src/b.swift", "dos")
        let f0 = WorkspaceSafety.fingerprint(root)
        check("la huella existe y es estable sin cambios", f0 != nil && f0 == WorkspaceSafety.fingerprint(root))
        check("ruta relativa o inexistente: sin huella", WorkspaceSafety.fingerprint("relativa") == nil && WorkspaceSafety.fingerprint(root + "/nope") == nil)
        for ignored in ["node_modules/x.js", "dist/o.js", ".next/c", "build/o", ".build/o", "target/o", "__pycache__/m.pyc", "out.log", "tmp.swp"] {
            write(ignored, "cambio")
        }
        write(".git/HEAD", "ref")
        check("artefactos generados y logs no cuentan como cambio", WorkspaceSafety.fingerprint(root) == f0)
        usleep(20_000); write("a.swift", "uno-modificado")
        let f1 = WorkspaceSafety.fingerprint(root)
        check("editar un archivo cambia la huella", f1 != f0)
        write("src/nuevo.swift")
        check("crear un archivo cambia la huella", WorkspaceSafety.fingerprint(root) != f1)

        // 2. monitor asincrono
        let mon = WorkspaceMonitor()
        final class Fired: @unchecked Sendable { var list: [String] = [] }
        let box = Fired()
        mon.onChange = { s in box.list.append(s) }       // se llama en el hilo principal
        mon.arm(session: "s1", workspace: root)
        spin(1.0) { false }                                // deja que tome la linea base
        mon.check(session: "s1", workspace: root); spin(1.0) { false }
        check("sin cambios no avisa", box.list.isEmpty && mon.changed.isEmpty)
        usleep(20_000); write("src/b.swift", "dos-cambiado")
        mon.check(session: "s1", workspace: root); spin(3.0) { !box.list.isEmpty }
        check("un cambio durante el pensamiento avisa una sola vez", box.list == ["s1"] && mon.changed == ["s1"])
        mon.check(session: "s1", workspace: root); spin(1.0) { false }
        check("no repite el aviso", box.list.count == 1)
        mon.forget(session: "s1")
        check("al terminar la sesion el aviso se limpia (no queda pegado)", mon.changed.isEmpty)
        mon.arm(session: "s2", workspace: root); spin(1.0) { false }
        usleep(20_000); write("a.swift", "otro")
        mon.arm(session: "s2", workspace: root); spin(1.0) { false }          // nueva linea base: lo anterior ya no cuenta
        mon.check(session: "s2", workspace: root); spin(1.0) { false }
        check("rearmar toma una linea base nueva (los cambios de la propia sesion no cuentan)", mon.changed.isEmpty)

        // 3. DiffOpener
        let repo = root + "/repo"
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        sh(["init", "-q"], in: repo); sh(["config", "user.email", "t@t.t"], in: repo); sh(["config", "user.name", "t"], in: repo)
        try? "base\n".write(toFile: repo + "/big.txt", atomically: true, encoding: .utf8)
        sh(["add", "."], in: repo); sh(["-c", "commit.gpgsign=false", "commit", "-qm", "init"], in: repo)
        let big = (0..<40_000).map { "linea \($0) \(UUID().uuidString)" }.joined(separator: "\n")      // varios MB, muy por encima de la tuberia del SO
        try? big.write(toFile: repo + "/big.txt", atomically: true, encoding: .utf8)
        let t0 = Date()
        let out = DiffOpener.renderSync(workspace: repo)
        let took = Date().timeIntervalSince(t0)
        let size = (out.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.size] as? Int }) ?? 0
        check("un diff de varios MB termina (sin colgarse) y se recorta al tope", out != nil && took < 15 && size > 64 * 1024 && size <= DiffOpener.maxBytes + 200)
        let perms = (out.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.posixPermissions] as? Int }) ?? 0
        check("el archivo del diff es solo del usuario (0600)", perms == 0o600)
        // un diff.external definido por el repo no debe ejecutarse
        let canary = root + "/canary-ejecutado"
        try? "#!/bin/sh\ntouch '\(canary)'\n".write(toFile: root + "/ext.sh", atomically: true, encoding: .utf8)
        chmod(root + "/ext.sh", 0o755)
        sh(["config", "diff.external", root + "/ext.sh"], in: repo)
        _ = DiffOpener.renderSync(workspace: repo)
        check("un diff.external del repo no se ejecuta", !fm.fileExists(atPath: canary))
        check("ruta no valida: no hace nada", DiffOpener.renderSync(workspace: "no/absoluta") == nil && DiffOpener.renderSync(workspace: root + "/nope") == nil)

        // 4. parseo de eventos
        let longPath = "/" + String(repeating: "a", count: 900)
        let line = ["tool", "abcd1234", "Edit", "proy", "main.swift", "desktop", "t:hacer algo", longPath].joined(separator: "\t")
        let ev = PetEvent.parse(line)
        check("el evento con ruta larga se parsea completo", ev?.workspace == longPath && ev?.detail == "main.swift" && ev?.task == "t:hacer algo")
        check("una ruta no absoluta se descarta", PetEvent.parse("tool\ts\tEdit\tp\td\tdesktop\t\trelativa")?.workspace == "")
        check("una linea sin ruta sigue valiendo (compatibilidad)", PetEvent.parse("tool\ts\tEdit\tp\td\tdesktop\t")?.workspace == "")

        // 5. titulos
        check("las pruebas se muestran como pruebas", PetStore.describe(.tool, tool: "test", detail: "$ swift", task: "").0 == "Ejecutando pruebas (swift)")

        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
