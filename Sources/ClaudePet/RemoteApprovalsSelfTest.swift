import Foundation
import Darwin

/// `ClaudePet --selftest-remote`: politica (riesgo alto, caducidad, "siempre" inexistente) y el socket real con un cliente de prueba.
enum RemoteApprovalsSelfTest {
    private final class TestClient {
        let fd: Int32
        var buffer = ""
        init?(path: String) {
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0, var addr = makeSockAddr(path) else { return nil }
            let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard ok == 0 else { close(fd); return nil }
            var tv = timeval(tv_sec: 0, tv_usec: 300_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        func send(_ s: String) { _ = (s + "\n").withCString { write(fd, $0, strlen($0)) } }
        /// Lineas que llegan en la ventana de espera.
        func lines(wait: Int = 20) -> [[String: Any]] {
            for _ in 0..<wait {
                var b = [UInt8](repeating: 0, count: 4096)
                let n = read(fd, &b, b.count)
                if n > 0 { buffer += String(decoding: b[0..<n], as: UTF8.self) } else { break }
            }
            let parts = buffer.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            buffer = ""
            return parts.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        }
        func closed() -> Bool { var b = [UInt8](repeating: 0, count: 8); return read(fd, &b, 8) == 0 }
        deinit { close(fd) }
    }

    static func run() -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let now = Date()
        func ask(_ id: String, _ tool: String, _ detail: String, age: TimeInterval = 0) -> PermissionAsk {
            PermissionAsk(id: id, session: "s", tool: tool, project: "proy", detail: detail, canAlways: true, at: now.addingTimeInterval(-age))
        }
        let low = ask("a1", "Read", "README.md"), medium = ask("a2", "Bash", "swift build"), high = ask("a3", "Bash", "rm -rf build")

        check("bajo y medio se pueden permitir desde fuera", RemoteWire.verdict(for: .allow, ask: low, now: now) == nil && RemoteWire.verdict(for: .allow, ask: medium, now: now) == nil)
        check("riesgo alto no se permite desde fuera", RemoteWire.verdict(for: .allow, ask: high, now: now)?.contains("Mac") == true)
        check("riesgo alto sí se puede denegar desde fuera", RemoteWire.verdict(for: .deny, ask: high, now: now) == nil)
        check("permiso caducado se rechaza", RemoteWire.verdict(for: .allow, ask: ask("a4", "Read", "x", age: 200), now: now) == "caducó")
        check("permiso inexistente se rechaza", RemoteWire.verdict(for: .allow, ask: nil, now: now) != nil)

        check("respuesta valida: permitir", RemoteWire.parseAnswer(#"{"t":"answer","id":"a1","d":"allow"}"#)?.decision == .allow)
        check("respuesta valida: denegar", RemoteWire.parseAnswer(#"{"t":"answer","id":"a1","d":"deny"}"#)?.decision == .deny)
        check("«siempre» no existe desde fuera", RemoteWire.parseAnswer(#"{"t":"answer","id":"a1","d":"always"}"#) == nil)
        check("respuesta rara se descarta", RemoteWire.parseAnswer("basura") == nil && RemoteWire.parseAnswer(#"{"t":"answer","d":"allow"}"#) == nil && RemoteWire.parseAnswer(#"{"t":"ask","id":"a","d":"allow"}"#) == nil && RemoteWire.parseAnswer(#"{"t":"answer","id":"","d":"allow"}"#) == nil)
        check("línea demasiado larga se descarta", RemoteWire.parseAnswer(#"{"t":"answer","id":"\#(String(repeating: "x", count: 600))","d":"allow"}"#) == nil)

        let long = ask("a5", "Bash", String(repeating: "x", count: 900))
        let line = (try? JSONSerialization.jsonObject(with: Data(RemoteWire.askLine(long).utf8))) as? [String: Any]
        check("el detalle se recorta a 300", (line?["detail"] as? String)?.count == 300)
        check("la línea lleva riesgo y caducidad", line?["risk"] as? String != nil && (line?["expires"] as? Int ?? 0) > Int(now.timeIntervalSince1970))
        check("comillas y saltos se escapan sin romper el JSON", (try? JSONSerialization.jsonObject(with: Data(RemoteWire.askLine(ask("a6", "Bash", "echo \"hola\"\nmundo \\ fin")).utf8))) != nil)

        // socket real
        let path = "/tmp/cp-remote-\(getpid()).sock"
        defer { unlink(path) }
        let server = RemoteApprovalServer(path: path)
        let got = NSLock(); var answers: [(String, PermissionDecision)] = []
        server.onAnswer = { id, d in got.lock(); answers.append((id, d)); got.unlock() }
        do { try server.start() } catch { print("FALLO no abre el socket: \(error)"); return false }
        var st = stat(); stat(path, &st)
        check("el socket es solo del usuario (0600)", st.st_mode & 0o077 == 0)

        server.sync([low, medium, high])      // llegan antes de que nadie se conecte
        let c1 = TestClient(path: path)
        check("un cliente se conecta", c1 != nil)
        let first = c1?.lines() ?? []
        check("saluda", first.first?["t"] as? String == "hello")
        check("quien se conecta tarde ve los tres pendientes", first.filter { $0["t"] as? String == "ask" }.compactMap { $0["id"] as? String }.sorted() == ["a1", "a2", "a3"])
        check("el de riesgo alto llega marcado", first.first { $0["id"] as? String == "a3" }?["risk"] as? String == "alto")

        c1?.send(#"{"t":"answer","id":"a2","d":"allow"}"#)
        Thread.sleep(forTimeInterval: 0.2)
        got.lock(); let applied = answers; got.unlock()
        check("permitir uno de riesgo medio llega a la app", applied.count == 1 && applied[0].0 == "a2" && applied[0].1 == .allow)

        c1?.send(#"{"t":"answer","id":"a3","d":"allow"}"#)
        let refused = c1?.lines() ?? []
        got.lock(); let afterHigh = answers.count; got.unlock()
        check("permitir uno de riesgo alto se rechaza y no llega a la app", refused.contains { $0["t"] as? String == "refused" && $0["id"] as? String == "a3" } && afterHigh == 1)

        c1?.send(#"{"t":"answer","id":"a3","d":"deny"}"#)
        Thread.sleep(forTimeInterval: 0.2)
        got.lock(); let afterDeny = answers; got.unlock()
        check("denegar uno de riesgo alto sí llega", afterDeny.count == 2 && afterDeny[1].1 == .deny)

        c1?.send(#"{"t":"answer","id":"nope","d":"allow"}"#)
        check("responder a un id que no existe se rechaza", (c1?.lines() ?? []).contains { $0["t"] as? String == "refused" })

        server.sync([low])
        let gone = c1?.lines() ?? []
        check("los que se resuelven en la Mac se retiran del dispositivo", Set(gone.filter { $0["t"] as? String == "gone" }.compactMap { $0["id"] as? String }) == ["a2", "a3"])
        server.sync([low, ask("a7", "Edit", "Sources/x.swift")])
        check("un permiso nuevo se envía una sola vez", (c1?.lines() ?? []).filter { $0["t"] as? String == "ask" }.compactMap { $0["id"] as? String } == ["a7"])
        server.sync([low, ask("a7", "Edit", "Sources/x.swift")])
        check("sin cambios no repite nada", (c1?.lines() ?? []).isEmpty)

        c1?.send("{\"t\":\"answer\",\"id\":\"" + String(repeating: "z", count: 5000))
        Thread.sleep(forTimeInterval: 0.2)
        check("un cliente que manda basura sin fin se corta", c1?.closed() == true)

        let c2 = TestClient(path: path), c3 = TestClient(path: path), c4 = TestClient(path: path)
        _ = c2?.lines()
        check("como mucho dos puentes a la vez", c2 != nil && c3 != nil && (c4?.closed() ?? true))
        server.stop()
        check("al parar se borra el socket", !FileManager.default.fileExists(atPath: path))
        server.sync([low])

        print(failures == 0 ? "REMOTO OK" : "REMOTO \(failures) FALLOS")
        return failures == 0
    }
}
