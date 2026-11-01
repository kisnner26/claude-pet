import Foundation

/// Pruebas sin red de lo que se anade a claudwler: avisos de la verificacion, exportacion y prompt de arreglo.
enum ClaudwlerExtrasSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }

        // avisos de la verificacion
        func ok200(final: String? = nil, code: Int? = nil, ms: Int = 120) -> LinkCheck { LinkCheck(state: .ok, note: "200", finalURL: final, redirectCode: code, millis: ms) }
        check("un enlace normal no avisa de nada", LinkChecker.warnings(for: ok200(), requested: "https://a.com/x").isEmpty)
        check("una redireccion permanente se avisa con su destino", LinkChecker.warnings(for: ok200(final: "https://a.com/nuevo", code: 301), requested: "https://a.com/viejo") == ["redirección permanente (301) → a.com/nuevo"])
        check("el 308 tambien es permanente", LinkChecker.warnings(for: ok200(final: "https://a.com/n", code: 308), requested: "https://a.com/v").count == 1)
        check("una redireccion temporal no se avisa", LinkChecker.warnings(for: ok200(final: "https://a.com/login", code: 302), requested: "https://a.com/panel").isEmpty)
        check("caer de https a http se avisa", LinkChecker.warnings(for: ok200(final: "http://a.com/x", code: 302), requested: "https://a.com/x") == ["redirige a http sin cifrar"])
        check("de http a https no es problema", LinkChecker.warnings(for: ok200(final: "https://a.com/x", code: 302), requested: "http://a.com/x").isEmpty)
        check("tres segundos ya es lento", LinkChecker.warnings(for: ok200(ms: 3200), requested: "https://a.com") == ["lento (3.2 s)"])
        check("2,9 segundos no es lento", LinkChecker.warnings(for: ok200(ms: 2900), requested: "https://a.com").isEmpty)
        check("un enlace roto no suma avisos", LinkChecker.warnings(for: LinkCheck(state: .broken, note: "404", finalURL: "http://x", redirectCode: 301, millis: 9000), requested: "https://a.com").isEmpty)
        check("el destino se acorta sin esquema ni barra final", LinkChecker.shortURL("https://a.com/") == "a.com" && LinkChecker.shortURL("http://a.com/x/y") == "a.com/x/y")
        check("un destino larguisimo se recorta", LinkChecker.shortURL("https://a.com/" + String(repeating: "z", count: 100)).count == 60)

        // CSV
        check("una celda simple queda tal cual", WebCrawlerReport.csvCell("inicio") == "inicio")
        check("una coma o unas comillas piden comillas y se duplican", WebCrawlerReport.csvCell("a, b") == "\"a, b\"" && WebCrawlerReport.csvCell("di \"hola\"") == "\"di \"\"hola\"\"\"")
        check("los saltos de linea se aplanan", WebCrawlerReport.csvCell("uno\ndos") == "uno dos")
        check("una formula no se ejecuta en la hoja de calculo", WebCrawlerReport.csvCell("=HYPERLINK(\"x\")").hasPrefix("\"'=") && WebCrawlerReport.csvCell("+34 600").hasPrefix("'+"))
        let entries = [
            ReportEntry(link: CrawledLink(text: "Inicio", url: "http://localhost:3000/"), problems: [], check: LinkCheck(state: .ok, note: "200", millis: 80), hints: []),
            ReportEntry(link: CrawledLink(text: "aquí", url: "http://localhost:3000/precios"), problems: ["texto genérico"], check: nil, hints: ["src/app/page.tsx:42"]),
            ReportEntry(link: CrawledLink(text: "Docs, guía", url: "http://localhost:3000/docs"), problems: ["roto · 404"], check: LinkCheck(state: .broken, note: "404", millis: 40), hints: ["src/nav.tsx:7", "src/footer.tsx:3"])]
        let lines = WebCrawlerReport.csv(entries).split(separator: "\n").map(String.init)
        check("el CSV tiene cabecera y una fila por enlace", lines.count == 4 && lines[0] == "texto,destino,estado,codigo,milisegundos,problemas,codigo_fuente")
        check("los rotos van primero", lines[1].hasPrefix("\"Docs, guía\",http://localhost:3000/docs,roto,404,40,"))
        check("las pistas de codigo se separan con barra", lines[1].hasSuffix("src/nav.tsx:7 | src/footer.tsx:3"))
        check("un aviso sin verificar en red se marca como aviso", lines[2].contains(",aviso,") && lines[3].contains(",ok,200,80,"))
        // prompt de arreglo
        let prompt = WebCrawlerReport.fixPrompt(entries, site: "localhost:3000")
        check("el prompt cuenta solo lo que falla", prompt?.contains("Son 2.") == true && prompt?.contains("Inicio") == false)
        check("los rotos van primero con su pista de codigo", prompt.map { $0.range(of: "Docs, guía")!.lowerBound < $0.range(of: "aquí")!.lowerBound && $0.contains("`src/nav.tsx:7`, `src/footer.tsx:3`") } == true)
        check("explica que la pista es archivo:linea", prompt?.contains("`archivo:línea`") == true)
        check("sin problemas no hay prompt", WebCrawlerReport.fixPrompt([entries[0]], site: "x") == nil)
        let many = (0..<50).map { ReportEntry(link: CrawledLink(text: "e\($0)", url: "http://a.com/\($0)"), problems: ["texto genérico"], check: nil, hints: []) }
        check("con muchos problemas se limita", WebCrawlerReport.fixPrompt(many, site: "a.com", limit: 40)?.contains("te paso los 40 mas graves") == true
              && WebCrawlerReport.fixPrompt(many, site: "a.com", limit: 40)?.contains("40. ") == true && WebCrawlerReport.fixPrompt(many, site: "a.com", limit: 40)?.contains("41. ") == false)
        print(ok ? "CLAUDWLER EXTRAS OK" : "CLAUDWLER EXTRAS FALLO")
        return ok
    }
}
