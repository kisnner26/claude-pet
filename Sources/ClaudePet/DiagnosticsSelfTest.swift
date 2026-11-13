import Foundation

/// `ClaudePet --selftest-diag`: el registro no deja pasar rutas ni mensajes, y el estado de los componentes se recuerda.
enum DiagnosticsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        // codigo de error: dominio y numero, nunca el mensaje (que en Foundation trae la ruta)
        let home = NSHomeDirectory()
        let withPath = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: "no se pudo escribir en \(home)/secreto/notas.txt", NSFilePathErrorKey: "\(home)/secreto"])
        check("code-formato", Diag.code(withPath) == "NSCocoaErrorDomain:513")
        check("code-sin-ruta", !Diag.code(withPath).contains(home) && !Diag.code(withPath).contains("secreto"))
        check("code-posix", Diag.code(NSError(domain: NSPOSIXErrorDomain, code: 48)) == "NSPOSIXErrorDomain:48")

        // estados de componentes
        let name = "prueba-\(UUID().uuidString.prefix(6))"
        check("estado-inicial", ComponentStates.shared.snapshot()[name] == nil)
        Diag.socket(name, .up)
        check("estado-activo", ComponentStates.shared.snapshot()[name] == .up)
        Diag.socket(name, .failed("NSPOSIXErrorDomain:13"))
        check("estado-fallo", ComponentStates.shared.snapshot()[name]?.label == "error NSPOSIXErrorDomain:13")
        Diag.socket(name, .down)
        check("estado-parado", ComponentStates.shared.snapshot()[name]?.label == "parado")

        // texto de «copiar diagnostico»
        let user = NSUserName()
        let hostile = DiagnosticInfo(appVersion: "2.1.0", build: "7", packaged: true, macOS: "27.2.0", arch: "arm64", model: "Mac14,5", hasNotch: true, language: "es",
                                    loginItem: "activado", features: [("relay", true), ("Meta Quest", false)],
                                    components: [("eventos", "activo"), ("permisos", "error \(home)/.claude-pet/ask.sock en /Users/\(user)/x")], plugins: (1, 3))
        let fake = DiagnosticReport.text(hostile)
        check("texto-version", fake.contains("claude-pet 2.1.0 (7)") && fake.contains("macOS 27.2.0") && fake.contains("Mac14,5"))
        check("texto-si-no", fake.contains("relay: sí") && fake.contains("Meta Quest: no") && fake.contains("notch: sí"))
        check("texto-sin-home", !fake.contains(home) && !fake.contains("/Users/\(user)"))
        check("texto-con-home-ajeno", !DiagnosticReport.text(hostile, home: "/Users/otra", user: "otra").contains("/Users/otra"))
        check("scrub-usuario-en-ruta", DiagnosticReport.scrub("/Users/ana/x y ana", home: "/Users/otra", user: "ana") == "/Users/usuario/x y ana")
        check("scrub-usuario-final-de-ruta", DiagnosticReport.scrub("en /Users/ana", home: "/Users/otra", user: "ana") == "en /Users/usuario")
        check("scrub-home", DiagnosticReport.scrub("/Users/ana/x", home: "/Users/ana", user: "ana") == "~/x")
        for u in ["mac", "pet", "app", "si", "no"] {
            let t = DiagnosticReport.text(hostile, home: "/Users/\(u)", user: u)
            check("usuario-\(u)-macOS", t.contains("macOS 27.2.0") && t.contains("claude-pet 2.1.0") && t.contains("notch: sí") && t.contains("abrir al iniciar sesión"))
        }
        check("scrub-home-raiz", DiagnosticReport.scrub("/ a", home: "/", user: "") == "/ a")
        check("componentes-sin-iniciar", DiagnosticReport.components(from: [:]).map(\.state) == Array(repeating: "sin iniciar", count: DiagnosticReport.componentOrder.count))
        check("componentes-estado", DiagnosticReport.components(from: ["bus": .up, "quest": .failed("X:1")]).filter { $0.name == "bus" || $0.name == "quest" }.map(\.state) == ["activo", "error X:1"])

        // el texto real de esta maquina: sin home, sin rutas y con cada funcion en sí/no
        let real = MainActor.assumeIsolated { DiagnosticReport.text(DiagnosticReport.gather(store: PetStore.shared)) }
        check("real-sin-home", !real.contains(home) && !real.contains("/Users/") && !real.contains("/private/") && !real.contains(".sock"))
        check("real-componentes", DiagnosticReport.componentOrder.allSatisfy { real.contains("  \($0): ") })
        let featureLines = real.components(separatedBy: "\n").drop { $0 != "funciones opcionales" }.dropFirst().prefix { !$0.isEmpty }
        check("real-funciones-si-no", featureLines.count >= 8 && featureLines.allSatisfy { $0.hasSuffix(": sí") || $0.hasSuffix(": no") || $0.contains("plugins activos: ") })
        check("real-corto", real.count < 1200 && real.components(separatedBy: "\n").count < 30)
        let lower = real.lowercased()
        check("real-sin-campos-prohibidos", !lower.contains("código de emparejamiento") && !lower.contains("comando") && !lower.contains("proyecto"))

        print(failures == 0 ? "DIAGNOSTICO OK" : "DIAGNOSTICO \(failures) FALLOS")
        return failures == 0
    }
}
