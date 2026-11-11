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

        print(failures == 0 ? "DIAGNOSTICO OK" : "DIAGNOSTICO \(failures) FALLOS")
        return failures == 0
    }
}
