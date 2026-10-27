import Foundation
import Darwin

enum IslandResistanceSelfTest {
    static func run() -> Bool {
        let sock = "/tmp/cp-resistance-\(getpid()).sock"; let server = PermissionServer(path: sock); try? server.start(); defer { server.stop(); unlink(sock) }
        let raw = [["header": "x", "question": "continuar?", "options": [["label": "sí", "description": ""]]]]
        let encoded = Data(try! JSONSerialization.data(withJSONObject: raw)).base64EncodedString()
        for i in 0..<500 {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0, var address = makeSockAddr(sock) else { continue }
            let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            if connected == 0 { let line = i % 2 == 0 ? "ask\ts\tp\t\(encoded)\n" : "perm\ts\tBash\tp\t0\ttrue\n"; _ = line.withCString { write(fd, $0, strlen($0)) }; if i % 3 == 0 { close(fd) } else { usleep(500); close(fd) } } else { close(fd) }
        }
        usleep(300_000)
        let ok = server.questions.isEmpty && server.asks.isEmpty
        print(ok ? "RESISTENCIA OK" : "RESISTENCIA FALLOS: preguntas=\(server.questions.count) permisos=\(server.asks.count)")
        return ok
    }
}
