import Foundation

/// Recorrido de un sitio entero a traves de HTTP: parte de una pagina, sigue los enlaces internos (mismo dominio) hasta una
/// profundidad y un numero maximo de paginas, y apunta de cada una el estado, lo que tarda y lo que conviene arreglar.
/// Es una cola con un cargador inyectado: no sabe de red, asi se prueba con un sitio de mentira.

struct FetchedPage: Equatable {
    var status: Int                  // 0 = no hubo respuesta
    var contentType = ""
    var body = ""
    var millis = 0
    var finalURL = ""
    var error = ""
}

struct SitePage: Equatable {
    var url: String
    var depth: Int
    var status: Int
    var millis: Int
    var title: String
    var problems: [String]
    var linkCount: Int
    var error: String
}

struct SiteBrokenLink: Equatable {
    var url: String
    var status: Int
    var foundOn: [String]
}

struct SiteCrawlOutcome: Equatable {
    var start: String
    var pages: [SitePage]
    var broken: [SiteBrokenLink]
    /// Enlaces a otros dominios y en que paginas aparecen (no se siguen).
    var external: [String: [String]]
    /// Rutas que robots.txt pide no recorrer.
    var blockedByRobots: [String]
    /// Quedaron paginas sin visitar por el tope.
    var truncated: Bool
}

/// robots.txt: solo se lee lo que aplica a todos los agentes o a claudwler, y solo Disallow.
enum RobotsTxt {
    static func disallowed(_ text: String, agent: String = "claudwler") -> [String] {
        var applies = false, lastWasAgent = false
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "user-agent":
                // varias lineas User-agent seguidas forman un solo grupo
                let a = value.lowercased(), match = a == "*" || a == agent.lowercased()
                applies = lastWasAgent ? (applies || match) : match
                lastWasAgent = true
            case "disallow":
                lastWasAgent = false
                if applies, !value.isEmpty { out.append(value) }
            default: lastWasAgent = false
            }
        }
        return out
    }

    static func allows(path: String, disallowed: [String]) -> Bool {
        !disallowed.contains { rule in
            let r = rule.replacingOccurrences(of: "*", with: "")
            return !r.isEmpty && path.hasPrefix(r.hasSuffix("$") ? String(r.dropLast()) : r)
        }
    }
}

enum SiteCrawl {
    /// Recursos que no son paginas: no se descargan ni cuentan.
    static let assetExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "pdf", "zip", "gz", "mp4", "mov", "mp3", "wav", "css", "js", "json", "xml", "woff", "woff2", "ttf", "dmg", "exe"]

    static func isAsset(_ url: URL) -> Bool { assetExtensions.contains(url.pathExtension.lowercased()) }

    private static func origin(_ url: URL) -> String { "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? "")\(url.port.map { ":\($0)" } ?? "")" }

    static func run(start: URL, maxPages: Int = 40, maxDepth: Int = 3, concurrency: Int = 4,
                    fetch: @escaping @Sendable (URL) async -> FetchedPage,
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async -> SiteCrawlOutcome {
        let home = origin(start)
        var outcome = SiteCrawlOutcome(start: start.absoluteString, pages: [], broken: [], external: [:], blockedByRobots: [], truncated: false)

        // robots.txt
        var disallow: [String] = []
        if let robotsURL = URL(string: home + "/robots.txt") {
            let robots = await fetch(robotsURL)
            if robots.status == 200 { disallow = RobotsTxt.disallowed(robots.body) }
        }

        var queue: [(url: String, depth: Int)] = [(start.absoluteString, 0)]
        var queued: Set<String> = [start.absoluteString]
        var inbound: [String: [String]] = [:]
        var results: [String: SitePage] = [:]
        var order: [String] = []

        while !queue.isEmpty, results.count < maxPages, !Task.isCancelled {
            let take = min(concurrency, maxPages - results.count, queue.count)
            let batch = Array(queue.prefix(take))
            queue.removeFirst(take)

            let fetched: [(String, Int, FetchedPage)] = await withTaskGroup(of: (Int, String, Int, FetchedPage).self) { group in
                for (i, item) in batch.enumerated() {
                    group.addTask { (i, item.url, item.depth, await fetch(URL(string: item.url)!)) }
                }
                var out: [(Int, String, Int, FetchedPage)] = []
                for await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2, $0.3) }
            }

            for (urlString, depth, page) in fetched {
                let url = URL(string: urlString)!
                var info = SitePage(url: urlString, depth: depth, status: page.status, millis: page.millis, title: "", problems: [], linkCount: 0, error: page.error)
                let leftSite = !page.finalURL.isEmpty && URL(string: page.finalURL).map { origin($0) != home } == true
                let isHTML = page.contentType.lowercased().contains("html") || (page.contentType.isEmpty && page.body.lowercased().contains("<html"))
                if page.status >= 200, page.status < 400, isHTML, !leftSite {
                    let scan = HTMLScan.scan(html: page.body, base: URL(string: page.finalURL) ?? url)
                    info.title = scan.title
                    info.problems = HTMLScan.problems(scan)
                    info.linkCount = scan.links.count
                    for link in scan.links {
                        guard let target = URL(string: link.url) else { continue }
                        if origin(target) != home {
                            outcome.external[link.url, default: []].append(urlString)
                            continue
                        }
                        inbound[link.url, default: []].append(urlString)
                        if isAsset(target) || queued.contains(link.url) { continue }
                        if !RobotsTxt.allows(path: target.path.isEmpty ? "/" : target.path, disallowed: disallow) {
                            if !outcome.blockedByRobots.contains(target.path) { outcome.blockedByRobots.append(target.path) }
                            continue
                        }
                        if depth + 1 <= maxDepth { queued.insert(link.url); queue.append((link.url, depth + 1)) }
                    }
                } else if leftSite {
                    info.problems.append("redirige fuera del sitio")
                }
                results[urlString] = info
                order.append(urlString)
                progress?(results.count, results.count + queue.count)
            }
        }

        outcome.pages = order.compactMap { results[$0] }
        outcome.truncated = !queue.isEmpty
        outcome.broken = outcome.pages.filter { $0.status == 0 || $0.status >= 400 }.map {
            SiteBrokenLink(url: $0.url, status: $0.status, foundOn: Array(Set(inbound[$0.url] ?? [])).sorted())
        }
        for key in outcome.external.keys { outcome.external[key] = Array(Set(outcome.external[key] ?? [])).sorted() }
        return outcome
    }
}
