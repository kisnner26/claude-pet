import Foundation

enum ConfigSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let valid = try? JSONEncoder().encode(ClaudePetConfig.defaults)
        check("decodifica configuración vigente", valid.flatMap { try? ConfigStore.decode($0) } == .defaults)
        check("rechaza campos desconocidos", (try? ConfigStore.decode(Data(#"{"version":1,"wat":true}"#.utf8))) == nil)
        check("rechaza versión futura", (try? ConfigStore.decode(Data(#"{"version":99}"#.utf8))) == nil)
        check("rechaza escala fuera de rango", (try? ConfigStore.decode(Data(#"{"version":1,"textScale":9}"#.utf8))) == nil)
        check("rechaza json truncado", (try? ConfigStore.decode(Data(#"{"version":1"#.utf8))) == nil)
        print(failures == 0 ? "CONFIG OK" : "CONFIG FALLOS")
        return failures == 0
    }
}
