import Foundation

/// Lo que claudwler lee de una pagina HTML para el recorrido del sitio entero. Todo es texto: no ejecuta nada ni abre un navegador.
struct PageScan: Equatable {
    var title = ""
    var description = ""
    var h1Count = 0
    var lang = ""
    var imagesWithoutAlt = 0
    var noindex = false
    var canonical = ""
    var links: [CrawledLink] = []
}

enum HTMLScan {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // los patrones son constantes de este archivo: si uno estuviera mal, mejor enterarse en las pruebas
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }
    private static let titleRE = regex("<title[^>]*>(.*?)</title>")
    private static let metaRE = regex("<meta\\b[^>]*>")
    private static let h1RE = regex("<h1[\\s>]")
    private static let htmlRE = regex("<html\\b[^>]*>")
    private static let imgRE = regex("<img\\b[^>]*>")
    private static let linkTagRE = regex("<link\\b[^>]*>")
    private static let anchorRE = regex("<a\\b([^>]*)>(.*?)</a>")
    private static let tagRE = regex("<[^>]+>")
    private static let scriptRE = regex("<(script|style)\\b.*?</\\1>")

    /// Valor de un atributo dentro de una etiqueta, con comillas dobles, simples o sin ellas.
    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?:^|[\\s\"'])\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for g in 1...3 { if let r = Range(m.range(at: g), in: tag) { return String(tag[r]) } }
        return nil
    }

    static func hasAttribute(_ name: String, in tag: String) -> Bool {
        let pattern = "(?:^|[\\s\"'])\(name)(?:\\s*=|[\\s>/])"
        return (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) != nil
    }

    static func decode(_ text: String) -> String {
        var out = text
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func matches(_ re: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func string(_ m: NSTextCheckingResult, _ group: Int, in text: String) -> String {
        Range(m.range(at: group), in: text).map { String(text[$0]) } ?? ""
    }

    static func scan(html: String, base: URL) -> PageScan {
        var page = PageScan()
        let body = scriptRE.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ")

        if let m = matches(titleRE, in: body).first {
            let raw = string(m, 1, in: body)
            page.title = decode(tagRE.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: ""))
        }
        for m in matches(metaRE, in: body) {
            let tag = string(m, 0, in: body)
            let name = (attribute("name", in: tag) ?? attribute("property", in: tag) ?? "").lowercased()
            let content = decode(attribute("content", in: tag) ?? "")
            if name == "description", page.description.isEmpty { page.description = content }
            if name == "robots", content.lowercased().contains("noindex") { page.noindex = true }
        }
        page.h1Count = matches(h1RE, in: body).count
        if let m = matches(htmlRE, in: body).first { page.lang = attribute("lang", in: string(m, 0, in: body)) ?? "" }
        // alt="" es decorativa y vale; lo que falla es no tener el atributo
        page.imagesWithoutAlt = matches(imgRE, in: body).filter { !hasAttribute("alt", in: string($0, 0, in: body)) }.count
        for m in matches(linkTagRE, in: body) {
            let tag = string(m, 0, in: body)
            if (attribute("rel", in: tag) ?? "").lowercased() == "canonical", let href = attribute("href", in: tag) { page.canonical = href }
        }

        var seen = Set<String>()
        for m in matches(anchorRE, in: body) {
            let attrs = string(m, 1, in: body)
            guard let href = attribute("href", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                  let url = resolve(href, base: base) else { continue }
            let inner = string(m, 2, in: body)
            var text = decode(tagRE.stringByReplacingMatches(in: inner, range: NSRange(inner.startIndex..., in: inner), withTemplate: " "))
            if text.isEmpty, let label = attribute("aria-label", in: attrs) ?? attribute("title", in: attrs) { text = decode(label) }
            let link = CrawledLink(text: text, url: url)
            if seen.insert(link.url + "\u{0}" + link.text).inserted { page.links.append(link) }
        }
        return page
    }

    /// Una URL absoluta http(s) sin fragmento; nil para mailto:, tel:, javascript: y lo que no se pueda resolver.
    static func resolve(_ href: String, base: URL) -> String? {
        let lower = href.lowercased()
        if lower.hasPrefix("#") || lower.hasPrefix("javascript:") || lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") || lower.hasPrefix("data:") { return nil }
        guard let url = URL(string: href, relativeTo: base)?.absoluteURL, var comps = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https", comps.host != nil else { return nil }
        comps.fragment = nil
        return comps.url?.absoluteString
    }

    /// Lo que conviene arreglar de una pagina (titulo, descripcion, encabezados, idioma, imagenes y si se esconde de los buscadores).
    static func problems(_ page: PageScan) -> [String] {
        var out: [String] = []
        if page.title.isEmpty { out.append("sin título") }
        else if page.title.count > 70 { out.append("título largo (\(page.title.count) caracteres)") }
        if page.description.isEmpty { out.append("sin meta descripción") }
        else if page.description.count > 170 { out.append("descripción larga (\(page.description.count) caracteres)") }
        if page.h1Count == 0 { out.append("sin h1") } else if page.h1Count > 1 { out.append("\(page.h1Count) h1") }
        if page.lang.isEmpty { out.append("sin idioma (html lang)") }
        if page.imagesWithoutAlt > 0 { out.append("\(page.imagesWithoutAlt) \(page.imagesWithoutAlt == 1 ? "imagen" : "imágenes") sin alt") }
        if page.noindex { out.append("noindex: se esconde de los buscadores") }
        return out
    }
}
