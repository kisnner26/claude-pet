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

        // 2b. plan: el texto del plan llega aplanado y se aprueba o rechaza como un permiso
        let plan = #"{"session_id":"plan1234","cwd":"/p/miproyecto","tool_name":"ExitPlanMode","tool_input":{"plan":"1. leer el codigo\n2. cambiar X\n3. probar"}}"#
        (p, o) = spawn(plan)
        check("un plan llega con su texto aplanado", waitAsk(1) && { let a = server.asks[0]; return a.tool == "ExitPlanMode" && a.detail == "1. leer el codigo ~ 2. cambiar X ~ 3. probar" }())
        check("un plan es de riesgo medio y no se recuerda",
              PermissionRiskClassifier.classify(tool: "ExitPlanMode", detail: "x", project: "p").risk == .medium && ApprovalRules.key(tool: "ExitPlanMode", detail: "x") == nil)
        check("la vista previa del plan lista sus pasos", PermissionPreviewBuilder.make(tool: "ExitPlanMode", detail: "a ~ b ~ c", project: "p").lines == ["a", "b", "c"])
        check("aprobar el plan devuelve allow", server.resolve(id: server.asks.first?.id ?? "", .allow) && decision(finish(p, o))?["behavior"] as? String == "allow")

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
        // la conexion se queda abierta hasta leer el permiso: cerrarla lo retira, y con una espera fija la lectura competia con ese cierre
        let longConn = socket(AF_UNIX, SOCK_STREAM, 0); var longAddr = makeSockAddr(sock)!
        _ = withUnsafePointer(to: &longAddr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(longConn, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        let longLine = "perm\ts\tBash\tp\t0\t" + String(repeating: "A", count: 3000) + "\n"
        _ = longLine.withCString { write(longConn, $0, strlen($0)) }
        var longWaits = 0
        while server.asks.isEmpty && longWaits < 50 { usleep(100_000); longWaits += 1 }
        check("el detalle largo se recorta", server.asks.first.map { $0.detail.count <= 400 } ?? false)
        close(longConn)
        if let a = server.asks.first { server.resolve(id: a.id, .deny) }
        raw("perm\ts\tBa\u{1B}sh\tp\t0\tcmd\u{7}\n")
        check("se quitan los caracteres de control", server.asks.first.map { $0.tool == "Bash" && $0.detail == "cmd" } ?? false)
        if let a = server.asks.first { server.resolve(id: a.id, .deny) }
        var fuzzSafe = true
        for size in [0, 1, 5, 128, PermissionServer.maxLine, PermissionServer.maxLine + 1, 9000] {
            let bytes = [UInt8](repeating: 0xFF, count: size)
            fuzzSafe = fuzzSafe && PermissionServer.parse(String(decoding: bytes, as: UTF8.self)) == nil
        }
        check("fuzz de permisos rechaza basura, utf-8 inválido y líneas enormes", fuzzSafe)

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

        // 12. perimetro de extremo a extremo: el hook real pide editar fuera de la zona y la puerta lo deniega sin preguntar
        let fenceRoot = "/tmp/claudepet-fence-\(getpid())"
        let fence = PerimeterStore(path: nil)
        fence.upsert(Perimeter(root: fenceRoot, allow: ["Sources/**"], mode: .block))
        let server3 = PermissionServer(path: sock)
        server3.onChange = { asks in
            if case .deny(let id, _) = PermissionGate.decide(asks: asks, check: { fence.check($0) }, ruleMatches: { _ in false }) { _ = server3.resolve(id: id, .deny, source: "perímetro") }
        }
        try? server3.start()
        let edit = { (path: String) in #"{"session_id":"fence1","cwd":"\#(fenceRoot)","tool_name":"Edit","tool_input":{"file_path":"\#(path)","old_string":"a","new_string":"b"}}"# }
        (p, o) = spawn(edit(fenceRoot + "/Package.swift"))
        out = finish(p, o)
        let denied = decision(out)
        check("el perimetro deniega una edicion fuera de la zona sin que nadie responda", denied?["behavior"] as? String == "deny" && server3.asks.isEmpty)
        (p, o) = spawn(edit(fenceRoot + "/Sources/ok.swift"))
        let pending = { () -> Bool in let end = Date().addingTimeInterval(5); while Date() < end { if server3.asks.count == 1 { return true }; usleep(20_000) }; return false }()
        check("dentro del perimetro el permiso llega a la isla para decidir", pending)
        _ = server3.resolve(id: server3.asks.first?.id ?? "", .allow)
        check("y se puede permitir con normalidad", decision(finish(p, o))?["behavior"] as? String == "allow")
        server3.stop()

        // 13. el cambio real: Edit, Write, Bash y NotebookEdit pasan por el hook real y llegan a la app con el diff calculado
        let server4 = PermissionServer(path: sock)
        try? server4.start()
        defer { server4.stop() }
        func waitAsk4(_ n: Int, timeout: TimeInterval = 5) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end { if server4.asks.count == n { return true }; usleep(20_000) }
            return server4.asks.count == n
        }
        func hookInput(_ tool: String, _ input: [String: Any], cwd: String = "/Users/x/miproyecto") -> String {
            let o: [String: Any] = ["session_id": "chg12345", "cwd": cwd, "tool_name": tool, "tool_input": input]
            return String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), as: UTF8.self)
        }
        func through(_ tool: String, _ input: [String: Any], wait: String = "20") -> PermissionAsk? {
            let (pp, oo) = spawn(hookInput(tool, input), wait: wait)
            let got = waitAsk4(1) ? server4.asks.first : nil
            if let id = got?.id { server4.resolve(id: id, .allow) }
            _ = finish(pp, oo)
            return got
        }
        let work = home + "/work"
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        let existing = work + "/viejo.swift"
        try? "uno\ndos\ntres\ncuatro\n".write(toFile: existing, atomically: true, encoding: .utf8)

        let ed = through("Edit", ["file_path": existing, "old_string": "dos\ntres", "new_string": "DOS\ntres\ntres bis", "replace_all": false])
        check("Edit: el par old/new llega como diff +2 −1 y el detalle sigue siendo la ruta", ed?.change?.added == 2 && ed?.change?.removed == 1 && ed?.detail == existing && ed?.cwd == "/Users/x/miproyecto" && ed?.rawCommand == nil)
        let wr = through("Write", ["file_path": existing, "content": "uno\nDOS\ntres\ncuatro\ncinco\n"])
        check("Write sobre un archivo existente se compara con el disco", wr?.change?.shape == .rewrite && wr?.change?.added == 2 && wr?.change?.removed == 1)
        let wn = through("Write", ["file_path": work + "/nuevo.swift", "content": "let a = 1\nlet b = 2\n"])
        check("Write a un archivo que no existe es archivo nuevo", wn?.change?.shape == .newFile && wn?.change?.added == 2 && wn?.change?.tag == "archivo nuevo")
        let me = through("MultiEdit", ["file_path": existing, "edits": [["old_string": "uno", "new_string": "1"], ["old_string": "cuatro", "new_string": "4"]]])
        check("MultiEdit llega con sus dos ediciones", me?.change?.shape == .multiEdit(2) && me?.change?.added == 2)
        let nb = through("NotebookEdit", ["notebook_path": work + "/n.ipynb", "new_source": "x = 1\ny = 2", "cell_type": "code", "edit_mode": "insert"])
        check("NotebookEdit llega como celda nueva y su ruta es el detalle", nb?.change?.shape == .cellInsert && nb?.change?.added == 2 && nb?.detail == work + "/n.ipynb")
        let secretWrite = through("Write", ["file_path": work + "/c.swift", "content": "let key = \"sk-live-abcdef123456\"\n"])
        check("una credencial en el contenido nuevo se avisa", secretWrite?.change?.secret != nil)

        // el comando de Bash llega integro, byte a byte, mientras el detalle sigue aplanado como siempre
        let nasty = "echo \"a\\\"b\" 'c'\\\\d\te\nf\\\n$(printf '\\x00')\u{0}\u{1}fin # " + String(repeating: "é", count: 900)
        let bash = through("Bash", ["command": nasty, "description": "x"])
        check("Bash: el comando llega identico, con comillas, barras, tabuladores, saltos y nulos", bash?.rawCommand == nasty && bash?.cwd == "/Users/x/miproyecto" && bash?.change == nil)
        check("Bash: el detalle sigue limpio y recortado como antes", bash.map { $0.detail.count <= 400 && !$0.detail.unicodeScalars.contains { $0.value < 32 || $0.value == 92 } } ?? false)
        let tooLong = String(repeating: "x", count: ChangeWire.maxCommandChars + 1)
        check("Bash: un comando que excede el tope no se envia (nil, no recortado)", through("Bash", ["command": tooLong])?.rawCommand == nil)
        check("otras herramientas no llevan comando ni cambio pero si el cwd", { let a = through("Read", ["file_path": "/p/a.txt"]); return a?.rawCommand == nil && a?.change == nil && a?.cwd == "/Users/x/miproyecto" }())

        // contenido hostil y enorme: el encuadre aguanta y el tope se respeta
        let hostileText = "a\tb\u{0}c\r\n\u{1B}[31m" + String(repeating: "linea con tab\t y comillas \" y barra \\\n", count: 50)
        let hz = through("Write", ["file_path": work + "/h.txt", "content": hostileText])
        check("Write con tabuladores, nulos y saltos llega sin partir el mensaje", hz?.change?.shape == .newFile && hz?.change?.added == 51)
        check("y lo dibujado no lleva controles", hz?.change?.lines.allSatisfy { !$0.text.unicodeScalars.contains { $0.value < 32 } } ?? false)
        let hugeContent = (0..<6000).map { "linea numero \($0) con algo de texto" }.joined(separator: "\n")
        let hg = through("Write", ["file_path": existing, "content": hugeContent])
        check("un Write enorme se recorta, avisa de lo omitido y no se compara a medias", hg?.change?.partial == true && hg?.change?.shape == .rewriteUncompared && (hg?.change?.added ?? 0) == 6000 && (hg?.change?.lines.count ?? 0) <= ChangeWire.maxShownLines)
        let emojis = String(repeating: "😀é", count: 30000)
        let em = through("Write", ["file_path": work + "/e.txt", "content": emojis])
        check("un Write de emojis recortado por el hook no deja utf-8 partido", em?.change.map { c in c.lines.allSatisfy { !$0.text.unicodeScalars.contains("\u{FFFD}") } && !c.lines.isEmpty } ?? false)

        // compatibilidad: la linea de un hook nuevo vista por una app antigua y la de un hook antiguo vista por la app nueva
        let base = "perm\tabcd\tEdit\tproj\t1\t/p/a.swift"
        check("la marca del hook nuevo desaparece al limpiar el detalle: una app antigua ve lo de siempre", PermissionServer.parse(base + "\u{1F}")?.detail == "/p/a.swift" && PermissionServer.parse(base)?.detail == "/p/a.swift")
        check("solo la marca anuncia un segundo mensaje", PermissionServer.announcesPayload(base + "\u{1F}") && !PermissionServer.announcesPayload(base) && !PermissionServer.announcesPayload("perm\ta\tEdit\tp\t1"))
        func rawConn(_ bytes: Data) -> Int32 {
            let c = socket(AF_UNIX, SOCK_STREAM, 0); var addr = makeSockAddr(sock)!
            _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(c, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            bytes.withUnsafeBytes { _ = write(c, $0.baseAddress, bytes.count) }
            return c
        }
        func cleanup() { for a in server4.asks { server4.resolve(id: a.id, .deny) } }
        let first = Data((base + "\u{1F}\n").utf8)
        // hook antiguo: sin marca, sin segundo mensaje
        var c = rawConn(Data((base + "\n").utf8)); _ = waitAsk4(1)
        check("un hook antiguo crea el permiso al instante y sin cambio", server4.asks.first.map { $0.change == nil && $0.rawCommand == nil && $0.cwd == nil && $0.detail == "/p/a.swift" } ?? false)
        close(c); _ = waitAsk4(0)
        // hook nuevo con carga valida escrita en dos trozos
        let good = Data(#"{"k":"edit","cwd":"/c","p":"/p/a.swift","e":[{"o":{"t":"a","m":0},"n":{"t":"b","m":0}}]}"#.utf8)
        c = rawConn(first + Data("diff\t\(good.count)\n".utf8) + good.prefix(10)); usleep(100_000)
        good.dropFirst(10).withUnsafeBytes { _ = write(c, $0.baseAddress, good.count - 10) }
        check("la carga puede llegar en trozos", waitAsk4(1) && server4.asks.first?.change?.added == 1 && server4.asks.first?.cwd == "/c")
        close(c); _ = waitAsk4(0)
        // anuncia una carga que nunca llega: el permiso aparece igual tras el plazo, sin cambio
        let t1 = Date()
        c = rawConn(first)
        check("marca sin carga: el permiso aparece igual, sin cambio, tras el plazo", waitAsk4(1, timeout: 6) && server4.asks.first?.change == nil && Date().timeIntervalSince(t1) < 5)
        close(c); _ = waitAsk4(0)
        // cabecera invalida, tamano absurdo, carga que no es json, carga truncada, bytes sobrantes
        for (name, bytes) in [("cabecera invalida", Data("hola\n".utf8) + good),
                              ("tamano enorme", Data("diff\t99999999\n".utf8) + good),
                              ("tamano cero", Data("diff\t0\n".utf8)),
                              ("tamano negativo", Data("diff\t-5\n".utf8) + good),
                              ("no es json", Data("diff\t6\nabcdef".utf8)),
                              ("kind desconocido", Data("diff\t14\n{\"k\":\"rm -rf\"}".utf8))] as [(String, Data)] {
            c = rawConn(first + bytes)
            check("carga mala (\(name)): el permiso se crea sin cambio", waitAsk4(1, timeout: 6) && server4.asks.first?.change == nil && server4.asks.first?.detail == "/p/a.swift")
            close(c); _ = waitAsk4(0)
        }
        // bytes de mas despues de la carga no se leen como otra linea ni crean otro permiso
        c = rawConn(first + Data("diff\t\(good.count)\n".utf8) + good + Data("perm\tx\tBash\tp\t1\trm -rf /\n".utf8))
        usleep(300_000)
        check("lo que sobra tras la carga no inyecta otro permiso", server4.asks.count == 1 && server4.asks.first?.tool == "Edit")
        close(c); _ = waitAsk4(0)
        // una carga dentro de la linea: tabuladores en el contenido no crean campos
        let tabby = Data(#"{"k":"write","cwd":"/c","p":"/p/t","c":{"t":"a\tb\tc\nperm\tx\tBash\tp\t1\tmalo","m":0}}"#.utf8)
        c = rawConn(first + Data("diff\t\(tabby.count)\n".utf8) + tabby)
        check("tabuladores y saltos dentro del contenido no inyectan campos ni permisos", waitAsk4(1) && server4.asks.first?.tool == "Edit" && server4.asks.first?.detail == "/p/a.swift")
        close(c); cleanup(); _ = waitAsk4(0)

        // una app antigua (lee la primera linea, ignora lo demas y responde) sigue funcionando con el hook nuevo
        let oldSock = "/tmp/cp-old-\(getpid()).sock"
        unlink(oldSock)
        let ls = socket(AF_UNIX, SOCK_STREAM, 0); var oa = makeSockAddr(oldSock)!
        _ = withUnsafePointer(to: &oa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(ls, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        listen(ls, 4)
        final class Box: @unchecked Sendable { let l = NSLock(); var v = ""; func set(_ s: String) { l.lock(); v = s; l.unlock() }; func get() -> String { l.lock(); defer { l.unlock() }; return v } }
        let oldFirst = Box()
        DispatchQueue.global().async {
            let cfd = accept(ls, nil, nil); guard cfd >= 0 else { return }
            var data = Data(); var b = [UInt8](repeating: 0, count: 512)
            while !data.contains(0x0A) { let n = read(cfd, &b, b.count); if n <= 0 { break }; data.append(contentsOf: b[0..<n]) }
            oldFirst.set(String(decoding: data.prefix(upTo: data.firstIndex(of: 0x0A) ?? data.endIndex), as: UTF8.self))
            // como la app antigua: de ahi en adelante solo lee de a 64 bytes para notar que el hook murio
            DispatchQueue.global().async { var d = [UInt8](repeating: 0, count: 64); while read(cfd, &d, d.count) > 0 {} }
            usleep(300_000)
            _ = "allow\n".withCString { write(cfd, $0, 6) }
        }
        let (po, oo) = spawn(hookInput("Write", ["file_path": existing, "content": hugeContent]), sockPath: oldSock)
        let oldOut = finish(po, oo, timeout: 8)
        check("hook nuevo con app antigua: la primera linea es la de siempre (la marca es un control) y la respuesta llega", decision(oldOut)?["behavior"] as? String == "allow" && oldFirst.get().hasPrefix("perm\tchg12345\tWrite\tmiproyecto\t0\t\(existing)"))
        if decision(oldOut)?["behavior"] as? String != "allow" { print("  salida=[\(oldOut)] primera=[\(oldFirst.get().prefix(120))]") }
        close(ls); unlink(oldSock)

        // sin jq o con jq que falla no hay segundo mensaje y todo sigue como antes (el hook falla abierto)
        server4.stop()
        let server5 = PermissionServer(path: sock)
        try? server5.start()
        defer { server5.stop() }
        let t2 = Date()
        let (pn, on) = spawn(hookInput("Write", ["file_path": existing, "content": String(repeating: "z", count: 300_000)]), wait: "2")
        usleep(500_000)
        check("una entrada de mas de 256 KB sigue sin crear permiso (falla abierto)", server5.asks.isEmpty)
        _ = finish(pn, on, timeout: 4)
        check("y no tarda ni se cuelga", Date().timeIntervalSince(t2) < 5)

        print(failures == 0 ? "PERMISOS OK" : "PERMISOS FALLOS: \(failures)")
        return failures == 0
    }
}
