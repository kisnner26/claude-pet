import Foundation

/// `ClaudePet --selftest-restore`: puntos de restauracion en un repositorio temporal.
enum RestorePointsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let dir = NSTemporaryDirectory() + "claudepet-restore-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        func sh(_ args: [String]) -> String {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", dir] + args
            p.environment = ["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "HOME": dir, "PATH": "/usr/bin:/bin"]
            p.standardOutput = out; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func write(_ name: String, _ text: String) { try? text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8) }
        func read(_ name: String) -> String { (try? String(contentsOfFile: dir + "/" + name, encoding: .utf8)) ?? "" }

        check("una carpeta sin git no es repositorio", !RestorePoints.isRepo(dir) && RestorePoints.create(workspace: dir, label: "x") == nil)
        _ = sh(["init", "-q"]); write("a.txt", "uno\n"); _ = sh(["add", "."]); _ = sh(["commit", "-q", "-m", "base"])
        check("el arbol limpio no genera punto", !RestorePoints.isDirty(dir) && RestorePoints.create(workspace: dir, label: "limpio") == nil && RestorePoints.list(workspace: dir).isEmpty)

        write("a.txt", "dos\n")
        check("los cambios se detectan", RestorePoints.isDirty(dir))
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        guard let point = RestorePoints.create(workspace: dir, label: "Edit: antes del cambio", now: t0) else { check("crea un punto con cambios", false); return false }
        check("crea un punto con cambios", point.ref.hasPrefix("refs/claude-pet/") && point.sha.count >= 40)
        check("el arbol de trabajo queda intacto", read("a.txt") == "dos\n")
        check("la pila de stashes no cambia", sh(["stash", "list"]).isEmpty)
        check("el indice no cambia", sh(["diff", "--cached", "--name-only"]).isEmpty)
        check("el punto se lista con su etiqueta y hora", RestorePoints.list(workspace: dir).first == point || (RestorePoints.list(workspace: dir).first?.sha == point.sha && RestorePoints.list(workspace: dir).first?.at == t0))

        write("a.txt", "tres\n"); write("nuevo.txt", "nuevo\n")
        check("la vista previa muestra lo que cambiaria", RestorePoints.preview(workspace: dir, point: point).contains("a.txt"))
        check("restaurar devuelve el contenido del punto", RestorePoints.restore(workspace: dir, point: point) && read("a.txt") == "dos\n")
        check("restaurar no borra archivos nuevos", read("nuevo.txt") == "nuevo\n")
        check("restaurar no toca el indice", sh(["diff", "--cached", "--name-only"]).isEmpty)
        check("un punto inventado no se restaura", !RestorePoints.restore(workspace: dir, point: RestorePoints.Point(ref: "refs/claude-pet/0-x", sha: String(repeating: "a", count: 40), at: t0, label: "x")))

        // limite de 20 por proyecto
        for i in 0..<25 { write("a.txt", "v\(i)\n"); _ = RestorePoints.create(workspace: dir, label: "n\(i)", now: t0.addingTimeInterval(Double(i + 1))) }
        let all = RestorePoints.list(workspace: dir)
        check("se conservan como maximo 20 puntos", all.count == RestorePoints.maxPerProject)
        check("se conservan los mas recientes", all.first?.at == t0.addingTimeInterval(25) && !all.contains { $0.at == t0 })
        check("las etiquetas raras no rompen la referencia", RestorePoints.create(workspace: dir, label: "a b/c..d;rm -rf", now: t0.addingTimeInterval(99)).map { !$0.ref.contains(" ") && !$0.ref.contains("..") && !$0.ref.contains(";") } ?? false)

        print(failures == 0 ? "PUNTOS OK" : "PUNTOS FALLOS: \(failures)")
        return failures == 0
    }
}
