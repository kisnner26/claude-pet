import Foundation
import Darwin

/// Un permiso que Claude Code espera y que se puede responder desde la isla.
struct PermissionAsk: Identifiable, Equatable {
    let id: String
    let session: String
    let tool: String
    let project: String
    /// Lo que se va a ejecutar (comando, archivo o url), solo para mostrarlo en la isla. Vive en memoria; no se guarda ni cruza el pet bus.
    let detail: String
    /// Claude Code envio una regla sugerida, asi que "siempre permitir" tiene sentido.
    let canAlways: Bool
    let at: Date
    // Lo que sigue llega por el segundo mensaje del hook (ver docs/ISLAND.md). Solo en memoria mientras el permiso esta pendiente:
    // nunca va a disco, a la auditoria, al bus, a los plugins, al registro de diagnostico ni a Visto.
    /// El cambio de un Edit, MultiEdit, Write o NotebookEdit, ya calculado. nil con un hook antiguo.
    var change: ChangeDiff?
    /// `tool_input.command` de Bash, integro y sin limpiar. nil con un hook antiguo o si excede el tope.
    var rawCommand: String?
    /// Ruta completa del proyecto (`cwd`); `project` solo trae el nombre corto.
    var cwd: String?

    var clipboardText: String {
        var lines = ["permiso: \(tool)"]
        if !project.isEmpty { lines.append("proyecto: \(project)") }
        if !detail.isEmpty { lines.append("detalle: \(detail)") }
        return lines.joined(separator: "\n")
    }
}

enum PermissionDecision: String { case allow, always, deny }

/// Socket aparte del de eventos: el hook de permisos se queda esperando en la conexion hasta que llegue la respuesta.
/// Si la app no esta, no hay socket o se agota el plazo, el hook no devuelve decision y Claude Code pregunta en la terminal.
final class PermissionServer: @unchecked Sendable {
    static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_ASK_SOCK"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/ask.sock"
    }
    static let maxPending = 8
    static let maxLine = 4096

    private final class Conn {
        let fd: Int32
        let ask: PermissionAsk
        var source: DispatchSourceRead?
        var closed = false
        init(fd: Int32, ask: PermissionAsk) { self.fd = fd; self.ask = ask }
    }

    private let path: String
    private var fd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "claudepet.ask")
    private let lock = NSLock()
    private var pending: [Conn] = []
    /// Se llama (en el hilo del socket) cada vez que cambia la lista de permisos pendientes.
    var onChange: (([PermissionAsk]) -> Void)?
    var onQuestionsChange: (([QuestionAsk]) -> Void)?

    init(path: String = PermissionServer.defaultPath) { self.path = path }

    var asks: [PermissionAsk] { lock.lock(); defer { lock.unlock() }; return pending.map(\.ask) }
    var questions: [QuestionAsk] { lock.lock(); defer { lock.unlock() }; return questionPending.map(\.ask) }

    func start() throws {
        do { try bringUp(); Diag.socket("permisos", .up) }
        catch { Diag.socket("permisos", .failed(Diag.code(error))); throw error }
    }

    private func bringUp() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posix("socket") }
        guard var addr = makeSockAddr(path) else {
            throw NSError(domain: "ClaudePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "ruta de socket demasiado larga"])
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { throw posix("bind") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { throw posix("listen") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptPending() }
        src.resume()
        acceptSource = src
    }

    func stop() {
        acceptSource?.cancel()
        if fd >= 0 { close(fd); fd = -1 }
        unlink(path)
        lock.lock(); let all = pending; pending = []; lock.unlock()
        for c in all { finish(c, reply: nil) }
        lock.lock(); let questions = questionPending; questionPending = []; lock.unlock()
        for q in questions { q.closed = true; q.source?.cancel(); close(q.fd) }
        onQuestionsChange?([])
        onChange?([])
        Diag.socket("permisos", .down)
    }

    /// Responde a un permiso. Devuelve false si ya no estaba pendiente (lo resolvio otro o la terminal).
    @discardableResult
    func resolve(id: String, _ decision: PermissionDecision, source: String = "isla") -> Bool {
        lock.lock()
        guard let i = pending.firstIndex(where: { $0.ask.id == id }) else { lock.unlock(); return false }
        let c = pending.remove(at: i)
        let rest = pending.map(\.ask)
        lock.unlock()
        finish(c, reply: decision.rawValue)
        AuditLog.record(ask: c.ask, result: decision.rawValue, source: source)
        onChange?(rest)
        return true
    }

    @discardableResult
    func dismissPermission(id: String) -> Bool {
        lock.lock(); guard let i = pending.firstIndex(where: { $0.ask.id == id }) else { lock.unlock(); return false }
        let c = pending.remove(at: i); let rest = pending.map(\.ask); lock.unlock()
        finish(c, reply: nil); AuditLog.record(ask: c.ask, result: "terminal", source: "terminal"); onChange?(rest); return true
    }

    // MARK: conexiones

    private func acceptPending() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }
            handle(c)
        }
    }

    private func handle(_ c: Int32) {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { close(c); return }
        _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 512)
        while data.count <= Self.maxLine {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if data.contains(0x0A) { break }
        }
        // la linea mide como mucho maxLine; lo que venga despues del salto es el segundo mensaje (o nada)
        guard let nl = data.firstIndex(of: 0x0A), nl <= Self.maxLine else { close(c); return }
        let leftover = Data(data[(nl + 1)...])
        let line = String(decoding: data[..<nl], as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
        if let question = QuestionServer.parse(line) {
            // AskUserQuestion comparte el socket y queda abierto hasta la respuesta.
            let response = QuestionConn(fd: c, ask: question)
            // el limite se mira antes de crear la fuente de eventos: soltar una DispatchSource que nunca se activo aborta el proceso
            lock.lock(); guard questionPending.count < Self.maxPending else { lock.unlock(); close(c); return }; questionPending.append(response); lock.unlock()
            let src = DispatchSource.makeReadSource(fileDescriptor: c, queue: queue)
            src.setEventHandler { [weak self, weak response] in
                guard let self, let response, !response.closed else { return }
                var b = [UInt8](repeating: 0, count: 64); let n = read(response.fd, &b, b.count)
                if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { self.dropQuestion(response) }
            }
            response.source = src
            src.resume()
            lock.lock(); let questions = questionPending.map(\.ask); lock.unlock(); onQuestionsChange?(questions)
            return
        }
        lock.lock(); let full = pending.count >= Self.maxPending; lock.unlock()
        // lleno o linea invalida: se cierra sin respuesta y Claude Code pregunta en la terminal
        guard !full, var ask = Self.parse(line) else { close(c); return }
        if Self.announcesPayload(line), let raw = Self.readPayload(fd: c, leftover: leftover), let payload = ChangeWire.decodePayload(raw) {
            // fuera del hilo principal: leer el archivo y calcular el diff ocurre aqui, en la cola del socket
            ask.cwd = payload.cwd
            ask.rawCommand = payload.command
            if let req = payload.change { ask.change = ChangeWire.build(req, base: ChangeWire.readBase(path: req.path)) }
        }
        _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK)
        let conn = Conn(fd: c, ask: ask)
        // si el hook muere (respondiste en la terminal o se agoto su plazo) la conexion se cierra: se retira el permiso
        let src = DispatchSource.makeReadSource(fileDescriptor: c, queue: queue)
        src.setEventHandler { [weak self, weak conn] in
            guard let self, let conn, !conn.closed else { return }
            var b = [UInt8](repeating: 0, count: 64)
            let n = read(conn.fd, &b, b.count)
            if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { self.drop(conn) }
        }
        conn.source = src
        lock.lock(); pending.append(conn); let list = pending.map(\.ask); lock.unlock()
        src.resume()
        onChange?(list)
    }

    private final class QuestionConn { let fd: Int32; let ask: QuestionAsk; var source: DispatchSourceRead?; var closed = false; init(fd: Int32, ask: QuestionAsk) { self.fd = fd; self.ask = ask } }
    private var questionPending: [QuestionConn] = []

    @discardableResult
    func resolveQuestion(id: String, answers: [String: String]) -> Bool {
        lock.lock(); guard let i = questionPending.firstIndex(where: { $0.ask.id == id }) else { lock.unlock(); return false }; let q = questionPending.remove(at: i); lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: answers), let text = String(data: data, encoding: .utf8) else { close(q.fd); return false }
        q.closed = true; q.source?.cancel(); _ = (text + "\n").withCString { write(q.fd, $0, strlen($0)) }; close(q.fd)
        lock.lock(); let rest = questionPending.map(\.ask); lock.unlock(); onQuestionsChange?(rest); return true
    }

    @discardableResult
    func dismissQuestion(id: String) -> Bool {
        lock.lock(); guard let i = questionPending.firstIndex(where: { $0.ask.id == id }) else { lock.unlock(); return false }; let q = questionPending.remove(at: i); lock.unlock()
        q.closed = true; q.source?.cancel(); close(q.fd)
        lock.lock(); let rest = questionPending.map(\.ask); lock.unlock(); onQuestionsChange?(rest)
        return true
    }

    private func dropQuestion(_ q: QuestionConn) {
        lock.lock(); questionPending.removeAll { $0 === q }; lock.unlock()
        q.closed = true; q.source?.cancel(); close(q.fd)
        lock.lock(); let questions = questionPending.map(\.ask); lock.unlock(); onQuestionsChange?(questions)
    }

    private func drop(_ c: Conn) {
        lock.lock()
        let had = pending.contains { $0 === c }
        pending.removeAll { $0 === c }
        let rest = pending.map(\.ask)
        lock.unlock()
        finish(c, reply: nil)
        if had { onChange?(rest) }
    }

    private func finish(_ c: Conn, reply: String?) {
        guard !c.closed else { return }
        c.closed = true
        if let reply { _ = reply.appending("\n").withCString { write(c.fd, $0, strlen($0)) } }
        c.source?.cancel()
        close(c.fd)
    }

    /// Linea: `perm<TAB>sesion<TAB>herramienta<TAB>proyecto<TAB>siempre(0|1)<TAB>detalle`
    static func parse(_ line: String) -> PermissionAsk? {
        let p = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 5, p[0] == "perm" else { return nil }
        func clean(_ s: String, _ n: Int) -> String {
            String(s.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(n).map(Character.init))
        }
        let tool = clean(p[2], 40)
        guard !tool.isEmpty else { return nil }
        return PermissionAsk(id: UUID().uuidString, session: clean(p[1], 12), tool: tool, project: clean(p[3], 40),
                             detail: p.count > 5 ? clean(p[5], 400) : "", canAlways: p[4] == "1", at: Date())
    }

    /// El detalle termina en la marca de control: tras esta linea viene `diff<TAB>N<LF>` y N bytes de json.
    static func announcesPayload(_ line: String) -> Bool {
        let p = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
        return p.count > 5 && p[5].unicodeScalars.last == ChangeWire.marker
    }

    /// Lee el segundo mensaje con plazo propio. Cualquier fallo devuelve nil y el permiso sigue como en un hook antiguo.
    /// Lee solo lo anunciado: ni un byte de mas, asi el contenido no puede colarse como otra linea.
    static func readPayload(fd: Int32, leftover: Data, deadline: TimeInterval = 2) -> Data? {
        let end = Date().addingTimeInterval(deadline)
        var buf = leftover
        var chunk = [UInt8](repeating: 0, count: 8192)
        func more(_ limit: Int) -> Bool {
            guard Date() < end else { return false }
            let n = read(fd, &chunk, min(chunk.count, max(1, limit)))
            if n < 0 && errno == EINTR { return true }
            guard n > 0 else { return false }
            buf.append(contentsOf: chunk[0..<n])
            return true
        }
        while !buf.contains(0x0A) && buf.count <= 32 { if !more(32) { return nil } }
        guard let nl = buf.firstIndex(of: 0x0A), nl <= 32 else { return nil }
        let head = String(decoding: buf[..<nl], as: UTF8.self).split(separator: "\t", omittingEmptySubsequences: false)
        guard head.count == 2, head[0] == "diff", let size = Int(head[1]), size > 0, size <= ChangeWire.maxPayload else { return nil }
        var body = Data(buf[(nl + 1)...])
        while body.count < size {
            let before = body.count
            guard Date() < end else { return nil }
            let n = read(fd, &chunk, min(chunk.count, size - body.count))
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return nil }
            body.append(contentsOf: chunk[0..<n])
            if body.count == before { return nil }
        }
        return body.prefix(size)
    }

    private func posix(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
