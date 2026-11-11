import Foundation
import Darwin

/// Una linea del cambio tal como se dibuja en la tarjeta del permiso.
struct ChangeLine: Equatable {
    enum Kind: Equatable {
        case context, added, removed
        /// Tramo sin cambios que se oculta (`count` lineas) o, con `count` 0, el corte entre dos ediciones.
        case gap
    }
    let kind: Kind
    let text: String
    let count: Int
    init(_ kind: Kind, _ text: String = "", count: Int = 0) { self.kind = kind; self.text = text; self.count = count }
}

/// El cambio que pide un Edit, MultiEdit, Write o NotebookEdit, ya calculado y listo para mostrar.
/// Vive solo en memoria mientras el permiso esta pendiente: no se guarda, no entra en la auditoria ni sale hacia el bus, los plugins o el movil.
struct ChangeDiff: Equatable {
    enum Shape: Equatable {
        case edit
        case multiEdit(Int)
        case newFile
        case rewrite
        /// Write sobre un archivo que existe pero no se pudo comparar (muy grande, binario, ilegible o recortado por el hook).
        case rewriteUncompared
        case cellReplace, cellInsert, cellDelete
    }

    let shape: Shape
    let added: Int
    let removed: Int
    /// Lineas que se dibujan: cambios con poco contexto, ya recortadas a `ChangeWire.maxShownLines`.
    let lines: [ChangeLine]
    /// Lineas del cambio (anadidas, quitadas o de contexto) que no caben en `lines`.
    let hidden: Int
    /// Lineas que el hook recorto antes de enviar: el cambio real es mayor que lo que se ve.
    let trimmed: Int
    /// Algo con pinta de credencial en las lineas anadidas (se mira en todas, no solo en las que se dibujan).
    let secret: SecretFinding?

    var isEmpty: Bool { added == 0 && removed == 0 && shape != .cellDelete }
    var partial: Bool { trimmed > 0 }

    /// `+12 −3`; vacio si no hay cifras que dar (celda eliminada).
    var counts: String {
        switch shape {
        case .cellDelete: return ""
        case .newFile, .rewriteUncompared, .cellInsert, .cellReplace: return "+\(added)"
        default: return "+\(added) −\(removed)"
        }
    }

    /// Etiqueta en espanol (se traduce con `L.tr`), o vacia.
    var tag: String {
        switch shape {
        case .edit, .rewrite: return isEmpty ? "sin cambios" : ""
        case .multiEdit(let n): return "\(n) ediciones"
        case .newFile: return "archivo nuevo"
        case .rewriteUncompared: return "sin comparar"
        case .cellReplace: return "celda reemplazada"
        case .cellInsert: return "celda nueva"
        case .cellDelete: return "celda eliminada"
        }
    }
}

/// Texto que llega del hook: ya recortado por el, con cuantas lineas se quedaron fuera.
struct ChangePart: Equatable {
    var text: String
    var omitted: Int
}

/// Lo que el hook envio sobre el cambio, sin calcular nada todavia.
struct ChangeRequest: Equatable {
    enum Kind: String { case edit, multi, write, notebook }
    var kind: Kind
    var path: String
    var edits: [(old: ChangePart, new: ChangePart)] = []
    var extraEdits = 0
    var content: ChangePart?
    var cellMode = ""
    static func == (a: ChangeRequest, b: ChangeRequest) -> Bool {
        a.kind == b.kind && a.path == b.path && a.extraEdits == b.extraEdits && a.content == b.content && a.cellMode == b.cellMode
            && a.edits.count == b.edits.count && zip(a.edits, b.edits).allSatisfy { $0.old == $1.old && $0.new == $1.new }
    }
}

/// El archivo tal como esta ahora en el disco, para comparar un Write.
enum ChangeBase: Equatable {
    case missing
    case text(String)
    case unreadable
}

enum ChangeWire {
    /// Lo mas que se acepta de la carga del cambio. El hook envia como mucho 128 KiB.
    static let maxPayload = 160 * 1024
    static let maxEdits = 20
    static let maxPartChars = 64 * 1024
    static let maxLineChars = 240
    static let maxShownLines = 160
    static let contextLines = 2
    /// Un archivo en disco mayor que esto no se compara.
    static let maxBaseBytes = 512 * 1024
    /// Marca al final del detalle que dice «detras de esta linea viene el cambio». Es un caracter de control: los
    /// permisos antiguos lo descartan al limpiar el detalle, asi que un hook nuevo con una app vieja sigue igual que antes.
    static let marker: Unicode.Scalar = "\u{1F}"

    // MARK: decodificar

    /// `{"k":"edit|multi|write|nb","p":ruta,"e":[{"o":{"t":texto,"m":omitidas},"n":{...}}],"x":ediciones omitidas,"c":{...},"md":modo de celda}`
    static func decode(_ data: Data) -> ChangeRequest? {
        guard !data.isEmpty, data.count <= maxPayload,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = root["k"] as? String else { return nil }
        let kind: ChangeRequest.Kind
        switch raw {
        case "edit": kind = .edit
        case "multi": kind = .multi
        case "write": kind = .write
        case "nb": kind = .notebook
        default: return nil
        }
        var req = ChangeRequest(kind: kind, path: cleanPath(root["p"] as? String ?? ""))
        func part(_ any: Any?) -> ChangePart {
            guard let d = any as? [String: Any] else { return ChangePart(text: "", omitted: 0) }
            let text = String((d["t"] as? String ?? "").unicodeScalars.prefix(maxPartChars))
            let omitted = (d["m"] as? NSNumber)?.intValue ?? 0
            return ChangePart(text: text, omitted: min(max(0, omitted), 100_000_000))
        }
        if let list = root["e"] as? [Any] {
            for case let e as [String: Any] in list.prefix(maxEdits) { req.edits.append((part(e["o"]), part(e["n"]))) }
            req.extraEdits = max(0, list.count - maxEdits)
        }
        req.extraEdits += min(max(0, (root["x"] as? NSNumber)?.intValue ?? 0), 100_000)
        if root["c"] != nil { req.content = part(root["c"]) }
        if let md = root["md"] as? String, ["replace", "insert", "delete"].contains(md) { req.cellMode = md }
        switch kind {
        case .edit: guard req.edits.count == 1 else { return nil }
        case .multi: guard !req.edits.isEmpty else { return nil }
        case .write: guard req.content != nil else { return nil }
        case .notebook: guard req.content != nil || req.cellMode == "delete" else { return nil }
        }
        return req
    }

    private static func cleanPath(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(1024)))
    }

    // MARK: leer el archivo actual

    /// Lee el archivo que un Write va a pisar. Solo archivos normales (un FIFO o un dispositivo bloquearian), con tope de tamano.
    /// Se llama fuera del hilo principal.
    static func readBase(path: String) -> ChangeBase {
        guard path.hasPrefix("/"), !path.contains("\0") else { return .unreadable }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 { return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= off_t(maxBaseBytes) else { return .unreadable }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= maxBaseBytes {
            let n = read(fd, &buf, buf.count)
            if n < 0 { if errno == EINTR { continue }; return .unreadable }
            if n == 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        guard data.count <= maxBaseBytes, let text = String(data: data, encoding: .utf8) else { return .unreadable }
        return .text(text)
    }

    // MARK: calcular

    static func build(_ req: ChangeRequest, base: @autoclosure () -> ChangeBase = .unreadable) -> ChangeDiff {
        switch req.kind {
        case .edit, .multi:
            var all: [ChangeLine] = []
            var added = 0, removed = 0, trimmed = 0
            var addedText: [String] = []
            for (i, e) in req.edits.enumerated() {
                let pair = DiffEngine.diff(old: lines(of: e.old.text), new: lines(of: e.new.text))
                added += pair.added; removed += pair.removed
                trimmed += e.old.omitted + e.new.omitted
                addedText += pair.addedLines
                if i > 0 { all.append(ChangeLine(.gap)) }
                all += DiffEngine.compact(pair.ops, context: contextLines)
            }
            trimmed += req.extraEdits
            let shape: ChangeDiff.Shape = req.kind == .edit ? .edit : .multiEdit(req.edits.count + req.extraEdits)
            return finish(shape: shape, added: added, removed: removed, all: all, trimmed: trimmed, addedText: addedText)
        case .write:
            let content = req.content ?? ChangePart(text: "", omitted: 0)
            let new = lines(of: content.text)
            switch base() {
            case .missing:
                return finish(shape: .newFile, added: new.count, removed: 0, all: new.map { ChangeLine(.added, $0) }, trimmed: content.omitted, addedText: new,
                              addedExtra: content.omitted)
            case .text(let old) where content.omitted == 0:
                let pair = DiffEngine.diff(old: lines(of: old), new: new)
                return finish(shape: .rewrite, added: pair.added, removed: pair.removed, all: DiffEngine.compact(pair.ops, context: contextLines), trimmed: 0, addedText: pair.addedLines)
            default:
                // el hook recorto el contenido o el archivo no se pudo leer: se ensena lo que llego sin inventar borrados
                return finish(shape: .rewriteUncompared, added: new.count, removed: 0, all: new.map { ChangeLine(.added, $0) }, trimmed: content.omitted, addedText: new,
                              addedExtra: content.omitted)
            }
        case .notebook:
            let content = req.content ?? ChangePart(text: "", omitted: 0)
            let new = lines(of: content.text)
            switch req.cellMode {
            case "delete": return finish(shape: .cellDelete, added: 0, removed: 0, all: [], trimmed: 0, addedText: [])
            case "insert": return finish(shape: .cellInsert, added: new.count, removed: 0, all: new.map { ChangeLine(.added, $0) }, trimmed: content.omitted, addedText: new, addedExtra: content.omitted)
            default: return finish(shape: .cellReplace, added: new.count, removed: 0, all: new.map { ChangeLine(.added, $0) }, trimmed: content.omitted, addedText: new, addedExtra: content.omitted)
            }
        }
    }

    private static func finish(shape: ChangeDiff.Shape, added: Int, removed: Int, all: [ChangeLine], trimmed: Int, addedText: [String], addedExtra: Int = 0) -> ChangeDiff {
        let shown = Array(all.prefix(maxShownLines)).map(display)
        let hiddenLines = all.dropFirst(maxShownLines).filter { $0.kind != .gap }.count
        return ChangeDiff(shape: shape, added: added + addedExtra, removed: removed, lines: shown, hidden: hiddenLines, trimmed: trimmed,
                          secret: SecretDetector.find(inLines: addedText))
    }

    /// Lo que se dibuja: sin caracteres de control, sin tabuladores, con las lineas largas cortadas y con los controles de
    /// direccion de texto a la vista (un `\u{202E}` puede hacer que el codigo parezca otra cosa).
    private static func display(_ line: ChangeLine) -> ChangeLine {
        guard line.kind != .gap else { return line }
        return ChangeLine(line.kind, sanitize(line.text))
    }

    static func sanitize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var n = 0
        for u in s.unicodeScalars {
            if n >= maxLineChars { out.append("…"); break }
            switch u.value {
            case 9: out.append(contentsOf: "    ".unicodeScalars); n += 4
            case 0..<32, 127, 0x80..<0xA0: continue
            case 0x202A...0x202E, 0x2066...0x2069, 0x200E, 0x200F:
                out.append(contentsOf: "<U+\(String(u.value, radix: 16, uppercase: true))>".unicodeScalars); n += 8
            default: out.append(u); n += 1
            }
        }
        return String(out)
    }

    /// Divide en lineas sin inventar una linea vacia por el salto final; `\r\n` cuenta como un salto.
    static func lines(of text: String) -> [String] {
        if text.isEmpty { return [] }
        // por escalares: en Character, "\r\n" es un solo caracter y no se partiria
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            if u == "\n" {
                if cur.last == "\r" { cur.removeLast() }
                out.append(String(cur)); cur = String.UnicodeScalarView()
            } else { cur.append(u) }
        }
        out.append(String(cur))
        if text.unicodeScalars.last == "\n" { out.removeLast() }
        return out
    }
}

/// Diferencias por lineas (Myers) con prefijo y sufijo comunes recortados antes de buscar.
enum DiffEngine {
    enum Op: Equatable { case same(String), add(String), del(String) }
    struct Result { let ops: [Op]; let added: Int; let removed: Int; let addedLines: [String] }

    /// Cuantas ediciones se buscan antes de rendirse y dar el tramo del medio como borrado entero y escrito entero.
    static let maxEdits = 600

    static func diff(old: [String], new: [String]) -> Result {
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] { start += 1 }
        var endOld = old.count, endNew = new.count
        while endOld > start, endNew > start, old[endOld - 1] == new[endNew - 1] { endOld -= 1; endNew -= 1 }
        let a = Array(old[start..<endOld]), b = Array(new[start..<endNew])
        var ops: [Op] = old[..<start].map { .same($0) }
        ops += middle(a, b)
        ops += old[endOld...].map { .same($0) }
        var added = 0, removed = 0
        var addedLines: [String] = []
        for op in ops {
            switch op { case .add(let s): added += 1; addedLines.append(s); case .del: removed += 1; case .same: break }
        }
        return Result(ops: ops, added: added, removed: removed, addedLines: addedLines)
    }

    private static func middle(_ a: [String], _ b: [String]) -> [Op] {
        if a.isEmpty { return b.map { .add($0) } }
        if b.isEmpty { return a.map { .del($0) } }
        // las lineas se sustituyen por numeros para comparar rapido
        var ids: [String: Int] = [:]
        func id(_ s: String) -> Int { if let v = ids[s] { return v }; let v = ids.count; ids[s] = v; return v }
        let ia = a.map(id), ib = b.map(id)
        guard let script = myers(ia, ib) else { return a.map { .del($0) } + b.map { .add($0) } }
        var ops: [Op] = []
        ops.reserveCapacity(script.count)
        for step in script {
            switch step {
            case .same(let i): ops.append(.same(a[i]))
            case .del(let i): ops.append(.del(a[i]))
            case .add(let j): ops.append(.add(b[j]))
            }
        }
        return ops
    }

    private enum Step { case same(Int), del(Int), add(Int) }

    private static func myers(_ a: [Int], _ b: [Int]) -> [Step]? {
        let n = a.count, m = b.count
        let limit = min(n + m, maxEdits)
        let off = limit + 1
        var v = [Int](repeating: 0, count: 2 * off + 2)
        var trace: [[Int]] = []
        var found = false
        search: for d in 0...limit {
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) { x = v[off + k + 1] } else { x = v[off + k - 1] + 1 }
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n, y >= m { found = true; break search }
                k += 2
            }
        }
        guard found else { return nil }
        var steps: [Step] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let vv = trace[d]
            let k = x - y
            let prevK = (k == -d || (k != d && vv[off + k - 1] < vv[off + k + 1])) ? k + 1 : k - 1
            let prevX = vv[off + prevK], prevY = prevX - prevK
            while x > prevX, y > prevY { steps.append(.same(x - 1)); x -= 1; y -= 1 }
            if d > 0 {
                if x == prevX { steps.append(.add(y - 1)) } else { steps.append(.del(x - 1)) }
                x = prevX; y = prevY
            }
        }
        return steps.reversed()
    }

    /// Deja los cambios con `context` lineas alrededor; los tramos largos sin cambios pasan a una sola linea de salto.
    static func compact(_ ops: [Op], context: Int) -> [ChangeLine] {
        var keep = [Bool](repeating: false, count: ops.count)
        for (i, op) in ops.enumerated() {
            if case .same = op { continue }
            for j in max(0, i - context)...min(ops.count - 1, i + context) { keep[j] = true }
        }
        var out: [ChangeLine] = []
        var skipped = 0, skipStart = 0
        func flush() {
            // un salto de una sola linea ocupa lo mismo que la linea: se ensena la linea
            if skipped == 1, case .same(let s) = ops[skipStart] { out.append(ChangeLine(.context, s)) }
            else if skipped > 0 { out.append(ChangeLine(.gap, count: skipped)) }
            skipped = 0
        }
        for (i, op) in ops.enumerated() {
            if !keep[i] { if skipped == 0 { skipStart = i }; skipped += 1; continue }
            flush()
            switch op {
            case .same(let s): out.append(ChangeLine(.context, s))
            case .add(let s): out.append(ChangeLine(.added, s))
            case .del(let s): out.append(ChangeLine(.removed, s))
            }
        }
        // un tramo final sin cambios no aporta nada: solo se muestra si hay algo antes que lo explique
        if skipped > 0, !out.isEmpty { flush() }
        return out
    }
}
