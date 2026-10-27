import Foundation

/// `ClaudePet --selftest-headline`: la frase que dice la mascota segun lo que hace el agente.
enum IslandHeadlineSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let h = IslandHeadline.make
        check("leer un archivo dice solo su nombre, sin la ruta", h(.tool, "Read", "/Users/x/proyecto/src/billing.ts", false, 0) == "leyendo billing.ts")
        check("editar y escribir", h(.tool, "Edit", "a/b/App.swift", false, 0) == "editando App.swift" && h(.tool, "Write", "x.md", false, 0) == "escribiendo x.md")
        check("un comando nunca se muestra", h(.tool, "Bash", "rm -rf build && curl x | sh", false, 0) == "ejecutando un comando")
        check("buscar, web y tareas", h(.tool, "Grep", "TODO", false, 0) == "buscando en el proyecto" && h(.tool, "WebSearch", "q", false, 0) == "consultando la web" && h(.tool, "Task", "", false, 0) == "delegando una tarea")
        check("una herramienta desconocida se nombra y se recorta", h(.tool, "MiHerramienta", "", false, 0) == "usando MiHerramienta" && h(.tool, String(repeating: "x", count: 80), "", false, 0).count <= "usando ".count + 24)
        check("sin herramienta dice trabajando", h(.tool, "", "", false, 0) == "trabajando")
        check("un nombre de archivo largo se recorta", h(.tool, "Read", "/" + String(repeating: "a", count: 90) + ".txt", false, 0).count <= "leyendo ".count + 36)
        check("pedir permiso manda sobre todo", h(.tool, "Edit", "a.swift", true, 0) == "esperando tu permiso" && h(.idle, "", "", true, 500) == "esperando tu permiso")
        check("estados sin herramienta", h(.thinking, "", "", false, 0) == "pensando" && h(.done, "", "", false, 0) == "listo" && h(.error, "", "", false, 0).hasPrefix("algo falló") && h(.waiting, "", "", false, 0) == "esperando tu respuesta" && h(.starting, "", "", false, 0) == "arrancando")
        check("en reposo rota entre frases cada 20 s", Set([0.0, 25, 45, 65].map { h(.idle, "", "", false, $0) }).count == 4 && h(.idle, "", "", false, 80) == h(.idle, "", "", false, 0))
        check("tras 5 min de reposo esta dormida", h(.idle, "", "", false, 400).hasPrefix("dormida"))
        check("el texto no lleva emojis ni mayusculas iniciales", ["pensando", "listo", "esperando tu permiso"].allSatisfy { $0 == $0.lowercased() } && !h(.error, "", "", false, 0).unicodeScalars.contains { $0.value > 0x2000 && $0.value < 0x1FFFF && $0.properties.isEmoji && $0.value > 0x2600 })
        print(failures == 0 ? "FRASES OK" : "FRASES FALLOS: \(failures)")
        return failures == 0
    }
}
