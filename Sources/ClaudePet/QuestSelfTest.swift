import Foundation
import VistoCore

/// `ClaudePet --selftest-quest [carpeta-web]`: el analizador HTTP, las rutas permitidas, el codigo, y un servidor TLS real contra un cliente que acepta el certificado propio.
enum QuestSelfTest {
    final class Trust: NSObject, URLSessionDelegate, URLSessionDataDelegate {
        var stream = Data()
        let got = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finished.signal() }
        func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge, completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let t = c.protectionSpace.serverTrust { h(.useCredential, URLCredential(trust: t)) } else { h(.performDefaultHandling, nil) }
        }
        func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { stream.append(data); got.signal() }
    }

    static func run(web: String) -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func req(_ s: String) -> QuestHTTP.Parsed { QuestHTTP.parse(Data(s.utf8)) }

        // analizador
        if case .request(let r) = req("GET /events?c=ABCD HTTP/1.1\r\nHost: x\r\n\r\n") { check("GET con consulta", r.method == "GET" && r.path == "/events" && r.query["c"] == "ABCD") } else { check("GET con consulta", false) }
        if case .request(let r) = req("POST /answer?c=1 HTTP/1.1\r\nContent-Length: 11\r\n\r\n{\"id\":\"a\"}x") { check("POST con cuerpo exacto", r.body.count == 11 && r.method == "POST") } else { check("POST con cuerpo exacto", false) }
        check("cuerpo a medias pide mas", req("POST /answer HTTP/1.1\r\nContent-Length: 50\r\n\r\n{}") == .needMore)
        check("cabecera a medias pide mas", req("GET / HTTP/1.1\r\nHost: x") == .needMore)
        check("metodo raro se rechaza", req("DELETE / HTTP/1.1\r\n\r\n") == .bad && req("PUT /x HTTP/1.1\r\n\r\n") == .bad)
        check("linea de peticion rota se rechaza", req("GET\r\n\r\n") == .bad && req("GET / FTP/1.0\r\n\r\n") == .bad && req("GET nada HTTP/1.1\r\n\r\n") == .bad)
        check("cuerpo enorme se rechaza", req("POST /answer HTTP/1.1\r\nContent-Length: 999999\r\n\r\n") == .bad && req("POST /a HTTP/1.1\r\nContent-Length: -3\r\n\r\n") == .bad)
        check("cabecera enorme se rechaza", QuestHTTP.parse(Data(repeating: 65, count: 20_000)) == .bad)
        check("binario basura se rechaza", QuestHTTP.parse(Data([0xff, 0xfe, 0, 1, 2, 13, 10, 13, 10])) == .bad)

        // rutas y codigo
        check("solo dos archivos se sirven", QuestHTTP.file(for: "/")?.name == "index.html" && QuestHTTP.file(for: "/three.js")?.name == "three.module.min.js" && QuestHTTP.file(for: "/../Info.plist") == nil
              && QuestHTTP.file(for: "/index.html/../../etc/passwd") == nil && QuestHTTP.file(for: "/quest/index.html") == nil && QuestHTTP.file(for: "/%2e%2e/x") == nil)
        check("codigo: igual con guiones y minusculas", QuestHTTP.codeMatches("abcd-efgh-jkmn", "ABCDEFGHJKMN") && !QuestHTTP.codeMatches("ABCDEFGHJKMX", "ABCDEFGHJKMN") && !QuestHTTP.codeMatches("", "") && !QuestHTTP.codeMatches("ABC", "ABCDEFGHJKMN"))
        check("respuestas validas", QuestHTTP.decodeAnswer(Data(#"{"id":"a1","action":"allow"}"#.utf8)) == .init(id: "a1", allow: true) && QuestHTTP.decodeAnswer(Data(#"{"id":"a1","action":"deny"}"#.utf8)) == .init(id: "a1", allow: false))
        check("respuestas invalidas: siempre no existe desde el visor", QuestHTTP.decodeAnswer(Data(#"{"id":"a1","action":"always"}"#.utf8)) == nil && QuestHTTP.decodeAnswer(Data(#"{"id":"","action":"allow"}"#.utf8)) == nil
              && QuestHTTP.decodeAnswer(Data("no json".utf8)) == nil && QuestHTTP.decodeAnswer(Data(#"{"id":"\#(String(repeating: "x", count: 200))","action":"allow"}"#.utf8)) == nil)
        check("respuesta HTTP con longitud y sin cache", String(data: QuestHTTP.response(200, body: Data("hola".utf8)), encoding: .utf8)?.contains("Content-Length: 4") == true && String(data: QuestHTTP.response(404), encoding: .utf8)?.contains("Cache-Control: no-store") == true)

        // servidor real
        let dir = NSTemporaryDirectory() + "quest-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        guard let identity = QuestIdentity.load(dir: dir) else { print("FALLO no se pudo crear el certificado"); return false }
        check("el certificado se guarda con permisos privados", ((try? FileManager.default.attributesOfItem(atPath: dir + "/key.pem"))?[.posixPermissions] as? Int) == 0o600)
        let code = Pairing.newCode()
        let server = QuestServer(webDir: web)
        server.code = { code }
        server.snapshot = { Data(#"{"host":"Mac de prueba","asks":[],"agents":[],"plan":null}"#.utf8) }
        nonisolated(unsafe) var answered: (String, Bool)?
        server.onAnswer = { id, allow in answered = (id, allow); return id == "viejo" ? "caducó" : nil }
        do { try server.start(port: UInt16(20_000 + Int.random(in: 0..<5_000)), identity: identity) } catch { print("FALLO el servidor no arranca: \(error)"); return false }
        defer { server.stop() }
        let base = "https://127.0.0.1:\(server.port)"
        let trust = Trust()
        let session = URLSession(configuration: .ephemeral, delegate: trust, delegateQueue: nil)

        func fetch(_ path: String, method: String = "GET", body: String? = nil) -> (Int, Data) {
            var r = URLRequest(url: URL(string: base + path)!); r.httpMethod = method; r.timeoutInterval = 8
            if let body { r.httpBody = Data(body.utf8) }
            let sem = DispatchSemaphore(value: 0); nonisolated(unsafe) var out: (Int, Data) = (0, Data())
            session.dataTask(with: r) { d, resp, _ in out = ((resp as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data()); sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + 10)
            return out
        }

        let index = fetch("/")
        check("la pagina se sirve por TLS", index.0 == 200 && String(data: index.1, encoding: .utf8)?.contains("claude") == true)
        let three = fetch("/three.js")
        check("three.js se sirve", three.0 == 200 && three.1.count > 100_000)
        check("rutas fuera de lista dan 404", fetch("/../Info.plist").0 == 404 && fetch("/etc/passwd").0 == 404 && fetch("/index.html/../x").0 == 404)
        check("sin codigo no hay eventos ni respuestas", fetch("/events").0 == 403 && fetch("/answer", method: "POST", body: #"{"id":"a","action":"allow"}"#).0 == 403)
        let ok = fetch("/answer?c=\(code)", method: "POST", body: #"{"id":"nuevo","action":"allow"}"#)
        check("con codigo la respuesta llega a la app", ok.0 == 200 && answered?.0 == "nuevo" && answered?.1 == true)
        check("si la app la rechaza, el visor se entera", fetch("/answer?c=\(code)", method: "POST", body: #"{"id":"viejo","action":"deny"}"#).0 == 409)
        check("cuerpo roto es 400", fetch("/answer?c=\(code)", method: "POST", body: "basura").0 == 400)

        // flujo de eventos
        var r = URLRequest(url: URL(string: base + "/events?c=\(code)")!); r.timeoutInterval = 20
        let task = session.dataTask(with: r); task.resume()
        _ = trust.got.wait(timeout: .now() + 6)
        check("el flujo manda el estado al conectar", String(data: trust.stream, encoding: .utf8)?.contains("Mac de prueba") == true)
        server.snapshot = { Data(#"{"host":"Mac de prueba","asks":[{"id":"x1"}],"agents":[],"plan":null}"#.utf8) }
        server.push()
        _ = trust.got.wait(timeout: .now() + 4)
        check("push entrega el cambio", String(data: trust.stream, encoding: .utf8)?.contains("x1") == true)
        // al cambiar el codigo, el visor conectado se corta y el codigo viejo deja de valer
        nonisolated(unsafe) var current = code
        server.code = { current }
        let newCode = Pairing.newCode()
        current = newCode
        server.disconnectAll()
        check("al cambiar el codigo se corta el visor conectado", trust.finished.wait(timeout: .now() + 4) == .success)
        check("el codigo viejo ya no entra y el nuevo si", fetch("/answer?c=\(code)", method: "POST", body: #"{"id":"z","action":"allow"}"#).0 == 403 && fetch("/answer?c=\(newCode)", method: "POST", body: #"{"id":"z","action":"allow"}"#).0 == 200)
        task.cancel()

        // intentos de adivinar el codigo
        for _ in 0..<5 { _ = fetch("/events?c=AAAAAAAAAAAA") }
        check("tras cinco codigos malos se frena (429), incluso con el bueno", fetch("/events?c=\(newCode)").0 == 429)

        print(failures == 0 ? "QUEST OK" : "QUEST \(failures) FALLOS")
        return failures == 0
    }
}
