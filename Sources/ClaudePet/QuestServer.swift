import Foundation
import Network
import Security
import VistoCore

/// Soporte para Meta Quest 2 y Quest 3: la Mac sirve una pagina WebXR por HTTPS en tu red local y el navegador del visor la abre.
/// En el Quest 3 se ve en realidad mixta (con paso de camara); en el Quest 2 en realidad virtual o con el paso de camara en blanco y negro.
/// Se entra con el mismo codigo de emparejamiento de Visto; el canal va cifrado con TLS (certificado propio) y solo se puede permitir o denegar esta vez.
enum QuestHTTP {
    struct Request: Equatable { var method: String; var path: String; var query: [String: String]; var body: Data }

    enum Parsed: Equatable { case request(Request), needMore, bad }

    static let maxHead = 8 * 1024, maxBody = 4 * 1024

    /// Interpreta lo recibido de un golpe: cabecera, longitud del cuerpo y consulta. Todo lo raro es `bad`.
    static func parse(_ data: Data) -> Parsed {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return data.count > maxHead ? .bad : .needMore }
        guard end.lowerBound <= maxHead, let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .bad }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, ["GET", "POST"].contains(String(parts[0])), parts[2].hasPrefix("HTTP/1.") else { return .bad }
        var length = 0
        for l in lines.dropFirst() {
            let kv = l.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "content-length" { guard let n = Int(kv[1]), n >= 0, n <= maxBody else { return .bad }; length = n }
        }
        let body = data[end.upperBound...]
        if body.count < length { return .needMore }
        guard let comps = URLComponents(string: String(parts[1])), comps.path.hasPrefix("/") else { return .bad }
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { if let v = item.value, q.count < 8 { q[item.name] = String(v.prefix(64)) } }
        return .request(Request(method: String(parts[0]), path: comps.path, query: q, body: Data(body.prefix(length))))
    }

    /// Solo se sirven dos archivos, con nombre fijo: nada de rutas que lleguen a otros sitios.
    static func file(for path: String) -> (name: String, type: String)? {
        switch path {
        case "/", "/index.html": return ("index.html", "text/html; charset=utf-8")
        case "/three.js": return ("three.module.min.js", "text/javascript; charset=utf-8")
        default: return nil
        }
    }

    static func response(_ status: Int, type: String = "text/plain; charset=utf-8", body: Data = Data(), extra: [String] = []) -> Data {
        let names = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 429: "Too Many Requests", 409: "Conflict"]
        var head = "HTTP/1.1 \(status) \(names[status] ?? "OK")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n"
        for e in extra { head += e + "\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    /// Comparacion del codigo sin atajos por longitud de coincidencia.
    static func codeMatches(_ given: String, _ real: String) -> Bool {
        let a = Array(Pairing.normalize(given).utf8), b = Array(Pairing.normalize(real).utf8)
        guard a.count == b.count, !b.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    struct Answer: Equatable { var id: String; var allow: Bool }
    static func decodeAnswer(_ body: Data) -> Answer? {
        guard let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let id = o["id"] as? String, !id.isEmpty, id.count < 80, let a = o["action"] as? String, ["allow", "deny"].contains(a) else { return nil }
        return Answer(id: id, allow: a == "allow")
    }
}

/// Certificado propio de la Mac para el HTTPS local: se crea una vez en ~/.claude-pet/quest con el openssl del sistema.
enum QuestIdentity {
    static func load(dir: String = NSHomeDirectory() + "/.claude-pet/quest") -> SecIdentity? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = dir + "/key.pem", cert = dir + "/cert.pem", p12 = dir + "/identity.p12"
        if !fm.fileExists(atPath: p12) {
            func run(_ args: [String]) -> Bool {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); p.arguments = args
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
            }
            guard run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "825", "-subj", "/CN=claude-pet", "-addext", "subjectAltName=DNS:claude-pet.local"]),
                  run(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "pass:claudepet"]) else { return nil }
            chmod(key, 0o600); chmod(p12, 0o600)
        }
        guard let data = fm.contents(atPath: p12) else { return nil }
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: "claudepet"] as CFDictionary, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first, let id = first[kSecImportItemIdentity as String] else { return nil }
        return (id as! SecIdentity)
    }
}

final class QuestServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "claude-pet.quest")
    private var listener: NWListener?
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private var failures: [Date] = []
    private let webDir: String
    private(set) var port: UInt16 = 0
    var code: () -> String = { "" }
    var snapshot: () -> Data = { Data("{}".utf8) }
    /// Devuelve el motivo si se rechaza, o nil si se aplico.
    var onAnswer: (String, Bool) -> String? = { _, _ in nil }
    var onClients: (Int) -> Void = { _ in }

    init(webDir: String = QuestServer.defaultWebDir) { self.webDir = webDir }

    static var defaultWebDir: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_QUEST_DIR"], !p.isEmpty { return p }
        return (Bundle.main.resourcePath ?? ".") + "/quest"
    }

    func start(port wanted: UInt16 = 8787, identity: SecIdentity? = QuestIdentity.load()) throws {
        guard listener == nil else { return }
        guard let identity else { throw NSError(domain: "quest", code: 1, userInfo: [NSLocalizedDescriptionKey: "no se pudo crear el certificado"]) }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity)!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let l = try NWListener(using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()), on: NWEndpoint.Port(rawValue: wanted) ?? 8787)
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { [weak self, weak l] s in
            if case .ready = s { self?.port = l?.port?.rawValue ?? wanted; ready.signal() }
            if case .failed = s { ready.signal() }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        _ = ready.wait(timeout: .now() + 3)
        guard port != 0 else { l.cancel(); throw NSError(domain: "quest", code: 2, userInfo: [NSLocalizedDescriptionKey: "no se pudo abrir el puerto \(wanted)"]) }
        listener = l
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in self?.heartbeat() }
    }

    func stop() {
        listener?.cancel(); listener = nil; port = 0
        queue.async { [weak self] in self?.streams.values.forEach { $0.cancel() }; self?.streams = [:]; self?.onClients(0) }
    }

    /// Corta a todos los visores conectados sin parar el servidor: se usa al cambiar el codigo, para que quien lo tenia no siga viendo nada.
    func disconnectAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.streams.values.forEach { $0.cancel() }
            self.streams = [:]
            self.onClients(0)
        }
    }

    /// Empuja el estado actual a los visores conectados.
    func push() {
        queue.async { [weak self] in
            guard let self, !self.streams.isEmpty else { return }
            let frame = Data("data: ".utf8) + self.snapshot() + Data("\n\n".utf8)
            for (id, c) in self.streams { c.send(content: frame, completion: .contentProcessed { [weak self] e in if e != nil { self?.drop(id) } }) }
        }
    }

    private func heartbeat() {
        guard listener != nil else { return }
        for (id, c) in streams { c.send(content: Data(": ping\n\n".utf8), completion: .contentProcessed { [weak self] e in if e != nil { self?.drop(id) } }) }
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in self?.heartbeat() }
    }

    private func drop(_ id: ObjectIdentifier) { queue.async { [weak self] in self?.streams[id]?.cancel(); self?.streams[id] = nil; self?.onClients(self?.streams.count ?? 0) } }

    // MARK: conexiones

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        c.stateUpdateHandler = { [weak c] s in if case .failed = s { c?.cancel() } }
        read(c, buffer: Data())
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak c] in      // una conexion que no habla en 10 s se cierra
            guard let self, let c, self.streams[ObjectIdentifier(c)] == nil, c.state != .cancelled else { return }
            if !self.handled.contains(ObjectIdentifier(c)) { c.cancel() }
        }
    }

    private var handled: Set<ObjectIdentifier> = []

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer; if let data { buf.append(data) }
            switch QuestHTTP.parse(buf) {
            case .request(let r): self.handled.insert(ObjectIdentifier(c)); self.route(r, on: c)
            case .bad: self.finish(c, QuestHTTP.response(400))
            case .needMore: if err == nil, !done { self.read(c, buffer: buf) } else { c.cancel() }
            }
        }
    }

    private func finish(_ c: NWConnection, _ data: Data) {
        c.send(content: data, completion: .contentProcessed { _ in c.cancel() })
    }

    /// Tras 5 codigos malos en un minuto, todo se rechaza con 429 hasta que pase.
    private func tooManyFailures() -> Bool {
        failures.removeAll { Date().timeIntervalSince($0) > 60 }
        return failures.count >= 5
    }

    private func authorized(_ r: QuestHTTP.Request) -> Bool {
        if tooManyFailures() { return false }
        let ok = QuestHTTP.codeMatches(r.query["c"] ?? "", code())
        if !ok { failures.append(Date()) }
        return ok
    }

    private func route(_ r: QuestHTTP.Request, on c: NWConnection) {
        if let f = QuestHTTP.file(for: r.path), r.method == "GET" {
            guard let data = FileManager.default.contents(atPath: webDir + "/" + f.name) else { return finish(c, QuestHTTP.response(404)) }
            return finish(c, QuestHTTP.response(200, type: f.type, body: data))
        }
        if r.path == "/events", r.method == "GET" {
            if tooManyFailures() { return finish(c, QuestHTTP.response(429)) }
            guard authorized(r) else { return finish(c, QuestHTTP.response(403)) }
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n"
            let first = Data(head.utf8) + Data("retry: 2000\ndata: ".utf8) + snapshot() + Data("\n\n".utf8)
            streams[ObjectIdentifier(c)] = c
            onClients(streams.count)
            c.stateUpdateHandler = { [weak self, weak c] s in
                if case .cancelled = s, let c { self?.queue.async { self?.streams[ObjectIdentifier(c)] = nil; self?.onClients(self?.streams.count ?? 0) } }
                if case .failed = s { c?.cancel() }
            }
            c.send(content: first, completion: .contentProcessed { [weak self] e in if e != nil { self?.drop(ObjectIdentifier(c)) } })
            return
        }
        if r.path == "/answer", r.method == "POST" {
            if tooManyFailures() { return finish(c, QuestHTTP.response(429)) }
            guard authorized(r) else { return finish(c, QuestHTTP.response(403)) }
            guard let a = QuestHTTP.decodeAnswer(r.body) else { return finish(c, QuestHTTP.response(400)) }
            if let why = onAnswer(a.id, a.allow) { return finish(c, QuestHTTP.response(409, body: Data(why.utf8))) }
            return finish(c, QuestHTTP.response(200, body: Data("ok".utf8)))
        }
        finish(c, QuestHTTP.response(404))
    }

    /// Direccion de la Mac en la red local (Wi-Fi o cable), para escribirla en el navegador del visor.
    static func lanAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard i.ifa_addr.pointee.sa_family == UInt8(AF_INET), Int32(i.ifa_flags) & IFF_UP != 0, Int32(i.ifa_flags) & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: i.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(i.ifa_addr, socklen_t(i.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { best = best ?? String(cString: host); if name == "en0" { return String(cString: host) } }
        }
        return best
    }
}
