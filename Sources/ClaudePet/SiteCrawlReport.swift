import Foundation

/// Informe del recorrido del sitio entero: lo roto primero, luego las paginas con avisos, las mas lentas y los dominios externos.
enum SiteCrawlReport {
    struct Output {
        let markdown: String
        let html: String
        let flagged: Int
        let broken: Int
        let averageMillis: Int
    }

    /// Las rutas se ensenan sin el dominio: dentro del informe ya se sabe de que sitio hablan.
    static func path(_ url: String) -> String {
        guard let u = URL(string: url) else { return url }
        let p = u.path.isEmpty ? "/" : u.path
        return u.query.map { p + "?" + $0 } ?? p
    }

    static func host(_ url: String) -> String { URL(string: url)?.host ?? url }

    static func slowest(_ pages: [SitePage], limit: Int = 5, minMillis: Int = 800) -> [SitePage] {
        Array(pages.filter { $0.status > 0 && $0.millis >= minMillis }.sorted { $0.millis > $1.millis }.prefix(limit))
    }

    static func externalHosts(_ external: [String: [String]]) -> [(host: String, links: Int)] {
        Dictionary(grouping: external.keys, by: host).map { ($0.key, $0.value.count) }.sorted { $0.links != $1.links ? $0.links > $1.links : $0.host < $1.host }
    }

    static func build(_ outcome: SiteCrawlOutcome, date: Date = Date()) -> Output {
        let pages = outcome.pages
        let withIssues = pages.filter { !$0.problems.isEmpty && $0.status > 0 && $0.status < 400 }
        let ok = pages.filter { $0.status > 0 }
        let average = ok.isEmpty ? 0 : ok.map(\.millis).reduce(0, +) / ok.count
        let site = host(outcome.start)
        let hosts = externalHosts(outcome.external)

        var md = "# recorrido del sitio · \(site)\n\n"
        md += "\(pages.count) \(pages.count == 1 ? "página" : "páginas") · \(withIssues.count) con avisos · \(outcome.broken.count) rotas · \(hosts.count) dominios externos · \(average) ms de media"
        md += outcome.truncated ? " · recorrido incompleto (tope de páginas)\n\n" : "\n\n"
        if !outcome.broken.isEmpty {
            md += "## páginas rotas\n\n"
            for b in outcome.broken {
                md += "- \(path(b.url)) (\(b.status == 0 ? "sin respuesta" : String(b.status)))"
                md += b.foundOn.isEmpty ? "\n" : " — enlazada desde: " + b.foundOn.prefix(6).map { "`\(path($0))`" }.joined(separator: ", ") + (b.foundOn.count > 6 ? " y \(b.foundOn.count - 6) más\n" : "\n")
            }
            md += "\n"
        }
        if !withIssues.isEmpty {
            md += "## páginas con avisos\n\n"
            for p in withIssues { md += "- \(path(p.url)) — \(p.problems.joined(separator: "; "))\n" }
            md += "\n"
        }
        let slow = slowest(pages)
        if !slow.isEmpty {
            md += "## las más lentas\n\n"
            for p in slow { md += "- \(path(p.url)) — \(p.millis) ms\n" }
            md += "\n"
        }
        if !outcome.blockedByRobots.isEmpty {
            md += "## vetadas por robots.txt (no se recorrieron)\n\n" + outcome.blockedByRobots.map { "- \($0)\n" }.joined() + "\n"
        }
        if !hosts.isEmpty {
            md += "## dominios externos\n\n" + hosts.prefix(30).map { "- \($0.host) (\($0.links))\n" }.joined() + "\n"
        }
        md += "## todas las páginas\n\n"
        for p in pages { md += "- \(path(p.url)) · \(p.status == 0 ? "sin respuesta" : String(p.status)) · \(p.millis) ms\(p.title.isEmpty ? "" : " · \(p.title)")\n" }

        return Output(markdown: md, html: html(outcome, site: site, withIssues: withIssues, slow: slow, hosts: hosts, average: average, date: date),
                      flagged: withIssues.count, broken: outcome.broken.count, averageMillis: average)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func html(_ o: SiteCrawlOutcome, site: String, withIssues: [SitePage], slow: [SitePage], hosts: [(host: String, links: Int)], average: Int, date: Date) -> String {
        func stat(_ v: Int, _ label: String, _ cls: String) -> String { "<div class=\"stat \(cls)\"><b>\(v)</b><span>\(label)</span></div>" }
        var body = "<header><p class=\"kicker\">claudwler · recorrido del sitio</p><h1>\(esc(site))</h1><p class=\"sub\">\(date.formatted(date: .abbreviated, time: .shortened))\(o.truncated ? " · incompleto: se llegó al tope de páginas" : "")</p></header>"
        body += "<section class=\"stats\">\(stat(o.pages.count, "páginas", "all"))\(stat(withIssues.count, "con avisos", "warn"))\(stat(o.broken.count, "rotas", "bad"))\(stat(hosts.count, "dominios externos", "ext"))\(stat(average, "ms de media", "all"))</section>"
        if !o.broken.isEmpty {
            body += "<h2>Páginas rotas <small>\(o.broken.count)</small></h2><div class=\"cards\">"
            for b in o.broken {
                let from = b.foundOn.prefix(6).map { "<span class=\"src\">\(esc(path($0)))</span>" }.joined()
                body += "<article class=\"card bad\"><h3>\(esc(path(b.url)))</h3><span class=\"chip bad\">\(b.status == 0 ? "sin respuesta" : String(b.status))</span>\(from.isEmpty ? "" : "<div class=\"srcs\">enlazada desde: \(from)</div>")</article>"
            }
            body += "</div>"
        }
        if !withIssues.isEmpty {
            body += "<h2>Páginas con avisos <small>\(withIssues.count)</small></h2><div class=\"cards\">"
            for p in withIssues {
                body += "<article class=\"card warn\"><h3>\(esc(path(p.url)))</h3>\(p.title.isEmpty ? "" : "<code>\(esc(p.title))</code>")<div>\(p.problems.map { "<span class=\"chip warn\">\(esc($0))</span>" }.joined())</div></article>"
            }
            body += "</div>"
        } else if o.broken.isEmpty {
            body += "<p class=\"clean\">Sin problemas en las páginas recorridas.</p>"
        }
        if !slow.isEmpty {
            body += "<h2>Las más lentas</h2><table>" + slow.map { "<tr><td>\(esc(path($0.url)))</td><td>\($0.millis) ms</td></tr>" }.joined() + "</table>"
        }
        if !hosts.isEmpty {
            body += "<h2>Dominios externos <small>\(hosts.count)</small></h2><table>" + hosts.prefix(30).map { "<tr><td>\(esc($0.host))</td><td>\($0.links) \($0.links == 1 ? "enlace" : "enlaces")</td></tr>" }.joined() + "</table>"
        }
        let rows = o.pages.map { "<tr><td><i class=\"dot \($0.status == 0 || $0.status >= 400 ? "bad" : ($0.problems.isEmpty ? "ok" : "warn"))\"></i></td><td>\(esc(path($0.url)))</td><td>\($0.status == 0 ? "—" : String($0.status))</td><td>\($0.millis) ms</td><td>\(esc($0.title))</td></tr>" }.joined()
        body += "<details><summary>Todas las páginas (\(o.pages.count))</summary><table>\(rows)</table></details>"
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>claudwler · \(esc(site))</title><style>
        :root{--crema:#F4EDE1;--tinta:#1C1B1A;--coral:#E0824F;--ok:#4C9A6A;--warn:#D9A13B;--bad:#C94B3F;--linea:#1C1B1A22}
        *{box-sizing:border-box}body{margin:0;background:var(--crema);color:var(--tinta);font:16px/1.5 -apple-system,system-ui,sans-serif}
        main{max-width:960px;margin:0 auto;padding:40px 16px 80px}.kicker{font:600 12px ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--coral);margin:0}
        h1{font-size:clamp(32px,6vw,56px);line-height:1.05;font-weight:900;margin:8px 0;word-break:break-word}.sub{margin:0 0 28px;opacity:.65}
        h2{font-size:24px;font-weight:900;margin:44px 0 14px}h2 small{font:500 14px ui-monospace,monospace;opacity:.55;margin-left:8px}
        .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}.stat{background:#fff8;border:2px solid var(--tinta);border-radius:10px;padding:14px 16px;box-shadow:3px 3px 0 var(--tinta)}
        .stat b{display:block;font-size:34px;line-height:1;font-weight:900}.stat span{font:12px ui-monospace,monospace;text-transform:uppercase;opacity:.7}
        .stat.warn b{color:var(--warn)}.stat.bad b{color:var(--bad)}.stat.ext b{color:var(--coral)}
        .cards{display:grid;gap:12px}.card{background:#fffc;border:2px solid var(--tinta);border-left-width:10px;border-radius:8px;padding:14px 16px}.card.bad{border-left-color:var(--bad)}.card.warn{border-left-color:var(--warn)}
        .card h3{margin:0 0 4px;font-size:17px;word-break:break-word}code{font:13px ui-monospace,monospace;word-break:break-all;opacity:.75}
        .chip{display:inline-block;margin:8px 6px 0 0;padding:2px 10px;border-radius:99px;font:600 12px ui-monospace,monospace;color:#fff}.chip.bad{background:var(--bad)}.chip.warn{background:var(--warn);color:var(--tinta)}
        .srcs{margin-top:10px;font:13px ui-monospace,monospace}.src{display:inline-block;background:var(--tinta);color:var(--crema);padding:2px 8px;border-radius:6px;margin:2px 6px 2px 0}
        .clean{padding:18px;border:2px dashed var(--ok);border-radius:8px;color:var(--ok);font-weight:700}details{margin-top:40px}summary{cursor:pointer;font-weight:900;font-size:18px}
        table{width:100%;border-collapse:collapse;margin-top:12px;font-size:14px}td{padding:7px 8px;border-top:1px solid var(--linea);vertical-align:top;word-break:break-word}
        .dot{display:inline-block;width:10px;height:10px;border-radius:50%}.dot.ok{background:var(--ok)}.dot.warn{background:var(--warn)}.dot.bad{background:var(--bad)}
        @media (prefers-color-scheme:dark){:root{--crema:#1C1B1A;--tinta:#EDE3DA;--linea:#EDE3DA22}.stat,.card{background:#ffffff0d}}
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}
