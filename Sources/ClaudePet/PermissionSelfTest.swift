import Foundation
import Darwin

/// `ClaudePet --selftest-permission [ruta/al/hook]`: protocolo del socket y del hook bloqueante, de extremo a extremo.
/// Usa un HOME temporal: no toca ~/.claude-pet ni ~/.claude.
enum PermissionSelfTest {
    static func run(hook hookPath: String) -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        signal(SIGPIPE, SIG_IGN)      // un hook que ya salio no debe matar la prueba al escribirle
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        let sampleAsk = PermissionAsk(id: "copy", session: "s", tool: "Bash", project: "demo", detail: "echo hola", canAlways: false, at: Date())
        check("el permiso se puede copiar con herramienta, proyecto y detalle", sampleAsk.clipboardText == "permiso: Bash\nproyecto: demo\ndetalle: echo hola")
        let bareAsk = PermissionAsk(id: "copy-bare", session: "s", tool: "Read", project: "", detail: "", canAlways: false, at: Date())
        check("el texto copiado omite campos vacios", bareAsk.clipboardText == "permiso: Read")

        let home = NSTemporaryDirectory() + "claudepet-perm-\(getpid())"
        try? FileManager.default.createDirectory(atPath: home + "/.claude-pet", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        // el socket debe ser corto (limite de sockaddr_un)
        let sock = "/tmp/cp-ask-\(getpid()).sock"
        let flag = home + "/.claude-pet/island-permissions"
        let server = PermissionServer(path: sock)
        do { try server.start() } catch { print("FAIL no abre el socket: \(error)"); return false }
        defer { server.stop() }

        let payload = #"{"session_id":"abcdef123456","cwd":"/Users/x/miproyecto","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"limpia"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf build"}],"behavior":"allow","destination":"localSettings"}]}"#
        let noSuggest = #"{"session_id":"zzzz","cwd":"/p","tool_name":"Read","tool_input":{"file_path":"/p/a.txt"}}"#

        func spawn(_ input: String, wait: String = "20", sockPath: String = sock) -> (Process, Pipe) {
            let p = Process(), out = Pipe(), inp = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [hookPath]
            p.environment = ["HOME": home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "CLAUDE_PET_ASK_SOCK": sockPath, "CLAUDE_PET_ASK_WAIT": wait]
            p.standardInput = inp; p.standardOutput = out; p.standardError = FileHandle.nullDevice
            try? p.run()
            try? inp.fileHandleForWriting.write(contentsOf: Data(input.utf8)); try? inp.fileHandleForWriting.close()
            return (p, out)
        }
        func waitAsk(_ n: Int, timeout: TimeInterval = 5) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end { if server.asks.count == n { return true }; usleep(20_000) }
            return server.asks.count == n
        }
        func finish(_ p: Process, _ out: Pipe, timeout: TimeInterval = 5) -> String {
            let end = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < end { usleep(20_000) }
            if p.isRunning { p.terminate() }
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func json(_ s: String) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] }
        func decision(_ s: String) -> [String: Any]? { ((json(s)?["hookSpecificOutput"]) as? [String: Any])?["decision"] as? [String: Any] }

        // 1. sin la bandera opt-in el hook no hace nada
        var (p, o) = spawn(payload)
        var out = finish(p, o)
        check("sin la bandera del modo isla no imprime ni conecta", out.isEmpty && server.asks.isEmpty && p.terminationStatus == 0)

        FileManager.default.createFile(atPath: flag, contents: Data())

        // 2. permitir
        (p, o) = spawn(payload)
        check("el permiso llega a la app con herramienta, proyecto, comando y sugerencia", waitAsk(1) && { let a = server.asks[0]
            return a.tool == "Bash" && a.project == "miproyecto" && a.detail == "rm -rf build" && a.canAlways && a.session == "abcdef12" }())
        let id1 = server.asks.first?.id ?? ""
        check("responder permite y el hook devuelve allow", server.resolve(id: id1, .allow) && decision(finish(p, o))?["behavior"] as? String == "allow")
        check("resolver dos veces no hace nada", !server.resolve(id: id1, .allow) && server.asks.isEmpty)

        // 3. denegar
        (p, o) = spawn(payload); _ = waitAsk(1)
        server.resolve(id: server.asks[0].id, .deny)
        let d = decision(finish(p, o))
        check("denegar devuelve deny con mensaje", d?["behavior"] as? String == "deny" && (d?["message"] as? String)?.isEmpty == false)

        // 4. siempre permitir usa la regla sugerida por Claude Code
        (p, o) = spawn(payload); _ = waitAsk(1)
        server.resolve(id: server.asks[0].id, .always)
        let al = decision(finish(p, o))
        let upd = al?["updatedPermissions"] as? [[String: Any]]
        check("siempre permitir devuelve allow con la regla sugerida", al?["behavior"] as? String == "allow" && upd?.count == 1 && upd?[0]["type"] as? String == "addRules")

        // 5. sin regla sugerida no se ofrece "siempre"
        (p, o) = spawn(noSuggest); _ = waitAsk(1)
        check("sin sugerencia no se ofrece siempre permitir", server.asks.first?.canAlways == false)
        server.resolve(id: server.asks[0].id, .always)
        let plain = decision(finish(p, o))
        check("y 'siempre' sin regla equivale a permitir esta vez", plain?["behavior"] as? String == "allow" && plain?["updatedPermissions"] == nil)

        // 6. si respondes en la terminal el hook muere y la tarjeta desaparece
        (p, o) = spawn(payload); _ = waitAsk(1)
        p.terminate(); _ = finish(p, o)
        check("si el hook termina, el permiso se retira de la isla", waitAsk(0))

        // 7. varios a la vez, en orden de llegada
        let (p1, o1) = spawn(payload); _ = waitAsk(1)
        let (p2, o2) = spawn(noSuggest); _ = waitAsk(2)
        check("dos permisos quedan en cola en orden de llegada", server.asks.map(\.tool) == ["Bash", "Read"])
        server.resolve(id: server.asks[1].id, .deny)
        check("responder al segundo no afecta al primero", decision(finish(p2, o2))?["behavior"] as? String == "deny" && server.asks.count == 1)
        server.resolve(id: server.asks[0].id, .allow); _ = finish(p1, o1)

        // 8. entradas invalidas
        func raw(_ s: String) {
            let c = socket(AF_UNIX, SOCK_STREAM, 0); var addr = makeSockAddr(sock)!
            _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(c, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            _ = s.withCString { write(c, $0, strlen($0)) }; usleep(150_000); close(c)
        }
        raw("hola\n"); raw("perm\tx\t\t\t0\tsin herramienta\n"); raw("perm\tx\n")
        check("lineas invalidas se rechazan sin crear permisos", server.asks.isEmpty)
        raw("perm\ts\tBash\tp\t0\t" + String(repeating: "A", count: 3000) + "\n")
        check("el detalle largo se recorta", server.asks.first.map { $0.detail.count <= 400 } ?? false)
        if let a = server.asks.first { server.resolve(id: a.id, .deny) }
        raw("perm\ts\tBa\u{1B}sh\tp\t0\tcmd\u{7}\n")
        check("se quitan los caracteres de control", server.asks.first.map { $0.tool == "Bash" && $0.detail == "cmd" } ?? false)
        if let a = server.asks.first { server.resolve(id: a.id, .deny) }

        // 9. limite de pendientes
        var many: [(Process, Pipe)] = []
        for _ in 0..<(PermissionServer.maxPending + 2) { many.append(spawn(payload, wait: "3")); usleep(60_000) }
        check("no se acumulan mas de \(PermissionServer.maxPending) pendientes", waitAsk(PermissionServer.maxPending))
        for a in server.asks { server.resolve(id: a.id, .deny) }
        for (pp, oo) in many { _ = finish(pp, oo, timeout: 6) }

        // 10. fallos: sin servidor o app que se cierra, no hay decision (Claude Code pregunta en la terminal)
        (p, o) = spawn(payload, sockPath: "/tmp/no-existe-\(getpid()).sock")
        out = finish(p, o)
        check("sin socket el hook sale vacio y con 0", out.isEmpty && p.terminationStatus == 0)
        (p, o) = spawn(payload); _ = waitAsk(1)
        server.stop()
        out = finish(p, o)
        check("si la app se cierra con el permiso abierto, no hay decision", out.isEmpty && p.terminationStatus == 0)

        // 11. plazo agotado: sin respuesta, el hook termina solo y sin decision
        let server2 = PermissionServer(path: sock)
        try? server2.start()
        let t0 = Date()
        (p, o) = spawn(payload, wait: "1")
        out = finish(p, o, timeout: 6)
        check("si nadie responde, el hook se rinde tras su plazo y no decide", out.isEmpty && Date().timeIntervalSince(t0) < 5)
        server2.stop()

        print(failures == 0 ? "PERMISOS OK" : "PERMISOS FALLOS: \(failures)")
        return failures == 0
    }
}
