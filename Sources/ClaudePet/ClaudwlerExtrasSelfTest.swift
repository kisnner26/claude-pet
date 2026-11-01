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
        // carpeta del informe guardado
        let when = Date(timeIntervalSince1970: 1_793_547_000)
        let utc = TimeZone(identifier: "UTC")!
        check("la carpeta lleva sitio y fecha", WebCrawlerReport.folderName(site: "localhost:3000", date: when, timeZone: utc) == "claudwler-localhost-3000-20261101-153000")
        check("un sitio con rutas y mayusculas se limpia", WebCrawlerReport.folderName(site: "Mi-Sitio.com/Blog", date: when, timeZone: utc) == "claudwler-mi-sitio-com-blog-20261101-153000")
        check("un sitio vacio no deja un nombre roto", WebCrawlerReport.folderName(site: "", date: when, timeZone: utc) == "claudwler-sitio-20261101-153000")
        // lector de HTML
        let base = URL(string: "https://sitio.com/blog/post")!
        let html = """
        <!doctype html><html lang="es"><head><title>  Mi &amp; sitio
          </title><meta name="description" content="Una descripción corta">
        <meta content='index,noindex' name='robots'><link rel="canonical" href="https://sitio.com/blog/post">
        <script>var x = "<a href='/falso'>no</a>";</script><style>a{}</style></head><body>
        <h1>Hola</h1><h1 class="x">Otra vez</h1>
        <img src="a.png"><img src="b.png" alt=""><img src='c.png' alt='un gato'><IMG SRC=d.png>
        <a href="/precios">Precios <b>hoy</b></a> <a href='../otro?x=1#sec' class=y>Otro</a>
        <a href="https://externo.org/p">Externo</a> <a href="#arriba">arriba</a> <a href="mailto:a@b.com">correo</a>
        <a href="javascript:void(0)">js</a> <a href="/solo-icono" aria-label="Menú"><svg></svg></a> <a href="/precios">Precios <b>hoy</b></a>
        </body></html>
        """
        let page = HTMLScan.scan(html: html, base: base)
        check("el titulo se limpia", page.title == "Mi & sitio")
        check("lee descripcion, idioma y canonical", page.description == "Una descripción corta" && page.lang == "es" && page.canonical == "https://sitio.com/blog/post")
        check("detecta noindex aunque los atributos vengan al reves", page.noindex)
        check("cuenta los h1", page.h1Count == 2)
        check("solo las imagenes sin atributo alt fallan (alt vacio vale)", page.imagesWithoutAlt == 2)
        check("el script y el estilo no aportan enlaces", !page.links.contains { $0.url.contains("falso") })
        check("las rutas relativas se resuelven y el fragmento se quita", page.links.contains { $0.url == "https://sitio.com/precios" } && page.links.contains { $0.url == "https://sitio.com/otro?x=1" })
        check("el texto del enlace se limpia de etiquetas", page.links.first { $0.url.hasSuffix("/precios") }?.text == "Precios hoy")
        check("un enlace solo con icono usa su aria-label", page.links.first { $0.url.hasSuffix("/solo-icono") }?.text == "Menú")
        check("no se cuentan anclas, correo ni javascript", !page.links.contains { $0.url.contains("arriba") || $0.url.contains("mailto") || $0.url.contains("void") })
        check("un enlace repetido no se duplica", page.links.filter { $0.url.hasSuffix("/precios") }.count == 1)
        check("los problemas de la pagina", HTMLScan.problems(page) == ["2 h1", "2 imágenes sin alt", "noindex: se esconde de los buscadores"])
        let bare = HTMLScan.scan(html: "<html><body><p>nada</p></body></html>", base: base)
        check("una pagina pelada acumula avisos", HTMLScan.problems(bare) == ["sin título", "sin meta descripción", "sin h1", "sin idioma (html lang)"])
        check("un titulo larguisimo se avisa", HTMLScan.problems(PageScan(title: String(repeating: "t", count: 80), description: "d", h1Count: 1, lang: "es")) == ["título largo (80 caracteres)"])
        check("resolver ignora lo que no es web", HTMLScan.resolve("ftp://x.com/a", base: base) == nil && HTMLScan.resolve("tel:123", base: base) == nil && HTMLScan.resolve("/ok", base: base) == "https://sitio.com/ok")
        print(ok ? "CLAUDWLER EXTRAS OK" : "CLAUDWLER EXTRAS FALLO")
        return ok
    }
}
