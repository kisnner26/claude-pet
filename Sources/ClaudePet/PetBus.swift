import Foundation
import Darwin

/// Mensaje del pet bus, version 1. Una linea de JSON, maximo 512 bytes.
/// Campos desconocidos se ignoran; `project` y `event` son opcionales.
struct BusMessage: Codable {
    var v: Int
    var id: String
    var state: String
    var project: String?
    var ts: Double
    var event: String?
}

struct Peer {
    var id: String
    var state: PetState
    var project: String?
    var lastTs: Double
    var seen: Date
}

/// Cliente de publicacion. Cada mascota escucha en `<dir>/<id>.sock` y publica en los demas
/// sockets del directorio. Si no hay nadie, no pasa nada.
enum PetBus {
    static let selfID = "claude"
    static let version = 1
    static let maxBytes = 512
    static var dir: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_BUS"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/bus"
    }
    static var ownSocket: String { dir + "/\(selfID).sock" }
    private static let queue = DispatchQueue(label: "claudepet.bus.publish")

    static func decode(_ line: String) -> BusMessage? {
        guard line.utf8.count <= maxBytes, let data = line.data(using: .utf8),
              let m = try? JSONDecoder().decode(BusMessage.self, from: data),
              m.v == version, m.id != selfID,
              m.id.range(of: "^[a-z0-9-]{1,16}$", options: .regularExpression) != nil else { return nil }
        return m
    }

    static func encode(_ m: BusMessage) -> Data? {
        guard var d = try? JSONEncoder().encode(m) else { return nil }
        d.append(0x0A)
        return d.count <= maxBytes ? d : nil
    }

    /// Publica a todos los pares presentes. `wait` bloquea (solo al salir).
    static func publish(_ m: BusMessage, wait: Bool = false) {
        guard let data = encode(m) else { return }
        let work = {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasSuffix(".sock") && $0 != "\(selfID).sock" }
                .prefix(8)
            for f in files { send(data, to: dir + "/" + f) }
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    private static func send(_ data: Data, to path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        guard var addr = makeSockAddr(path) else { return }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard r == 0 else { return }   // sin oyente (par ausente o socket huerfano): se ignora
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, data.count) }
    }
}
