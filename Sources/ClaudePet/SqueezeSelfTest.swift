import Foundation

/// `ClaudePet --selftest-squeeze`: el filtro de salida con logs sinteticos. Lo importante es lo que NO se puede perder.
enum SqueezeSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        func squeeze(_ s: String) -> (text: String, result: OutputSqueezer.Result) {
            let r = OutputSqueezer.squeeze(Array(s.utf8))
            return (String(decoding: r.output, as: UTF8.self), r)
        }
        let esc = "\u{1B}"

        // colores
        var r = squeeze("\(esc)[31;1merror: algo se rompio\(esc)[0m\n\(esc)[32mok\(esc)[0m\n\(esc)]0;titulo\u{07}hola\n")
        check("quita colores y secuencias de titulo", !r.text.contains(esc) && r.text.contains("error: algo se rompio") && r.text.contains("hola"))

        // barras de progreso
        var log = ""
        for p in stride(from: 0, through: 100, by: 5) { log += "Downloading [\(String(repeating: "=", count: p / 5))>\(String(repeating: " ", count: 20 - p / 5))] \(p)% 1.2MB/s\r" }
        log += "Downloading done\nerror: checksum mismatch at 45%\n"
        r = squeeze(log)
        check("las barras de progreso desaparecen", !r.text.contains("1.2MB/s") && r.text.contains("Downloading done"))
        check("pero un error con porcentaje se conserva", r.text.contains("error: checksum mismatch at 45%"))
        r = squeeze("██████████░░░░░░ 62% 3.1 MB/s eta 4s\n⠋ cargando\nlisto\n")
        check("barras de bloques y spinners fuera", !r.text.contains("62%") && !r.text.contains("cargando") && r.text.contains("listo"))

        // repetidas
        r = squeeze(String(repeating: "waiting for server...\n", count: 34) + "connected\n")
        check("lineas repetidas se juntan con ×N", r.text.contains("waiting for server... ×34") && r.text.components(separatedBy: "waiting for server").count == 2)
        r = squeeze((1...20).map { "retry \($0) of 20 failed: connection refused\n" }.joined())
        check("errores que solo difieren en la cifra NO se pierden", (1...20).allSatisfy { r.text.contains("retry \($0) of 20 failed") })
        r = squeeze((1...20).map { "fetching chunk \($0)\n" }.joined())
        check("lineas normales que solo cambian la cifra se juntan", r.text.contains("×20") || r.result.linesOut <= 3)
        r = squeeze("a\n\n\n\n\nb\n")
        check("lineas en blanco consecutivas se reducen a una", r.text == "a\n\nb\n")

        // trazas
        var trace = "Error: no se pudo conectar\n"
        for i in 1...40 { trace += "    at Object.frame\(i) (/app/src/mod\(i).js:\(i):5)\n" }
        trace += "Caused by: ECONNRESET\nsiguiente linea\n"
        r = squeeze(trace)
        check("la traza larga conserva cabecera y causa", r.text.contains("Error: no se pudo conectar") && r.text.contains("Caused by: ECONNRESET") && r.text.contains("siguiente linea"))
        check("y las ultimas lineas, con aviso de lo omitido", r.text.contains("frame40") && r.text.contains("frame39") && r.text.contains("frame38") && r.text.contains("líneas de traza omitidas") && !r.text.contains("frame20"))
        check("una traza corta se deja entera", squeeze("boom\n    at a (x.js:1:1)\n    at b (x.js:2:2)\nfin\n").text.contains("at b"))
        var py = "Traceback (most recent call last):\n"
        for i in 1...15 { py += "  File \"/app/m\(i).py\", line \(i), in f\(i)\n    call_\(i)()\n" }
        py += "ValueError: valor invalido\n"
        r = squeeze(py)
        check("traceback de python: cabecera y causa se quedan", r.text.contains("Traceback (most recent call last):") && r.text.contains("ValueError: valor invalido") && r.text.contains("omitidas"))

        // swift test / xcodebuild
        var swiftTest = "Test Suite 'All tests' started at 2027-01-15 10:00:00.000\n"
        for i in 1...300 { swiftTest += "Test Case '-[AppTests.ModelTests test\(i)]' started.\nTest Case '-[AppTests.ModelTests test\(i)]' passed (0.001 seconds).\n" }
        swiftTest += "Test Case '-[AppTests.ModelTests testRotura]' started.\n/app/Tests/ModelTests.swift:42: error: -[AppTests.ModelTests testRotura] : XCTAssertEqual failed: (\"1\") is not equal to (\"2\")\nTest Case '-[AppTests.ModelTests testRotura]' failed (0.002 seconds).\n"
        swiftTest += "Executed 301 tests, with 1 failure (0 unexpected) in 0.5 (0.6) seconds\n** TEST FAILED **\n"
        r = squeeze(swiftTest)
        check("swift test: el fallo y su causa se conservan", r.text.contains("XCTAssertEqual failed") && r.text.contains("testRotura]' failed"))
        check("swift test: el resumen se conserva", r.text.contains("Executed 301 tests, with 1 failure") && r.text.contains("** TEST FAILED **"))
        check("swift test: los 300 aprobados se resumen", r.text.contains("líneas de pruebas correctas omitidas") && r.result.linesOut < 20)

        // otros ejecutores: ninguna de estas lineas puede desaparecer
        let mustSurvive = [
            "FAILED tests/test_api.py::test_login - AssertionError: assert 401 == 200",
            "E   AssertionError: assert 401 == 200",
            "=========== 1 failed, 12 passed in 0.84s ===========",
            "Test Suites: 1 failed, 3 passed, 4 total",
            "Tests:       2 failed, 18 passed, 20 total",
            " FAIL  src/app.test.ts > suma > falla",
            " Test Files  1 failed | 2 passed (3)",
            "error[E0308]: mismatched types",
            "test result: FAILED. 5 passed; 1 failed; 0 ignored",
            "thread 'main' panicked at src/main.rs:10:5",
            "npm ERR! code ELIFECYCLE",
            "npm ERR! Test failed.  See above for more details.",
            "** BUILD FAILED **",
            "The following build commands failed:",
            "/Users/x/App/Model.swift:12:5: error: cannot find 'foo' in scope",
            "ld: symbol(s) not found for architecture arm64",
            "Segmentation fault: 11",
            "fatal: not a git repository",
            "Uncaught TypeError: x is not a function",
            "warning: unused variable 'y'",
            "BUILD SUCCEEDED",
        ]
        for line in mustSurvive {
            var noisy = (1...30).map { "Compiling Modulo\($0) archivo\($0).swift\n" }.joined()
            noisy += "\(esc)[1m\(line)\(esc)[0m\n"
            noisy += (1...30).map { "Test Case '-[T t\($0)]' passed (0.001 seconds).\n" }.joined()
            let out = squeeze(noisy).text
            check("sobrevive: \(line)", out.contains(line))
        }

        // propiedad: en un log aleatorio y determinista, toda linea con error aparece en la salida
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        func noisyLog(_ lines: Int) -> (String, [String]) {
            var text = "", errors: [String] = []
            for i in 0..<lines {
                switch rnd(9) {
                case 0: let e = "error: fallo numero \(i) en modulo\(rnd(50))"; errors.append(e); text += e + "\n"
                case 1: text += "Compiling Mod\(rnd(500)) f\(i).swift\n"
                case 2: text += "Test Case '-[S t\(i)]' passed (0.001 seconds).\n"
                case 3: text += "    at frame\(i) (/x/y.js:\(i):1)\n"
                case 4: text += "\(esc)[33mwarn \(rnd(3))\(esc)[0m\n"
                case 5: text += "\n"
                case 6: text += "progress \(rnd(100))% [=====>   ] 1.0MB/s\r"
                case 7: let e = "FAILED case_\(i) - AssertionError"; errors.append(e); text += e + "\n"
                default: text += "linea normal \(rnd(1000)) del programa\n"
                }
            }
            return (text, errors)
        }
        func lineSet(_ text: String) -> Set<String> { Set(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)) }
        let (random, errors) = noisyLog(20_000)
        let rr = squeeze(random)
        let randomLines = lineSet(rr.text)
        check("log aleatorio: ninguna linea de error se pierde (\(errors.count))", errors.allSatisfy { randomLines.contains($0) })
        check("log aleatorio: se comprime de verdad", rr.result.tokensAfter < rr.result.tokensBefore)

        // determinismo
        check("misma entrada, misma salida", squeeze(random).text == rr.text)

        // 50 000 lineas en menos de un segundo
        let (big, bigErrors) = noisyLog(50_000)
        // tiempo de CPU del proceso, no de pared: una maquina cargada no debe hacer fallar la prueba (esta es la compilacion de depuracion, la mas lenta)
        let started = clock()
        let big1 = squeeze(big)
        let ms = Int(Double(clock() - started) / Double(CLOCKS_PER_SEC) * 1000)
        print("50000 lineas: \(ms) ms de CPU, ~\(big1.result.tokensBefore) -> ~\(big1.result.tokensAfter) tokens (datos sinteticos)")
        check("50 000 lineas en menos de un segundo (\(ms) ms)", ms < 1_000)
        let bigLines = lineSet(big1.text)
        check("50 000 lineas: ningun error perdido (\(bigErrors.count))", bigErrors.allSatisfy { bigLines.contains($0) })

        // entrada rara
        check("vacio", squeeze("").text.isEmpty)
        check("sin salto final", squeeze("solo una linea").text == "solo una linea\n")
        check("bytes no utf8 no rompen", OutputSqueezer.squeeze([0xFF, 0xFE, 10, 0x65, 0x72, 0x72, 0x6F, 0x72, 10]).linesOut == 2)
        let longLine = "error: " + String(repeating: "x", count: 20_000)
        check("una linea de error enorme se recorta pero no desaparece", squeeze(longLine).text.hasPrefix("error: xxx") && squeeze(longLine).text.contains("bytes]"))
        let footer = squeeze("a\nb\n").result.footer
        check("la linea final dice tokens antes y despues", footer.hasPrefix("[squeeze] ~") && footer.contains("tokens ->"))

        print(failures == 0 ? "SQUEEZE OK" : "SQUEEZE \(failures) FALLOS")
        return failures == 0
    }
}
