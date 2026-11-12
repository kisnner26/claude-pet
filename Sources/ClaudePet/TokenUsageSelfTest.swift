import Foundation

/// `ClaudePet --selftest-usage`: el parser de `usage`, la tasa de cache y el recuento sin duplicados.
enum TokenUsageSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func row(_ s: String) -> [String: Any] { SessionJSONLines.object(Data(s.utf8)) ?? [:] }

        let r = TokenUsageParser.parse(row(#"{"cwd":"/Users/x/mi-app","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":200,"cache_read_input_tokens":790,"output_tokens":55}}}"#))
        check("lee los cuatro contadores", r?.usage == TokenUsage(input: 10, cacheRead: 790, cacheCreate: 200, output: 55, messages: 1))
        check("solo guarda el ultimo componente de la carpeta", r?.cwdName == "mi-app")
        check("el id viaja para no duplicar", r?.id == "m1")
        check("sin usage no hay fila", TokenUsageParser.parse(row(#"{"message":{"content":"hola"}}"#)) == nil)
        check("usage vacio no cuenta", TokenUsageParser.parse(row(#"{"message":{"usage":{"input_tokens":0,"output_tokens":0}}}"#)) == nil)
        check("campos que faltan valen 0", TokenUsageParser.parse(row(#"{"message":{"usage":{"output_tokens":7}}}"#))?.usage.total == 7)
        check("negativos o texto se ignoran", TokenUsageParser.parse(row(#"{"message":{"usage":{"input_tokens":-5,"output_tokens":"x","cache_read_input_tokens":3}}}"#))?.usage == TokenUsage(input: 0, cacheRead: 3, cacheCreate: 0, output: 0, messages: 1))

        let u = TokenUsage(input: 10, cacheRead: 790, cacheCreate: 200, output: 55)
        check("tasa de cache = leida / entrada total", u.cacheHitPercent == 79 && u.promptTotal == 1000)
        check("sin entrada no hay tasa", TokenUsage(output: 4).cacheHitRate == nil)
        check("todo de cache es 100 %", TokenUsage(cacheRead: 50).cacheHitPercent == 100)
        check("nada de cache es 0 %", TokenUsage(input: 50).cacheHitPercent == 0)

        var acc = TokenUsageParser.Accumulator()
        for s in [#"{"message":{"id":"a","usage":{"input_tokens":1,"cache_read_input_tokens":100,"output_tokens":5}}}"#,
                  #"{"message":{"id":"a","usage":{"input_tokens":1,"cache_read_input_tokens":100,"output_tokens":40}}}"#,
                  #"{"message":{"id":"b","usage":{"input_tokens":2,"cache_creation_input_tokens":300,"output_tokens":10}}}"#,
                  #"{"message":{"usage":{"input_tokens":4,"output_tokens":1}}}"#] {
            if let p = TokenUsageParser.parse(row(s)) { acc.add(p) }
        }
        let sum = acc.usage
        check("un mensaje repartido en varias lineas se cuenta una vez, con la salida final", sum.input == 7 && sum.cacheRead == 100 && sum.cacheCreate == 300 && sum.output == 51 && sum.messages == 3)

        failures += ledger()

        print(failures == 0 ? "USO OK" : "USO \(failures) FALLOS")
        return failures == 0
    }

    /// Transcripts sinteticos en una carpeta temporal: dos proyectos, una sesion que crece, una linea a medio escribir y un archivo enorme.
    private static func ledger() -> Int {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        func line(_ id: String, _ cwd: String, input: Int, read: Int, create: Int, out: Int, secret: String = "texto privado") -> String {
            #"{"type":"assistant","cwd":"\#(cwd)","message":{"id":"\#(id)","content":[{"type":"text","text":"\#(secret)"}],"usage":{"input_tokens":\#(input),"cache_read_input_tokens":\#(read),"cache_creation_input_tokens":\#(create),"output_tokens":\#(out)}}}"# + "\n"
        }
        let a = root.appendingPathComponent("-Users-x-alfa"), b = root.appendingPathComponent("-Users-x-beta")
        try? fm.createDirectory(at: a, withIntermediateDirectories: true); try? fm.createDirectory(at: b, withIntermediateDirectories: true)
        let fa = a.appendingPathComponent("aaaaaaaa-1111.jsonl"), fb = b.appendingPathComponent("bbbbbbbb-2222.jsonl"), fc = b.appendingPathComponent("cccccccc-3333.jsonl")
        try? (line("m1", "/Users/x/alfa", input: 5, read: 900, create: 100, out: 20) + line("m1", "/Users/x/alfa", input: 5, read: 900, create: 100, out: 20)
              + "esto no es json\n" + #"{"type":"user","message":{"content":"hola"}}"# + "\n").write(to: fa, atomically: true, encoding: .utf8)
        try? line("n1", "/Users/x/beta", input: 50, read: 0, create: 450, out: 10).write(to: fb, atomically: true, encoding: .utf8)
        try? line("p1", "/Users/x/beta", input: 1, read: 99, create: 0, out: 5).write(to: fc, atomically: true, encoding: .utf8)

        let ledger = TokenLedger(root: root, limits: .init(maxFiles: 10, maxAge: 86_400, maxBytesPerFile: 1 << 20, chunk: 1 << 16))
        func snapshot() -> TokenSnapshot {
            let sem = DispatchSemaphore(value: 0); var result = TokenSnapshot()
            Task { result = await ledger.refresh(); sem.signal() }
            sem.wait(); return result
        }
        var snap = snapshot()
        check("tres sesiones, dos proyectos", snap.sessions.count == 3 && snap.projects.count == 2)
        let alfa = snap.sessions.first { $0.id == "aaaaaaaa" }
        check("el mensaje repetido cuenta una vez", alfa?.usage == TokenUsage(input: 5, cacheRead: 900, cacheCreate: 100, output: 20, messages: 1))
        check("la tasa de cache de la sesion es 90 %", alfa?.usage.cacheHitPercent == 90)
        check("el proyecto sale del ultimo componente de la carpeta", alfa?.project == "alfa")
        let beta = snap.projects.first { $0.name == "beta" }
        check("el proyecto suma sus sesiones", beta?.sessions == 2 && beta?.usage.total == 50 + 450 + 10 + 1 + 99 + 5)
        check("total global", snap.total.total == 1025 + 510 + 105)
        check("proyectos ordenados por gasto", snap.projects.first?.name == "alfa")

        // incremental: se anade una linea completa y otra a medio escribir
        if let h = try? FileHandle(forWritingTo: fa) {
            h.seekToEndOfFile()
            h.write(Data(line("m2", "/Users/x/alfa", input: 1, read: 0, create: 0, out: 9).utf8))
            h.write(Data(#"{"message":{"id":"m3","usage":{"input_tokens":1000"#.utf8))
            try? h.close()
        }
        snap = snapshot()
        check("lectura incremental suma solo lo nuevo", snap.sessions.first { $0.id == "aaaaaaaa" }?.usage.total == 1025 + 10)
        if let h = try? FileHandle(forWritingTo: fa) {
            h.seekToEndOfFile(); h.write(Data((#","output_tokens":1}}}"# + "\n").utf8)); try? h.close()
        }
        snap = snapshot()
        check("la linea a medio escribir se cuenta cuando se completa", snap.sessions.first { $0.id == "aaaaaaaa" }?.usage.total == 1025 + 10 + 1001)

        // archivo enorme: se lee solo el final y se marca como parcial
        let big = a.appendingPathComponent("dddddddd-4444.jsonl")
        var text = ""
        for i in 0..<400 { text += line("big\(i)", "/Users/x/alfa", input: 1, read: 0, create: 0, out: 1, secret: String(repeating: "x", count: 4000)) }
        try? text.write(to: big, atomically: true, encoding: .utf8)
        let small = TokenLedger(root: root, limits: .init(maxFiles: 10, maxAge: 86_400, maxBytesPerFile: 200_000, chunk: 50_000))
        let sem = DispatchSemaphore(value: 0); var bigSnap = TokenSnapshot()
        Task { bigSnap = await small.refresh(); sem.signal() }; sem.wait()
        let bigSession = bigSnap.sessions.first { $0.id == "dddddddd" }
        check("el tope de tamano marca la sesion como parcial y lee menos de todo", bigSession?.partial == true && (bigSession?.usage.messages ?? 0) > 0 && (bigSession?.usage.messages ?? 999) < 400)

        // un archivo viejo queda fuera
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 86_400)], ofItemAtPath: fc.path)
        let recent = TokenLedger(root: root, limits: .init(maxFiles: 10, maxAge: 86_400, maxBytesPerFile: 1 << 20, chunk: 1 << 16))
        Task { bigSnap = await recent.refresh(); sem.signal() }; sem.wait()
        check("los transcripts antiguos no se leen", !bigSnap.sessions.contains { $0.id == "cccccccc" })

        // nada de contenido en el resultado
        let dump = String(describing: snap)
        check("el resultado no contiene texto de los mensajes", !dump.contains("privado"))
        check("la carpeta completa solo se guarda como dato en memoria para auditar", snap.projects.first { $0.name == "alfa" }?.workspace == "/Users/x/alfa")
        check("las sesiones traen la fecha de inicio del transcript", snap.sessions.allSatisfy { $0.started != nil })
        return failures
    }
}
