import Foundation
import Darwin

enum IslandCleanupSelfTest {
    static func run() -> Bool {
        let root = NSTemporaryDirectory() + "cleanup-\(UUID().uuidString)"; let path = root + "/.claude-pet/island-permissions"; let sock = "/tmp/cp-cleanup-\(getpid()).sock"
        try? FileManager.default.createDirectory(atPath: root + "/.claude-pet", withIntermediateDirectories: true); FileManager.default.createFile(atPath: path, contents: Data())
        let server = PermissionServer(path: sock); try? server.start()
        let question = [["question": "cierre", "options": [["label": "ok"]]]]
        let encoded = Data(try! JSONSerialization.data(withJSONObject: question)).base64EncodedString()
        let c = socket(AF_UNIX, SOCK_STREAM, 0); var addr = makeSockAddr(sock)!
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(c, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        _ = "ask\ts\tp\t\(encoded)\n".withCString { write(c, $0, strlen($0)) }; usleep(100_000)
        let hadQuestion = server.questions.count == 1
        server.stop(); close(c); IslandCleanup.removeFlag(home: root)
        let ok = hadQuestion && !FileManager.default.fileExists(atPath: sock) && server.questions.isEmpty && !FileManager.default.fileExists(atPath: path)
        try? FileManager.default.removeItem(atPath: root); unlink(sock); print(ok ? "LIMPIEZA OK" : "LIMPIEZA FALLOS"); return ok
    }
}
