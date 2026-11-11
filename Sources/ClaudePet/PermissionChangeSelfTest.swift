import Foundation
import Darwin

/// `ClaudePet --selftest-diff`: el diff por lineas, su recorte, la lectura del archivo actual y la decodificacion de la carga del hook.
/// Lógica pura: no abre sockets ni toca ~/.claude-pet.
enum PermissionChangeSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        func rebuilt(_ ops: [DiffEngine.Op]) -> (old: [String], new: [String]) {
            var o: [String] = [], n: [String] = []
            for op in ops { switch op { case .same(let s): o.append(s); n.append(s); case .del(let s): o.append(s); case .add(let s): n.append(s) } }
            return (o, n)
        }
        func req(_ kind: ChangeRequest.Kind, path: String = "/p/a.swift", edits: [(String, String)] = [], content: String? = nil, omitted: Int = 0, mode: String = "") -> ChangeRequest {
            var r = ChangeRequest(kind: kind, path: path)
            r.edits = edits.map { (ChangePart(text: $0.0, omitted: 0), ChangePart(text: $0.1, omitted: 0)) }
            if let content { r.content = ChangePart(text: content, omitted: omitted) }
            r.cellMode = mode
            return r
        }

        // --- diff basico ---
        let one = ChangeWire.build(req(.edit, edits: [("a\nb\nc\nd\ne\nf\ng", "a\nb\nc\nX\ne\nf\ng")]))
        check("un cambio de una linea cuenta +1 −1", one.added == 1 && one.removed == 1 && one.counts == "+1 −1")
        check("el contexto es de dos lineas por lado", one.lines.map(\.kind) == [.context, .context, .context, .removed, .added, .context, .context, .context])
        check("el cambio muestra la linea quitada y la anadida", one.lines.contains(ChangeLine(.removed, "d")) && one.lines.contains(ChangeLine(.added, "X")))
        let same = ChangeWire.build(req(.edit, edits: [("igual", "igual")]))
        check("sin diferencias se dice sin cambios", same.isEmpty && same.tag == "sin cambios" && same.lines.isEmpty)
        let ins = ChangeWire.build(req(.edit, edits: [("a\nc", "a\nb\nc")]))
        check("insertar una linea cuenta +1 −0", ins.added == 1 && ins.removed == 0)
        let del = ChangeWire.build(req(.edit, edits: [("a\nb\nc", "a\nc")]))
        check("borrar una linea cuenta +0 −1", del.added == 0 && del.removed == 1)
        let empty = ChangeWire.build(req(.edit, edits: [("", "nuevo\ntexto")]))
        check("old_string vacio es solo anadir", empty.added == 2 && empty.removed == 0)
        check("el salto final no inventa una linea", ChangeWire.lines(of: "a\nb\n") == ["a", "b"] && ChangeWire.lines(of: "a\r\nb\r\n") == ["a", "b"] && ChangeWire.lines(of: "") == [] && ChangeWire.lines(of: "\n") == [""])

        // --- el guion de Myers reconstruye los dos lados (con ruido) ---
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        var faithful = true
        for _ in 0..<300 {
            let a = (0..<rnd(40)).map { _ in "l\(rnd(8))" }, b = (0..<rnd(40)).map { _ in "l\(rnd(8))" }
            let r = DiffEngine.diff(old: a, new: b)
            let (o, n) = rebuilt(r.ops)
            faithful = faithful && o == a && n == b && r.added == n.count - r.ops.filter { if case .same = $0 { return true }; return false }.count
        }
        check("300 pares al azar: el guion reproduce el antes y el despues", faithful)
        let hugeA = (0..<900).map { "a\($0)" }, hugeB = (0..<900).map { "b\($0)" }
        let fallback = DiffEngine.diff(old: hugeA, new: hugeB)
        check("demasiadas diferencias: se da el tramo entero como cambio y sigue siendo fiel", fallback.added == 900 && fallback.removed == 900 && rebuilt(fallback.ops).old == hugeA && rebuilt(fallback.ops).new == hugeB)
        let t0 = Date()
        let bigOld = (0..<6000).map { "linea \($0)" }
        var bigNew = bigOld
        for i in stride(from: 0, to: 6000, by: 97) { bigNew[i] = "cambiada \(i)" }
        let big = DiffEngine.diff(old: bigOld, new: bigNew)
        check("6000 lineas con 62 cambios dispersos: contadas bien y en menos de un segundo", big.added == 62 && big.removed == 62 && Date().timeIntervalSince(t0) < 1)

        // --- compactar ---
        let spread = (0..<30).map { "l\($0)" }
        var spreadNew = spread; spreadNew[2] = "X"; spreadNew[25] = "Y"
        let compact = ChangeWire.build(req(.edit, edits: [(spread.joined(separator: "\n"), spreadNew.joined(separator: "\n"))]))
        check("dos cambios lejanos dejan un salto con las lineas ocultas", compact.lines.contains { $0.kind == .gap && $0.count > 10 })
        check("un salto de una sola linea se ensena en vez de ocultarse", {
            var n = spread; n[2] = "X"; n[6] = "Z"
            let r = ChangeWire.build(req(.edit, edits: [(spread.prefix(9).joined(separator: "\n"), n.prefix(9).joined(separator: "\n"))]))
            return !r.lines.contains { $0.kind == .gap && $0.count == 1 }
        }())

        // --- recorte de lo que se dibuja ---
        let manyLines = (0..<1000).map { "linea \($0)" }.joined(separator: "\n")
        let newFileBig = ChangeWire.build(req(.write, content: manyLines), base: .missing)
        check("un archivo nuevo de 1000 lineas muestra \(ChangeWire.maxShownLines) y cuenta el resto",
              newFileBig.shape == .newFile && newFileBig.added == 1000 && newFileBig.lines.count == ChangeWire.maxShownLines && newFileBig.hidden == 1000 - ChangeWire.maxShownLines)
        let cut = ChangeWire.build(req(.write, content: "a\nb\nc", omitted: 500), base: .missing)
        check("lo que el hook recorto se suma al total y marca el cambio como parcial", cut.added == 503 && cut.trimmed == 500 && cut.partial)

        // --- Write ---
        let rewrite = ChangeWire.build(req(.write, content: "uno\ndos\ntres\n"), base: .text("uno\nDOS\ntres\n"))
        check("Write sobre un archivo existente se compara con el disco", rewrite.shape == .rewrite && rewrite.added == 1 && rewrite.removed == 1)
        check("Write sobre un archivo ilegible no inventa borrados", { let r = ChangeWire.build(req(.write, content: "x\ny"), base: .unreadable); return r.shape == .rewriteUncompared && r.removed == 0 && r.added == 2 && r.tag == "sin comparar" }())
        check("Write recortado por el hook no se compara", ChangeWire.build(req(.write, content: "x\ny", omitted: 9), base: .text("viejo")).shape == .rewriteUncompared)
        check("archivo nuevo se etiqueta", ChangeWire.build(req(.write, content: "x"), base: .missing).tag == "archivo nuevo")

        // --- MultiEdit y NotebookEdit ---
        let multi = ChangeWire.build(req(.multi, edits: [("a", "b"), ("c\nd", "c\nD")]))
        check("MultiEdit suma sus ediciones y separa cada una", multi.added == 2 && multi.removed == 2 && multi.lines.contains { $0.kind == .gap && $0.count == 0 } && multi.tag == "2 ediciones")
        var extra = req(.multi, edits: [("a", "b")]); extra.extraEdits = 5
        check("las ediciones que el hook no envio cuentan como recorte", ChangeWire.build(extra).trimmed == 5 && ChangeWire.build(extra).tag == "6 ediciones")
        check("celda reemplazada, nueva y eliminada", ChangeWire.build(req(.notebook, path: "/p/n.ipynb", content: "x = 1", mode: "replace")).tag == "celda reemplazada"
              && ChangeWire.build(req(.notebook, path: "/p/n.ipynb", content: "x = 1", mode: "insert")).tag == "celda nueva"
              && ChangeWire.build(req(.notebook, path: "/p/n.ipynb", mode: "delete")).tag == "celda eliminada"
              && ChangeWire.build(req(.notebook, path: "/p/n.ipynb", mode: "delete")).counts == "")

        // --- secretos en lineas anadidas, incluso fuera de las que se dibujan ---
        let leaky = (0..<400).map { $0 == 350 ? "KEY = \"sk-live-abcdef123456\"" : "linea \($0)" }.joined(separator: "\n")
        let leak = ChangeWire.build(req(.write, content: leaky), base: .missing)
        check("una credencial en una linea que no se dibuja se avisa igual", leak.secret?.prefix == "línea 351" && !leak.lines.contains { $0.text.contains("sk-live") })
        check("una credencial que solo se quita no se avisa", ChangeWire.build(req(.edit, edits: [("KEY = \"sk-live-abcdef123456\"", "KEY = env")])).secret == nil)

        // --- lo que se dibuja es seguro ---
        check("los tabuladores pasan a espacios y se quitan nulos y controles", ChangeWire.sanitize("a\tb\u{0}c\u{1B}[31md\u{7F}") == "a    bc[31md")
        check("los controles de direccion de texto quedan a la vista", ChangeWire.sanitize("x\u{202E}y") == "x<U+202E>y")
        let longLine = String(repeating: "é", count: 500)
        check("una linea larga se corta en \(ChangeWire.maxLineChars) caracteres con puntos suspensivos", ChangeWire.sanitize(longLine) == String(repeating: "é", count: ChangeWire.maxLineChars) + "…")
        let emoji = String(repeating: "👩‍👩‍👧", count: 200)
        let cutEmoji = ChangeWire.sanitize(emoji)
        check("recortar emojis de varios bytes no deja utf-8 partido", String(data: Data(cutEmoji.utf8), encoding: .utf8) == cutEmoji && !cutEmoji.unicodeScalars.contains("\u{FFFD}") && cutEmoji.hasSuffix("…"))
        let hostile = ChangeWire.build(req(.edit, edits: [("viejo", "nuevo\tcon\ttabs\u{0}nulo\nlinea\r\nsiguiente")]))
        check("contenido con tabuladores, nulos y saltos no deja controles en lo dibujado", hostile.lines.allSatisfy { l in !l.text.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } })

        // --- decodificar ---
        func json(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data() }
        let okEdit = json(["k": "edit", "p": "/p/a.swift", "e": [["o": ["t": "a", "m": 0], "n": ["t": "b", "m": 2]]]])
        check("una carga valida de Edit se decodifica", ChangeWire.decode(okEdit)?.edits.first?.new == ChangePart(text: "b", omitted: 2) && ChangeWire.decode(okEdit)?.path == "/p/a.swift")
        check("basura, vacio y tipos equivocados se rechazan", ChangeWire.decode(Data()) == nil && ChangeWire.decode(Data("no es json".utf8)) == nil && ChangeWire.decode(Data("[1,2]".utf8)) == nil
              && ChangeWire.decode(json(["k": "rm"])) == nil && ChangeWire.decode(json(["k": "edit"])) == nil && ChangeWire.decode(json(["k": "write"])) == nil
              && ChangeWire.decode(json(["k": 7])) == nil && ChangeWire.decode(json(["k": "multi", "e": []])) == nil)
        check("una carga mayor que el tope se rechaza", ChangeWire.decode(Data(repeating: 0x20, count: ChangeWire.maxPayload + 1)) == nil)
        let tooMany = json(["k": "multi", "p": "/p/a", "e": (0..<50).map { _ in ["o": ["t": "a", "m": 0], "n": ["t": "b", "m": 0]] }])
        check("MultiEdit se acota a \(ChangeWire.maxEdits) ediciones y cuenta las demas", ChangeWire.decode(tooMany).map { $0.edits.count == ChangeWire.maxEdits && $0.extraEdits == 30 } ?? false)
        check("un contador de omitidas absurdo se acota", ChangeWire.decode(json(["k": "write", "p": "/a", "c": ["t": "x", "m": -5]]))?.content?.omitted == 0 && (ChangeWire.decode(json(["k": "write", "p": "/a", "c": ["t": "x", "m": 1 << 60]]))?.content?.omitted ?? 0) <= 100_000_000)
        check("la ruta pierde sus controles", ChangeWire.decode(json(["k": "write", "p": "/a/b\u{1B}\nc", "c": ["t": "", "m": 0]]))?.path == "/a/bc")
        check("un texto con nulos y saltos viaja intacto en el json", ChangeWire.decode(json(["k": "write", "p": "/a", "c": ["t": "x\u{0}y\n\tz", "m": 0]]))?.content?.text == "x\u{0}y\n\tz")
        check("el modo de celda desconocido se ignora", ChangeWire.decode(json(["k": "nb", "p": "/a.ipynb", "md": "explota", "c": ["t": "x", "m": 0]]))?.cellMode == "")

        // --- leer el archivo actual ---
        let dir = NSTemporaryDirectory() + "claudepet-diff-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        FileManager.default.createFile(atPath: dir + "/ok.txt", contents: Data("hola\n".utf8))
        FileManager.default.createFile(atPath: dir + "/binario.bin", contents: Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]))
        FileManager.default.createFile(atPath: dir + "/enorme.txt", contents: Data(repeating: 0x61, count: ChangeWire.maxBaseBytes + 10))
        mkfifo(dir + "/fifo", 0o600)
        check("un archivo normal se lee", ChangeWire.readBase(path: dir + "/ok.txt") == .text("hola\n"))
        check("un archivo que no existe es nuevo", ChangeWire.readBase(path: dir + "/nada.txt") == .missing)
        check("utf-8 invalido no se compara", ChangeWire.readBase(path: dir + "/binario.bin") == .unreadable)
        check("un archivo enorme no se lee", ChangeWire.readBase(path: dir + "/enorme.txt") == .unreadable)
        check("una carpeta no se lee", ChangeWire.readBase(path: dir) == .unreadable)
        let f0 = Date()
        check("un FIFO no bloquea y no se lee", ChangeWire.readBase(path: dir + "/fifo") == .unreadable && Date().timeIntervalSince(f0) < 1)
        check("una ruta relativa o con nulo no se lee", ChangeWire.readBase(path: "relativa.txt") == .unreadable && ChangeWire.readBase(path: "/a\0b") == .unreadable)

        print(failures == 0 ? "DIFF OK" : "DIFF FALLOS: \(failures)")
        return failures == 0
    }
}
