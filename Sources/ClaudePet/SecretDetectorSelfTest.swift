import Foundation

enum SecretDetectorSelfTest {
    static func run() -> Bool {
        let cases: [(String, String, Bool)] = [("echo $TOKEN", "", true), ("echo sk-live-123456", "", true), ("cat .env", "", true), ("-----BEGIN PRIVATE KEY-----", "", true), ("cat x", "", false)]
        var ok = cases.allSatisfy { (SecretDetector.find(in: $0.0, path: $0.1) != nil) == $0.2 }
        func check(_ name: String, _ pass: Bool) { if !pass { ok = false; print("FALLO \(name)") } }

        // lineas anadidas por un cambio
        check("una clave sk- en una linea anadida se detecta", SecretDetector.find(inLines: ["let a = 1", "let key = \"sk-live-abcdef123456\""])?.prefix == "línea 2")
        check("un bloque pem se detecta", SecretDetector.find(inLines: ["-----BEGIN RSA PRIVATE KEY-----"])?.label == "bloque pem")
        check("un token de github se detecta", SecretDetector.find(inLines: ["export GH=ghp_abcdefghijklmnop"]) != nil)
        check("api_key y secret= se detectan", SecretDetector.find(inLines: ["API_KEY: 1"]) != nil && SecretDetector.find(inLines: ["client_secret=abc"]) != nil)
        check("una clave de aws se detecta", SecretDetector.find(inLines: ["id = AKIAIOSFODNN7EXAMPLE"])?.label == "posible credencial akia")
        check("codigo normal no se marca", SecretDetector.find(inLines: ["let task = 1", "mask-image: none", "disk-cache", "process.env.NODE_ENV", "ask-user"]) == nil)
        check("process.env en una linea anadida no es un archivo de entorno", SecretDetector.find(inLines: ["const p = process.env.PORT"]) == nil)
        check("sk- sin cuerpo no se marca", SecretDetector.find(inLines: ["sk-"]) == nil)
        check("la pista no lleva caracteres de la credencial", !(SecretDetector.find(inLines: ["sk-live-abcdef123456"])?.prefix.contains("sk") ?? true))
        check("sin lineas no hay hallazgo", SecretDetector.find(inLines: []) == nil)
        check("los comandos siguen sin falsos positivos con task- y mask-", SecretDetector.find(in: "make task-list mask-all") == nil)
        print(ok ? "SECRETOS OK" : "SECRETOS FALLOS")
        return ok
    }
}
