import Foundation
import Darwin

/// Aprobar permisos desde otro dispositivo (iPhone, Apple Watch) a traves de un puente local, por ejemplo Nexo.
/// Es opt-in. El puente se conecta a `~/.claude-pet/remote.sock` (0600, solo el mismo usuario) y habla por lineas JSON:
///   claude pet -> puente   {"t":"ask","id","tool","project","detail","risk","expires"}   {"t":"gone","id"}   {"t":"refused","id","why"}
///   puente -> claude pet   {"t":"answer","id","d":"allow"|"deny"}
/// Desde fuera solo se puede permitir o denegar esta vez (nunca "siempre"), y lo de riesgo alto solo se puede denegar:
/// aprobarlo exige estar delante de la Mac. El perimetro y las reglas ya se aplicaron antes de que un permiso llegue aqui.
enum RemoteWire {
    static let maxDetail = 300
    static let maxLine = 512
    /// El hook deja de esperar a los 110 s; con margen para no ofrecer un permiso que ya no existe.
    static let lifetime: TimeInterval = 105

    static func risk(of ask: PermissionAsk) -> PermissionRisk {
        PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk
    }

    static func askLine(_ ask: PermissionAsk) -> String {
        let obj: [String: Any] = ["t": "ask", "id": ask.id, "tool": ask.tool, "project": ask.project,
                                  "detail": String(ask.detail.prefix(maxDetail)), "risk": risk(of: ask).rawValue,
                                  "expires": Int(ask.at.timeIntervalSince1970 + lifetime)]
        return json(obj)
    }
    static func goneLine(_ id: String) -> String { json(["t": "gone", "id": id]) }
    static func refusedLine(_ id: String, _ why: String) -> String { json(["t": "refused", "id": id, "why": why]) }

    private static func json(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func parseAnswer(_ line: String) -> (id: String, decision: PermissionDecision)? {
        guard line.utf8.count <= maxLine, let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              o["t"] as? String == "answer", let id = o["id"] as? String, !id.isEmpty, id.count <= 64,
              let d = o["d"] as? String else { return nil }
        switch d { case "allow": return (id, .allow); case "deny": return (id, .deny); default: return nil }      // "always" no existe desde fuera
    }

    /// Quien responde y por que se rechaza: la politica, sin red ni sockets.
    static func verdict(for decision: PermissionDecision, ask: PermissionAsk?, now: Date) -> String? {
        guard let ask else { return "ya no está pendiente" }
        if now.timeIntervalSince(ask.at) > lifetime { return "caducó" }
        if decision == .allow, risk(of: ask) == .high { return "riesgo alto: apruébalo en la Mac" }
        return nil
    }
}

final class RemoteApprovalServer: @unchecked Sendable {
    static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_REMOTE_SOCK"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/remote.sock"
    }
    static let maxClients = 2

    private final class Client {
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        init(fd: Int32) { self.fd = fd }
    }

    private let path: String
    private let queue = DispatchQueue(label: "claudepet.remote")
    private var fd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Client] = []
    private var current: [PermissionAsk] = []
    private var sent: Set<String> = []
    /// Se llama (en la cola del socket) con una respuesta ya validada por la politica. Devuelve si se aplico.
    var onAnswer: ((String, PermissionDecision) -> Void)?

    init(path: String = RemoteApprovalServer.defaultPath) { self.path = path }

    var clientCount: Int { queue.sync { clients.count } }

    func start() throws {
        try queue.sync {
            guard fd < 0 else { return }
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            chmod(dir, 0o700)
            unlink(path)
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { throw posix("socket") }
            guard var addr = makeSockAddr(path) else { close(s); throw NSError(domain: "ClaudePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "ruta de socket demasiado larga"]) }
            let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard bound == 0 else { close(s); throw posix("bind") }
            chmod(path, 0o600)
            guard listen(s, 4) == 0 else { close(s); throw posix("listen") }
            _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
            fd = s
            let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.resume()
            acceptSource = src
        }
    }

    func stop() {
        queue.sync {
            acceptSource?.cancel(); acceptSource = nil
            if fd >= 0 { close(fd); fd = -1 }
            unlink(path)
            for c in clients { c.source?.cancel(); close(c.fd) }
            clients = []; sent = []
        }
    }

    /// Lista actual de permisos pendientes: avisa de los nuevos y de los que ya no estan.
    func sync(_ asks: [PermissionAsk]) {
        queue.async { [self] in
            current = asks
            guard !clients.isEmpty else { sent = []; return }
            let ids = Set(asks.map(\.id))
            for gone in sent.subtracting(ids) { broadcast(RemoteWire.goneLine(gone)) }
            for ask in asks where !sent.contains(ask.id) { broadcast(RemoteWire.askLine(ask)) }
            sent = ids
        }
    }

    private func broadcast(_ line: String) { for c in clients { write(line, to: c) } }

    private func write(_ line: String, to c: Client) {
        let bytes = Array((line + "\n").utf8)
        var off = 0
        while off < bytes.count {
            let n = Darwin.write(c.fd, bytes, bytes.count - off) as Int
            if n < 0 { if errno == EINTR { continue }; drop(c); return }      // si el puente no lee, se le corta: nunca bloquea a claude pet
            off += n
            if n == 0 { drop(c); return }
        }
    }

    private func acceptPending() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(c, &uid, &gid) == 0, uid == getuid(), clients.count < Self.maxClients else { close(c); continue }
            _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK)
            var one: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let client = Client(fd: c)
            let src = DispatchSource.makeReadSource(fileDescriptor: c, queue: queue)
            src.setEventHandler { [weak self, weak client] in guard let self, let client else { return }; self.read(client) }
            client.source = src
            clients.append(client)
            src.resume()
            write(#"{"t":"hello","v":1}"#, to: client)
            for ask in current { write(RemoteWire.askLine(ask), to: client) }       // quien se conecta tarde ve lo que ya espera
            sent = Set(current.map(\.id))
        }
    }

    private func read(_ c: Client) {
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(c.fd, &buf, buf.count)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { drop(c); return }
        guard n > 0 else { return }
        c.buffer.append(contentsOf: buf[0..<n])
        if c.buffer.count > 4096 { drop(c); return }
        while let nl = c.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: c.buffer[c.buffer.startIndex..<nl], as: UTF8.self)
            c.buffer.removeSubrange(c.buffer.startIndex...nl)
            guard let a = RemoteWire.parseAnswer(line) else { continue }
            if let why = RemoteWire.verdict(for: a.decision, ask: current.first { $0.id == a.id }, now: Date()) {
                write(RemoteWire.refusedLine(a.id, why), to: c)
            } else {
                onAnswer?(a.id, a.decision)
            }
        }
    }

    private func drop(_ c: Client) {
        guard clients.contains(where: { $0 === c }) else { return }
        clients.removeAll { $0 === c }
        c.source?.cancel(); close(c.fd)
        if clients.isEmpty { sent = [] }
    }

    private func posix(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
