import Foundation

/// Filtro de salida de terminal: `comando 2>&1 | ClaudePet --squeeze`.
/// Quita colores y barras de progreso, junta lineas repetidas («×34»), recorta trazas largas y resume las pruebas que pasan,
/// pero conserva siempre errores, fallos y resumenes. Determinista y sin red; trabaja sobre bytes para ser rapido.
/// No intercepta nada: Claude Code no deja que un hook cambie la salida de sus herramientas, asi que lo aplica el usuario o un alias.
enum OutputSqueezer {
    struct Result {
        let output: [UInt8]
        let tokensBefore: Int
        let tokensAfter: Int
        let linesIn: Int
        let linesOut: Int
        var savedPercent: Int { tokensBefore > 0 ? Int((Double(tokensBefore - tokensAfter) / Double(tokensBefore) * 100).rounded()) : 0 }
        var footer: String { "[squeeze] ~\(tokensBefore) tokens -> ~\(tokensAfter) tokens (\(savedPercent >= 0 ? "-" : "+")\(abs(savedPercent))%), \(linesIn) -> \(linesOut) líneas" }
    }

    enum Kind: UInt8 { case blank, important, summary, normal, testPass, buildStep, progress, trace }

    static let traceKeep = (head: 2, tail: 3)
    static let traceThreshold = 8
    static let maxLine = 600
    static let maxImportantLine = 4_000

    // palabras que marcan una linea que NUNCA se pierde (en minusculas)
    private static let importantNeedles: [[UInt8]] = [
        "error", "fail", "fatal", "panic", "exception", "traceback", "assert", "segfault", "segmentation", "abort", "denied", "crash", "killed",
        "not found", "cannot ", "can't ", "could not", "couldn't", "unable to", "undefined", "unresolved", "timed out", "timeout", "warning",
        "✗", "✘", "❌", "npm err", "err!", "refused", "invalid", "missing", "no such file", "uncaught", "unhandled", "deprecated", "overflow", "leak"
    ].map { Array($0.utf8) }

    private static let summaryNeedles: [[UInt8]] = [
        "passed", "tests:", "test suites:", "test files", "test result", "** ", "build complete", "build succeeded", "executed ", "added ",
        "up to date", "finished", "summary", "total:", "coverage", "tests  ", "duration", "ran "
    ].map { Array($0.utf8) }

    private static let buildStepPrefixes: [[UInt8]] = [
        "compiling ", "building ", "linking ", "compileswift", "swiftcompile", "ld ", "copyswiftlibs", "processinfoplistfile", "fetching ", "downloading ",
        "downloaded ", "resolving ", "updating ", "cloning ", "[", "write ", "creategroup", "swiftdriver", "swiftemitmodule", "mergeswiftmodule",
        "copy ", "touch ", "codesign ", "gensym", "createbuilddirectory", "registerexecutionpolicyexception", "processproductpackaging", "cpresource", "ditto"
    ].map { Array($0.utf8) }

    // MARK: API

    @_optimize(speed) static func squeeze(_ input: [UInt8]) -> Result {
        let before = tokens(input)
        var buf: [UInt8] = []
        buf.reserveCapacity(input.count)
        var starts: [Int] = [], ends: [Int] = [], overwritten: [Bool] = []
        clean(input, into: &buf, starts: &starts, ends: &ends, overwritten: &overwritten)
        let n = starts.count

        var lower = buf
        lower.withUnsafeMutableBufferPointer { p in
            for i in 0..<p.count { let b = p[i]; if b >= 65 && b <= 90 { p[i] = b + 32 } }
        }

        var kinds = [Kind](repeating: .normal, count: n)
        var important = [Bool](repeating: false, count: n)
        var summary = [Bool](repeating: false, count: n)
        lower.withUnsafeBufferPointer { low in
            if let base = low.baseAddress {
                mark(base, low.count, importantNeedles, starts: starts, ends: ends, into: &important)
                mark(base, low.count, summaryNeedles, starts: starts, ends: ends, into: &summary)
            }
        }
        buf.withUnsafeBufferPointer { raw in
            lower.withUnsafeBufferPointer { low in
                var prevTrace = false
                for i in 0..<n {
                    let kind = classify(raw.baseAddress!, low.baseAddress!, starts[i], ends[i], overwritten: overwritten[i], previousWasTrace: prevTrace,
                                        isImportant: important[i], isSummary: summary[i])
                    kinds[i] = kind
                    prevTrace = kind == .trace
                }
            }
        }

        var out: [UInt8] = []
        out.reserveCapacity(buf.count / 2)
        var linesOut = 0
        var lastBlank = true
        func emit(_ bytes: UnsafeBufferPointer<UInt8>, suffix: String? = nil) {
            out.append(contentsOf: bytes)
            if let suffix { out.append(contentsOf: Array(suffix.utf8)) }
            out.append(10); linesOut += 1; lastBlank = false
        }
        func emit(text: String) { out.append(contentsOf: Array(text.utf8)); out.append(10); linesOut += 1; lastBlank = false }

        buf.withUnsafeBufferPointer { raw in
            let base = raw.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!
            func slice(_ i: Int, important: Bool) -> UnsafeBufferPointer<UInt8> {
                let limit = important ? maxImportantLine : maxLine
                return UnsafeBufferPointer(start: base + starts[i], count: min(ends[i] - starts[i], limit))
            }
            func line(_ i: Int, suffix: String? = nil) {
                let k = kinds[i]
                let full = ends[i] - starts[i]
                let s = slice(i, important: k == .important || k == .summary)
                if s.count < full { emit(s, suffix: " […+\(full - s.count) bytes]" + (suffix ?? "")) } else { emit(s, suffix: suffix) }
            }
            var i = 0
            while i < n {
                switch kinds[i] {
                case .blank:
                    if !lastBlank { out.append(10); linesOut += 1; lastBlank = true }
                    i += 1
                case .progress:
                    i += 1
                case .testPass, .buildStep:
                    let kind = kinds[i]
                    var j = i
                    while j < n, kinds[j] == kind { j += 1 }
                    let count = j - i
                    if kind == .testPass {
                        if count < 3 { for k in i..<j { line(k) } } else { emit(text: "… \(count) líneas de pruebas correctas omitidas") }
                    } else {
                        if count < 4 { for k in i..<j { line(k) } } else { line(i); emit(text: "… \(count - 2) líneas de pasos de compilación o descarga omitidas"); line(j - 1) }
                    }
                    i = j
                case .trace:
                    var j = i
                    while j < n, kinds[j] == .trace { j += 1 }
                    let count = j - i
                    if count <= traceThreshold { for k in i..<j { line(k) } }
                    else {
                        for k in i..<(i + traceKeep.head) { line(k) }
                        emit(text: "    … \(count - traceKeep.head - traceKeep.tail) líneas de traza omitidas")
                        for k in (j - traceKeep.tail)..<j { line(k) }
                    }
                    i = j
                case .important, .summary, .normal:
                    let kind = kinds[i]
                    var j = i + 1
                    while j < n, kinds[j] == kind, same(base, starts[i], ends[i], starts[j], ends[j], digitsEqual: kind == .normal) { j += 1 }
                    line(i, suffix: j - i > 1 ? " ×\(j - i)" : nil)
                    i = j
                }
            }
        }
        // sin linea en blanco final
        while out.count >= 2, out[out.count - 1] == 10, out[out.count - 2] == 10 { out.removeLast(); linesOut -= 1 }
        return Result(output: out, tokensBefore: before, tokensAfter: tokens(out), linesIn: n, linesOut: linesOut)
    }

    // MARK: limpieza

    /// Quita secuencias ANSI y controles. Un retorno de carro suelto cuenta como fin de linea sobrescrita (barras de progreso).
    @_optimize(speed) private static func clean(_ input: [UInt8], into buf: inout [UInt8], starts: inout [Int], ends: inout [Int], overwritten: inout [Bool]) {
        var lineStart = 0
        func finish(_ over: Bool) {
            var end = buf.count
            while end > lineStart, buf[end - 1] == 32 || buf[end - 1] == 9 { end -= 1 }
            buf.removeSubrange(end..<buf.count)
            starts.append(lineStart); ends.append(end); overwritten.append(over)
            buf.append(10)          // separador: una palabra clave nunca cruza de una linea a otra
            lineStart = buf.count
        }
        let count = input.count
        var i = 0
        while i < count {
            let b = input[i]
            switch b {
            case 0x1B:
                if i + 1 < count {
                    let next = input[i + 1]
                    if next == 0x5B {          // CSI: hasta un byte final 0x40-0x7E
                        i += 2
                        while i < count, !(input[i] >= 0x40 && input[i] <= 0x7E) { i += 1 }
                        i += 1
                    } else if next == 0x5D {   // OSC: hasta BEL o ESC \
                        i += 2
                        while i < count, input[i] != 7, !(input[i] == 0x1B && i + 1 < count && input[i + 1] == 0x5C) { i += 1 }
                        i += (i < count && input[i] == 0x1B) ? 2 : 1
                    } else if next == 0x28 || next == 0x29 { i += 3 }
                    else { i += 2 }
                } else { i += 1 }
            case 0x0A:
                finish(false); i += 1
            case 0x0D:
                if i + 1 < count, input[i + 1] == 0x0A { i += 1 }        // \r\n
                else { if buf.count > lineStart { finish(true) }; i += 1 }
            case 0x09:
                buf.append(0x20); buf.append(0x20); i += 1
            case 0..<0x20, 0x7F:
                i += 1
            default:
                buf.append(b); i += 1
            }
        }
        if buf.count > lineStart { finish(false) }
    }

    // MARK: clasificacion

    @_optimize(speed) private static func classify(_ raw: UnsafePointer<UInt8>, _ low: UnsafePointer<UInt8>, _ s: Int, _ e: Int, overwritten: Bool, previousWasTrace: Bool, isImportant: Bool, isSummary: Bool) -> Kind {
        if e == s { return .blank }
        let len = e - s
        let l = low + s
        if isImportant { return .important }        // un error nunca se descarta, ni aunque la linea se sobrescriba
        if overwritten { return .progress }

        let first = raw[s]
        // barras de progreso y spinners
        if first == 0xE2, len >= 3, raw[s + 1] >= 0xA0, raw[s + 1] <= 0xA3 { return .progress }             // braille
        var percent = false
        for k in 1..<max(1, len) where raw[s + k] == 0x25 && raw[s + k - 1] >= 48 && raw[s + k - 1] <= 57 { percent = true; break }
        if percent {
            let bar = containsRaw(raw + s, len, [0xE2, 0x96]) || containsLiteral(l, len, "====") || containsLiteral(l, len, "####") || containsLiteral(l, len, "[#") || containsLiteral(l, len, "-->") || containsLiteral(l, len, "..." )
            if bar || containsLiteral(l, len, "/s") || containsLiteral(l, len, "eta") || containsLiteral(l, len, "kb") || containsLiteral(l, len, "mb") { return .progress }
        }

        // pruebas que pasan
        if startsWith(l, len, "test case '") || startsWith(l, len, "test suite '") && !containsLiteral(l, len, "'all tests'") && !containsLiteral(l, len, "selected tests") { return .testPass }
        if first == 0xE2, len >= 4, raw[s + 1] == 0x9C, raw[s + 2] == 0x93 || raw[s + 2] == 0x94 { return .testPass }         // ✓ ✔
        let trimmed = skipSpaces(l, len)
        if trimmed.len >= 3, (trimmed.ptr[0] == 0xE2 && trimmed.ptr[1] == 0x9C && (trimmed.ptr[2] == 0x93 || trimmed.ptr[2] == 0x94)) { return .testPass }
        if startsWith(l, len, "test "), endsWith(l, len, "... ok") { return .testPass }
        if containsLiteral(l, len, "::"), endsWith(l, len, " passed") || containsLiteral(l, len, " passed [") { return .testPass }
        if startsWith(l, len, "pass ") || startsWith(l, len, "ok ") && containsLiteral(l, len, "ms") { return .testPass }

        // resumenes
        if isSummary { return .summary }

        // trazas: marcos de pila
        if isTraceFrame(raw + s, low + s, len) || (previousWasTrace && leadingSpaces(raw + s, len) >= 4) { return .trace }

        // pasos de compilacion o descarga
        for p in buildStepPrefixes where p[0] == l[0] && startsWith(l, len, p) {
            if p.first == 0x5B {                    // "[12/40]" y no cualquier corchete
                if len > 3, low[s + 1] >= 48 && low[s + 1] <= 57 { return .buildStep } else { break }
            }
            return .buildStep
        }
        let t = skipSpaces(l, len)
        if t.len > 9, t.ptr != l, matchesAny(t.ptr, t.len, indentedStepPrefixes) { return .buildStep }
        return .normal
    }

    private static func isTraceFrame(_ p: UnsafePointer<UInt8>, _ low: UnsafePointer<UInt8>, _ len: Int) -> Bool {
        let indent = leadingSpaces(p, len)
        if p[0] == 0x23, len > 2, p[1] >= 48 && p[1] <= 57 { return true }      // "#12 0x..." (gdb, lldb)
        if indent == 0 {
            // marcos de swift/objc sin sangria: "0   libswiftCore.dylib   0x000..."
            if p[0] >= 48 && p[0] <= 57 { return containsLiteral(low, len, " 0x") && len > 20 }
            return false
        }
        let t = p + indent, tl = len - indent
        let lt = low + indent
        return startsWith(lt, tl, "at ") || startsWith(t, tl, "File \"") || startsWith(lt, tl, "from ") || (t[0] >= 48 && t[0] <= 57 && containsLiteral(lt, tl, " 0x"))
    }

    // MARK: utilidades de bytes

    @_optimize(speed) private static func tokens(_ bytes: [UInt8]) -> Int {
        var chars = 0
        bytes.withUnsafeBufferPointer { p in for i in 0..<p.count where p[i] & 0xC0 != 0x80 { chars += 1 } }
        return TokenEstimate.tokens(characters: chars)
    }

    private static func contains(_ p: UnsafePointer<UInt8>, _ len: Int, _ needles: [[UInt8]]) -> Bool {
        for n in needles where n.count <= len {
            if n.withUnsafeBufferPointer({ memmem(p, len, $0.baseAddress!, n.count) }) != nil { return true }
        }
        return false
    }
    private static func containsRaw(_ p: UnsafePointer<UInt8>, _ len: Int, _ needle: [UInt8]) -> Bool {
        needle.count <= len && needle.withUnsafeBufferPointer { memmem(p, len, $0.baseAddress!, needle.count) } != nil
    }
    private static func containsLiteral(_ p: UnsafePointer<UInt8>, _ len: Int, _ s: StaticString) -> Bool {
        Int(s.utf8CodeUnitCount) <= len && memmem(p, len, s.utf8Start, s.utf8CodeUnitCount) != nil
    }
    private static func startsWith(_ p: UnsafePointer<UInt8>, _ len: Int, _ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        return n <= len && memcmp(p, s.utf8Start, n) == 0
    }
    private static func startsWith(_ p: UnsafePointer<UInt8>, _ len: Int, _ s: [UInt8]) -> Bool {
        s.count <= len && s.withUnsafeBufferPointer { memcmp(p, $0.baseAddress!, s.count) == 0 }
    }
    private static func endsWith(_ p: UnsafePointer<UInt8>, _ len: Int, _ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        return n <= len && memcmp(p + len - n, s.utf8Start, n) == 0
    }
    private static let indentedStepPrefixes: [[UInt8]] = ["compiling ", "downloaded ", "downloading ", "fetching ", "resolving "].map { Array($0.utf8) }
    private static func matchesAny(_ p: UnsafePointer<UInt8>, _ len: Int, _ prefixes: [[UInt8]]) -> Bool {
        prefixes.contains { $0[0] == p[0] && startsWith(p, len, $0) }
    }

    /// Marca las lineas que contienen alguna palabra: una pasada por palabra sobre todo el texto, no una por linea.
    @_optimize(speed) private static func mark(_ base: UnsafePointer<UInt8>, _ total: Int, _ needles: [[UInt8]], starts: [Int], ends: [Int], into flags: inout [Bool]) {
        for needle in needles {
            needle.withUnsafeBufferPointer { nb in
                var offset = 0, line = 0
                while offset < total, let hit = memmem(base + offset, total - offset, nb.baseAddress!, nb.count) {
                    let at = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                    while line < starts.count - 1, starts[line + 1] <= at { line += 1 }
                    if at < ends[line] { flags[line] = true }
                    offset = line + 1 < starts.count ? starts[line + 1] : total       // el resto de esa linea ya no importa
                    if offset <= at { offset = at + 1 }
                }
            }
        }
    }
    private static func leadingSpaces(_ p: UnsafePointer<UInt8>, _ len: Int) -> Int {
        var k = 0
        while k < len, p[k] == 32 { k += 1 }
        return k
    }
    private static func skipSpaces(_ p: UnsafePointer<UInt8>, _ len: Int) -> (ptr: UnsafePointer<UInt8>, len: Int) {
        let k = leadingSpaces(p, len)
        return (p + k, len - k)
    }

    /// Dos lineas iguales; con `digitsEqual`, las cifras de una y otra cuentan como lo mismo («descargando 12» = «descargando 13»).
    private static func same(_ base: UnsafePointer<UInt8>, _ s1: Int, _ e1: Int, _ s2: Int, _ e2: Int, digitsEqual: Bool) -> Bool {
        if !digitsEqual { return e1 - s1 == e2 - s2 && memcmp(base + s1, base + s2, e1 - s1) == 0 }
        var a = s1, b = s2
        while a < e1, b < e2 {
            let x = base[a], y = base[b]
            if x >= 48 && x <= 57 && y >= 48 && y <= 57 {
                while a < e1, base[a] >= 48 && base[a] <= 57 { a += 1 }
                while b < e2, base[b] >= 48 && base[b] <= 57 { b += 1 }
            } else if x == y { a += 1; b += 1 } else { return false }
        }
        return a == e1 && b == e2
    }

    // MARK: linea de comandos

    /// `comando 2>&1 | ClaudePet --squeeze`: lee stdin entero, escribe la version comprimida y una linea final con tokens estimados.
    static func cli() -> Int32 {
        var data = [UInt8]()
        let h = FileHandle.standardInput
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { data.append(contentsOf: chunk) }
        let r = squeeze(data)
        var out = r.output
        out.append(contentsOf: Array((r.footer + "\n").utf8))
        FileHandle.standardOutput.write(Data(out))
        return 0
    }
}
