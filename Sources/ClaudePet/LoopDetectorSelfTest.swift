import Foundation

/// `ClaudePet --selftest-loops`: patrones de repeticion y silencio tras avisar.
enum LoopDetectorSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        var d = LoopDetector()
        check("dos errores iguales no avisan", d.record(tool: "Bash", target: "swift build", failed: true, at: 0) == nil && d.record(tool: "Bash", target: "swift build", failed: true, at: 5) == nil)
        let a = d.record(tool: "Bash", target: "swift build", failed: true, at: 10)
        check("el tercer error igual avisa", a?.reason == .repeatedError && a?.count == 3)
        check("no repite el aviso enseguida", d.record(tool: "Bash", target: "swift build", failed: true, at: 15) == nil)
        _ = d.record(tool: "Bash", target: "swift build", failed: true, at: 400); _ = d.record(tool: "Bash", target: "swift build", failed: true, at: 401)
        check("vuelve a avisar tras el silencio si el patron continua", d.record(tool: "Bash", target: "swift build", failed: true, at: 402)?.count == 3)

        d = LoopDetector()
        _ = d.record(tool: "Bash", target: "swift build", failed: true, at: 0)
        _ = d.record(tool: "Bash", target: "swift build", failed: true, at: 1)
        check("un acierto en medio corta la racha", d.record(tool: "Bash", target: "swift build", failed: false, at: 2) == nil && d.record(tool: "Bash", target: "swift build", failed: true, at: 3) == nil)
        d = LoopDetector()
        _ = d.record(tool: "Bash", target: "a", failed: true, at: 0); _ = d.record(tool: "Bash", target: "b", failed: true, at: 1)
        check("errores distintos no son un bucle", d.record(tool: "Bash", target: "c", failed: true, at: 2) == nil)
        d = LoopDetector()
        _ = d.record(tool: "Bash", target: "x", failed: true, at: 0); _ = d.record(tool: "Bash", target: "x", failed: true, at: 100)
        check("fuera de la ventana de 5 min no cuenta", d.record(tool: "Bash", target: "x", failed: true, at: 500) == nil)

        d = LoopDetector()
        var search: LoopAlert?
        for i in 0..<4 { search = d.record(tool: "Grep", target: "TODO", failed: false, at: Double(i)) }
        check("la misma busqueda 4 veces avisa", search?.reason == .repeatedSearch)
        d = LoopDetector()
        var read: LoopAlert?
        for i in 0..<10 { read = d.record(tool: "Read", target: "a.swift", failed: false, at: Double(i)) }
        check("leer el mismo archivo muchas veces no es bucle", read == nil)
        d = LoopDetector()
        var edit: LoopAlert?
        for i in 0..<6 { edit = d.record(tool: "Edit", target: "/p/a.swift", failed: false, at: Double(i)) }
        check("editar el mismo archivo 6 veces avisa", edit?.reason == .repeatedEdit)
        d = LoopDetector()
        var mixed: LoopAlert?
        for i in 0..<12 { mixed = d.record(tool: "Edit", target: i % 2 == 0 ? "/p/a" : "/p/b", failed: false, at: Double(i)) }
        check("alternar archivos no cuenta como repeticion seguida", mixed == nil)
        check("el aviso describe el patron sin contenido", a?.summary == "Bash · swift build · 3 veces seguidas" && a?.title.contains("posible bucle") == true)
        d = LoopDetector()
        let long = String(repeating: "x", count: 500)
        _ = d.record(tool: "Bash", target: long, failed: true, at: 0); _ = d.record(tool: "Bash", target: long, failed: true, at: 1)
        check("el objetivo se recorta a 120 caracteres", d.record(tool: "Bash", target: long, failed: true, at: 2)?.target.count == 120)

        print(failures == 0 ? "BUCLES OK" : "BUCLES FALLOS: \(failures)")
        return failures == 0
    }
}
