import Foundation

enum WebCrawlerSelfTest {
    static func run(htmlOut: String?) -> Bool {
        var failures = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if condition() { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
        }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var results: [LinkCheck] = []
        Task.detached {
            results = [await LinkChecker.check("https://example.com"),
                       await LinkChecker.check("https://example.com/no-existe-claudwler"),
                       await LinkChecker.check("https://dominio-que-no-existe-claudwler.invalid")]
            semaphore.signal()
        }
        semaphore.wait()
        print("red:", results.map { "\($0.state.rawValue)/\($0.note)" })
        check("enlace vivo es ok", results[0].state == .ok)
        check("404 es roto", results[1].state == .broken)
        check("dominio inexistente es roto", results[2].state == .broken)

        let entries = [
            ReportEntry(link: CrawledLink(text: "Inicio", url: "http://localhost:3000/"), problems: [], check: LinkCheck(state: .ok, note: "200"), hints: []),
            ReportEntry(link: CrawledLink(text: "aquí", url: "http://localhost:3000/precios"), problems: ["texto genérico"], check: nil, hints: ["src/app/page.tsx:42"]),
            ReportEntry(link: CrawledLink(text: "Docs", url: "http://localhost:3000/docs"), problems: ["roto · 404"], check: LinkCheck(state: .broken, note: "404"), hints: ["src/nav.tsx:7"])
        ]
        let now = CrawlSnapshot(date: .now, entries: entries.map { .init(key: $0.key, text: $0.link.text, url: $0.link.url, problems: $0.problems) })
        let before = CrawlSnapshot(date: .now.addingTimeInterval(-3600), entries: [
            .init(key: "http://localhost:3000/", text: "Inicio", url: "http://localhost:3000/", problems: ["sin texto accesible"]),
            .init(key: "http://localhost:3000/viejo", text: "Viejo", url: "http://localhost:3000/viejo", problems: [])
        ])
        let diff = CrawlHistory.diff(previous: before, current: now)
        check("diff: 2 nuevos", diff.newLinks.count == 2)
        check("diff: 1 desaparecido", diff.goneLinks.count == 1)
        check("diff: 1 arreglado", diff.fixed.count == 1)
        check("http en localhost no es problema", WebCrawlerReport.problems(for: entries[0].link, urlTexts: [:]).isEmpty)

        let report = WebCrawlerReport.build(entries, pages: 2, site: "localhost:3000", diff: diff, verified: true)
        check("informe cuenta 2 con problemas y 1 roto", report.flagged == 2 && report.broken == 1)
        check("informe trae la pista de código", report.markdown.contains("src/nav.tsx:7"))
        if let htmlOut { try? report.html.write(toFile: htmlOut, atomically: true, encoding: .utf8) }
        print(report.markdown)
        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
