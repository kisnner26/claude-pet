import Foundation

enum SecretDetectorSelfTest {
    static func run() -> Bool {
        let cases: [(String, String, Bool)] = [("echo $TOKEN", "", true), ("echo sk-live-123456", "", true), ("cat .env", "", true), ("-----BEGIN PRIVATE KEY-----", "", true), ("cat x", "", false)]
        let ok = cases.allSatisfy { (SecretDetector.find(in: $0.0, path: $0.1) != nil) == $0.2 }
        print(ok ? "SECRETOS OK" : "SECRETOS FALLOS")
        return ok
    }
}
