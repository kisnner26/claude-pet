import Foundation

struct CrawledLink: Hashable {
    let text: String
    let url: String
}

struct ReportEntry {
    let link: CrawledLink
    let problems: [String]
    let check: LinkCheck?
    let hints: [String]

    var broken: Bool { check?.state == .broken }
    var key: String { link.url.isEmpty ? "texto:" + link.text : link.url }
}

/// Informe de enlaces de la página recorrida por claudwler, en markdown (para pegar en Claude Code) y en HTML visual.
enum WebCrawlerReport {
    private static let genericTexts: Set<String> = [
        "click here", "here", "read more", "more", "link", "learn more", "aqui", "aquí", "haz clic aqui", "haz clic aquí",
        "leer mas", "leer más", "mas", "más", "ver mas", "ver más", "pulsa aqui", "pulsa aquí"
    ]

    static func problems(for link: CrawledLink, urlTexts: [String: Set<String>]) -> [String] {
        var found: [String] = []
        let text = link.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { found.append("sin texto accesible") }
        else if genericTexts.contains(text.lowercased()) { found.append("texto genérico") }
        if link.url.isEmpty { found.append("sin destino") }
        else if link.url.lowercased().hasPrefix("http://"), !isLocal(link.url) { found.append("http sin cifrar") }
        if !link.url.isEmpty, (urlTexts[link.url]?.count ?? 0) > 1 { found.append("mismo destino con textos distintos") }
        return found
    }

    static func isLocal(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }

    struct Output {
        let markdown: String
        let html: String
        let flagged: Int
        let broken: Int
        let external: Int
    }

    static func build(_ entries: [ReportEntry], pages: Int, site: String, diff: CrawlDiff?, verified: Bool) -> Output {
        let hosts = entries.compactMap { URL(string: $0.link.url)?.host }
        let home = Dictionary(grouping: hosts, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let external = entries.filter { entry in
            guard let host = URL(string: entry.link.url)?.host, let home else { return false }
            return host != home
        }.count
        let flagged = entries.filter { !$0.problems.isEmpty }
        let broken = entries.filter(\.broken).count
        let sorted = entries.sorted { rank($0) < rank($1) }
        let date = Date().formatted(date: .abbreviated, time: .shortened)

        // markdown
        var md = "# informe de claudwler · \(site)\n\n"
        md += "\(entries.count) enlaces únicos · \(pages) \(pages == 1 ? "página" : "páginas") · \(flagged.count) con problemas · \(broken) rotos · \(external) externos"
        md += verified ? " · verificados en red\n\n" : "\n\n"
        let anyHints = entries.contains { !$0.hints.isEmpty }
        if anyHints { md += "Corrige estos problemas en el proyecto. Cada línea trae la pista `archivo:línea` donde aparece el enlace.\n\n" }
        if let diff, !diff.isEmpty {
            md += "## cambios desde el recorrido anterior (\(diff.previousDate.formatted(date: .abbreviated, time: .shortened)))\n\n"
            md += section("enlaces nuevos", diff.newLinks, mark: "+")
            md += section("problemas nuevos", diff.newProblems, mark: "!")
            md += section("arreglados o ya sin problema", diff.fixed, mark: "ok")
            md += section("enlaces que ya no aparecen", diff.goneLinks, mark: "-")
        }
        if !flagged.isEmpty {
            md += "## problemas\n\n"
            for entry in sorted where !entry.problems.isEmpty {
                md += "- \(display(entry.link)) → \(destination(entry.link)) — \(entry.problems.joined(separator: ", "))"
                if !entry.hints.isEmpty { md += " — en: " + entry.hints.map { "`\($0)`" }.joined(separator: ", ") }
                md += "\n"
            }
            md += "\n"
        }
        md += "## todos los enlaces\n\n"
        for entry in sorted { md += "- \(display(entry.link)) → \(destination(entry.link))\n" }

        let html = buildHTML(sorted, pages: pages, site: site, diff: diff, verified: verified, date: date,
                             flagged: flagged.count, broken: broken, external: external)
        return Output(markdown: md, html: html, flagged: flagged.count, broken: broken, external: external)
    }

    private static func rank(_ entry: ReportEntry) -> Int { entry.broken ? 0 : (entry.problems.isEmpty ? 2 : 1) }

    private static func display(_ link: CrawledLink) -> String {
        let text = link.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(vacío)" : text
    }

    private static func destination(_ link: CrawledLink) -> String { link.url.isEmpty ? "(sin destino)" : link.url }

    private static func section(_ title: String, _ items: [CrawlSnapshot.Entry], mark: String) -> String {
        guard !items.isEmpty else { return "" }
        var out = "**\(title)** (\(items.count))\n"
        for item in items.prefix(25) {
            out += "- \(mark) \(item.text.isEmpty ? "(vacío)" : item.text) → \(item.url.isEmpty ? "(sin destino)" : item.url)\n"
        }
        if items.count > 25 { out += "- … y \(items.count - 25) más\n" }
        return out + "\n"
    }

    // MARK: HTML

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func buildHTML(_ entries: [ReportEntry], pages: Int, site: String, diff: CrawlDiff?, verified: Bool,
                                  date: String, flagged: Int, broken: Int, external: Int) -> String {
        let total = max(entries.count, 1)
        let warn = max(flagged - broken, 0)
        let ok = max(entries.count - flagged, 0)
        func pct(_ n: Int) -> String { String(format: "%.2f", Double(n) / Double(total) * 100) }

        func stat(_ value: Int, _ label: String, _ cls: String) -> String {
            "<div class=\"stat \(cls)\"><b>\(value)</b><span>\(label)</span></div>"
        }
        var body = """
        <header><p class="kicker">claudwler · informe de enlaces</p><h1>\(esc(site))</h1>
        <p class="sub">\(date) · \(pages) \(pages == 1 ? "página" : "páginas")\(verified ? " · verificado en red" : " · sin verificar en red")</p></header>
        <section class="stats">\(stat(entries.count, "enlaces", "all"))\(stat(ok, "bien", "ok"))\(stat(warn, "avisos", "warn"))\(stat(broken, "rotos", "bad"))\(stat(external, "externos", "ext"))</section>
        <div class="bar"><i class="ok" style="width:\(pct(ok))%"></i><i class="warn" style="width:\(pct(warn))%"></i><i class="bad" style="width:\(pct(broken))%"></i></div>
        """

        if let diff, !diff.isEmpty {
            body += "<h2>Cambios desde el recorrido anterior <small>\(esc(diff.previousDate.formatted(date: .abbreviated, time: .shortened)))</small></h2><div class=\"diff\">"
            func col(_ title: String, _ items: [CrawlSnapshot.Entry], _ cls: String) -> String {
                guard !items.isEmpty else { return "" }
                let rows = items.prefix(20).map { "<li><b>\(esc($0.text.isEmpty ? "(vacío)" : $0.text))</b><code>\(esc($0.url))</code></li>" }.joined()
                return "<div class=\"col \(cls)\"><h3>\(title) <em>\(items.count)</em></h3><ul>\(rows)</ul></div>"
            }
            body += col("Nuevos", diff.newLinks, "new") + col("Problemas nuevos", diff.newProblems, "bad")
            body += col("Arreglados", diff.fixed, "ok") + col("Ya no aparecen", diff.goneLinks, "gone")
            body += "</div>"
        }

        let problems = entries.filter { !$0.problems.isEmpty }
        if !problems.isEmpty {
            body += "<h2>Problemas <small>\(problems.count)</small></h2><div class=\"cards\">"
            for entry in problems {
                var chips = entry.problems.map { "<span class=\"chip \(entry.broken ? "bad" : "warn")\">\(esc($0))</span>" }.joined()
                if let check = entry.check, check.state == .broken { chips = "<span class=\"chip bad\">\(esc(check.note))</span>" + chips }
                let hints = entry.hints.map { "<span class=\"src\">\(esc($0))</span>" }.joined()
                body += "<article class=\"card \(entry.broken ? "bad" : "warn")\"><h3>\(esc(display(entry.link)))</h3><code>\(esc(destination(entry.link)))</code><div>\(chips)</div>\(hints.isEmpty ? "" : "<div class=\"srcs\">código: \(hints)</div>")</article>"
            }
            body += "</div>"
        } else {
            body += "<p class=\"clean\">Sin problemas en los enlaces recorridos.</p>"
        }

        let rows = entries.map { entry -> String in
            let state = entry.broken ? "bad" : (entry.problems.isEmpty ? "ok" : "warn")
            let note = entry.check.map { " <span class=\"note\">\(esc($0.note))</span>" } ?? ""
            return "<tr><td><i class=\"dot \(state)\"></i></td><td>\(esc(display(entry.link)))\(note)</td><td><code>\(esc(destination(entry.link)))</code></td></tr>"
        }.joined()
        body += "<details><summary>Todos los enlaces (\(entries.count))</summary><table>\(rows)</table></details>"

        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>claudwler · \(esc(site))</title><style>
        :root{--crema:#F4EDE1;--tinta:#1C1B1A;--coral:#E0824F;--ok:#4C9A6A;--warn:#D9A13B;--bad:#C94B3F;--linea:#1C1B1A22}
        *{box-sizing:border-box}body{margin:0;background:var(--crema);color:var(--tinta);font:16px/1.5 -apple-system,system-ui,sans-serif}
        main{max-width:960px;margin:0 auto;padding:40px 16px 80px}
        .kicker{font:600 12px ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--coral);margin:0}
        h1{font-size:clamp(32px,6vw,56px);line-height:1.05;font-weight:900;margin:8px 0;word-break:break-word}
        .sub{margin:0 0 28px;opacity:.65}h2{font-size:24px;font-weight:900;margin:44px 0 14px}h2 small{font:500 14px ui-monospace,monospace;opacity:.55;margin-left:8px}
        .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}
        .stat{background:#fff8;border:2px solid var(--tinta);border-radius:10px;padding:14px 16px;box-shadow:3px 3px 0 var(--tinta)}
        .stat b{display:block;font-size:34px;line-height:1;font-weight:900}.stat span{font:12px ui-monospace,monospace;text-transform:uppercase;opacity:.7}
        .stat.ok b{color:var(--ok)}.stat.warn b{color:var(--warn)}.stat.bad b{color:var(--bad)}.stat.ext b{color:var(--coral)}
        .bar{display:flex;height:14px;border:2px solid var(--tinta);border-radius:8px;overflow:hidden;margin-top:18px;background:#fff8}
        .bar i{display:block;height:100%}.bar .ok{background:var(--ok)}.bar .warn{background:var(--warn)}.bar .bad{background:var(--bad)}
        .cards{display:grid;gap:12px}.card{background:#fffc;border:2px solid var(--tinta);border-left-width:10px;border-radius:8px;padding:14px 16px}
        .card.bad{border-left-color:var(--bad)}.card.warn{border-left-color:var(--warn)}
        .card h3{margin:0 0 4px;font-size:17px;word-break:break-word}code{font:13px ui-monospace,monospace;word-break:break-all;opacity:.75}
        .chip{display:inline-block;margin:8px 6px 0 0;padding:2px 10px;border-radius:99px;font:600 12px ui-monospace,monospace;color:#fff}
        .chip.bad{background:var(--bad)}.chip.warn{background:var(--warn);color:var(--tinta)}
        .srcs{margin-top:10px;font:13px ui-monospace,monospace}.src{display:inline-block;background:var(--tinta);color:var(--crema);padding:2px 8px;border-radius:6px;margin:2px 6px 2px 0}
        .diff{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}.col{background:#fffc;border:2px solid var(--tinta);border-radius:8px;padding:12px 14px}
        .col h3{margin:0 0 8px;font-size:15px}.col em{font:600 12px ui-monospace,monospace;font-style:normal;background:var(--tinta);color:var(--crema);border-radius:99px;padding:1px 8px;margin-left:6px}
        .col.ok{border-top:8px solid var(--ok)}.col.bad{border-top:8px solid var(--bad)}.col.new{border-top:8px solid var(--coral)}.col.gone{border-top:8px solid #888}
        .col ul{list-style:none;margin:0;padding:0}.col li{padding:6px 0;border-top:1px solid var(--linea)}.col li b{display:block;font-size:14px}
        .clean{padding:18px;border:2px dashed var(--ok);border-radius:8px;color:var(--ok);font-weight:700}
        details{margin-top:40px}summary{cursor:pointer;font-weight:900;font-size:18px}
        table{width:100%;border-collapse:collapse;margin-top:12px;font-size:14px}td{padding:7px 8px;border-top:1px solid var(--linea);vertical-align:top}
        .dot{display:inline-block;width:10px;height:10px;border-radius:50%}.dot.ok{background:var(--ok)}.dot.warn{background:var(--warn)}.dot.bad{background:var(--bad)}
        .note{font:11px ui-monospace,monospace;opacity:.6;margin-left:6px}
        @media (prefers-color-scheme:dark){:root{--crema:#1C1B1A;--tinta:#EDE3DA;--linea:#EDE3DA22}.stat,.card,.col,.bar{background:#ffffff0d}}
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}
