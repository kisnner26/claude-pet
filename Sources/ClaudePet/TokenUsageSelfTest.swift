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

        print(failures == 0 ? "USO OK" : "USO \(failures) FALLOS")
        return failures == 0
    }
}
