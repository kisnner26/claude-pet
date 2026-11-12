import Foundation

/// `ClaudePet --selftest-concise`: el archivo del modo conciso (contrato con el hook) y, si se corre desde la raiz del repositorio, el hook de verdad.
enum ConciseModeSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "concise-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)

        check("apagado de serie: no hay archivo", !ConciseMode.isActive(home: home))
        check("textos por defecto en espanol e ingles", ConciseMode.defaultText(.es).hasPrefix("Responde") && ConciseMode.defaultText(.en).hasPrefix("Answer"))
        check("los textos por defecto caben en el contrato", ConciseMode.defaultES.utf8.count <= ConciseMode.maxBytes && ConciseMode.defaultEN.utf8.count <= ConciseMode.maxBytes)

        _ = try? ConciseMode.apply(enabled: true, customText: nil, home: home, lang: .es)
        let path = ConciseMode.path(home: home)
        check("encender escribe el archivo", ConciseMode.isActive(home: home) && (try? String(contentsOfFile: path, encoding: .utf8)) == ConciseMode.defaultES)
        let mode = (try? fm.attributesOfItem(atPath: path)[.posixPermissions]) as? Int
        check("permisos 0600", mode == 0o600)
        let dirMode = (try? fm.attributesOfItem(atPath: home + "/.claude-pet")[.posixPermissions]) as? Int
        check("carpeta 0700", dirMode == 0o700)
        _ = try? ConciseMode.apply(enabled: true, customText: nil, home: home, lang: .en)
        check("en ingles usa el texto en ingles", (try? String(contentsOfFile: path, encoding: .utf8)) == ConciseMode.defaultEN)
        _ = try? ConciseMode.apply(enabled: true, customText: "  responde en tres lineas \u{07}como mucho \n", home: home)
        check("texto propio, limpio de controles y espacios", (try? String(contentsOfFile: path, encoding: .utf8)) == "responde en tres lineas como mucho")
        _ = try? ConciseMode.apply(enabled: true, customText: "   ", home: home, lang: .es)
        check("texto propio vacio vuelve al predeterminado", (try? String(contentsOfFile: path, encoding: .utf8)) == ConciseMode.defaultES)
        let huge = String(repeating: "ñ", count: 5_000)
        check("un texto enorme se recorta a los limites del contrato", ConciseMode.sanitize(huge).count <= ConciseMode.maxCharacters && ConciseMode.sanitize(huge).utf8.count <= ConciseMode.maxBytes)
        _ = try? ConciseMode.apply(enabled: false, customText: nil, home: home)
        check("apagar borra el archivo", !ConciseMode.isActive(home: home) && !fm.fileExists(atPath: path))
        check("apagar dos veces no falla", (try? ConciseMode.apply(enabled: false, customText: nil, home: home)) == false)
        check("sin archivos temporales sueltos", ((try? fm.contentsOfDirectory(atPath: home + "/.claude-pet")) ?? []).isEmpty)

        // el hook de verdad, con una app de mentira
        let hook = fm.currentDirectoryPath + "/hooks/pet-brain.sh"
        if fm.fileExists(atPath: hook) {
            let stub = home + "/stub.sh"
            fm.createFile(atPath: stub, contents: Data("#!/bin/sh\necho \"[notas del cerebro]\"\n".utf8), attributes: [.posixPermissions: 0o755])
            func startOutput() -> String {
                let p = Process(); let pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = [hook, "start"]
                p.environment = ["HOME": home, "CLAUDE_PET_BIN": stub, "PATH": "/usr/bin:/bin"]
                p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                let input = Pipe(); p.standardInput = input
                try? p.run(); input.fileHandleForWriting.write(Data("{\"cwd\":\"/tmp\"}".utf8)); try? input.fileHandleForWriting.close()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                return String(decoding: data, as: UTF8.self)
            }
            check("hook con el modo apagado: solo el contexto de siempre", startOutput() == "[notas del cerebro]\n")
            _ = try? ConciseMode.apply(enabled: true, customText: "se breve", home: home)
            check("hook con el modo encendido: la instruccion va antes del contexto", startOutput() == "se breve\n\n[notas del cerebro]\n")
            _ = try? ConciseMode.apply(enabled: false, customText: nil, home: home)
            check("hook otra vez apagado", startOutput() == "[notas del cerebro]\n")
        } else {
            print("aviso: sin hooks/pet-brain.sh en la carpeta actual, no se prueba el hook")
        }

        print(failures == 0 ? "CONCISO OK" : "CONCISO \(failures) FALLOS")
        return failures == 0
    }
}
