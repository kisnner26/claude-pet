import Foundation
import Darwin

func makeSockAddr(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < cap else { return nil }
    withUnsafeMutablePointer(to: &addr.sun_path) { p in
        p.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
            _ = path.withCString { strncpy(dst, $0, cap - 1) }
        }
    }
    return addr
}

/// Servidor minimo sobre socket Unix (solo local, modo 0600, solo el mismo usuario).
/// Entrega cada linea recibida (max 1024 bytes por conexion; el bus impone sus 512 al decodificar) a `onLine`.
final class EventServer {
    static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_SOCK"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/pet.sock"
    }

    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue: DispatchQueue
    var onLine: ((String) -> Void)?

    init(path: String = EventServer.defaultPath) {
        self.path = path
        queue = DispatchQueue(label: "claudepet.socket." + (path as NSString).lastPathComponent)
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        unlink(path)

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posix("socket") }
        guard var addr = makeSockAddr(path) else {
            throw NSError(domain: "ClaudePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "ruta de socket demasiado larga"])
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw posix("bind") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { throw posix("listen") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptPending() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        if fd >= 0 { close(fd); fd = -1 }
        unlink(path)
    }

    private func acceptPending() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }
            handle(c)
        }
    }

    private func handle(_ c: Int32) {
        defer { close(c) }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { return }
        _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 256)
        while data.count < 1024 {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
            if data.contains(0x0A) { break }
        }
        let text = String(decoding: data.prefix(1024), as: UTF8.self)   // bytes invalidos -> U+FFFD, no se pierde la linea
        for line in text.split(separator: "\n") { onLine?(String(line)) }
    }

    private func posix(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}
