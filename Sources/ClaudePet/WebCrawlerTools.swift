import Foundation

// MARK: - Verificación de enlaces (opt-in: contacta los sitios)

enum LinkState: String, Codable { case ok, broken, unknown }

struct LinkCheck: Codable {
    let state: LinkState
    let note: String
}

private actor AsyncGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func enter() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }
}

enum LinkChecker {
    private static let gate = AsyncGate(limit: 6)
    /// Sesión efímera: sin cookies ni caché, para no enviar nada de la sesión del usuario.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["User-Agent": "claudwler/1.0 (ClaudePet; comprobación de enlaces)"]
        return URLSession(configuration: config)
    }()

    static func isCheckable(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func check(_ string: String) async -> LinkCheck {
        guard let url = URL(string: string) else { return LinkCheck(state: .unknown, note: "url inválida") }
        await gate.enter()
        let result = await run(url)
        await gate.leave()
        return result
    }

    private static func run(_ url: URL) async -> LinkCheck {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url)
            request.httpMethod = method
            if method == "GET" { request.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if method == "HEAD", [403, 405, 501].contains(http.statusCode) { continue }
                return classify(http.statusCode)
            } catch let error as URLError {
                return classify(error)
            } catch {
                return LinkCheck(state: .unknown, note: "error")
            }
        }
        return LinkCheck(state: .unknown, note: "sin respuesta")
    }

    private static func classify(_ code: Int) -> LinkCheck {
        switch code {
        case 200..<400: return LinkCheck(state: .ok, note: "\(code)")
        case 404, 410: return LinkCheck(state: .broken, note: "\(code)")
        case 500..<600: return LinkCheck(state: .broken, note: "\(code)")
        case 401, 403: return LinkCheck(state: .unknown, note: "\(code) requiere acceso")
        default: return LinkCheck(state: .unknown, note: "\(code)")
        }
    }

    private static func classify(_ error: URLError) -> LinkCheck {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed: return LinkCheck(state: .broken, note: "dominio no existe")
        case .cannotConnectToHost: return LinkCheck(state: .broken, note: "no responde")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return LinkCheck(state: .broken, note: "certificado inválido")
        case .timedOut: return LinkCheck(state: .unknown, note: "sin respuesta")
        case .cancelled: return LinkCheck(state: .unknown, note: "cancelado")
        default: return LinkCheck(state: .unknown, note: "error de red")
        }
    }
}

// MARK: - De la página en localhost al código fuente

enum SourceLocator {
    /// Carpeta del proyecto que sirve `port`: cwd del proceso que escucha, subiendo hasta .git o package.json.
    static func projectRoot(port: Int) -> URL? {
        guard let pid = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"], in: nil, timeout: 4)?
            .split(separator: "\n").first,
              let out = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"], in: nil, timeout: 4),
              let line = out.split(separator: "\n").first(where: { $0.hasPrefix("n") }) else { return nil }
        let start = URL(fileURLWithPath: String(line.dropFirst()))
        var candidate = start
        for _ in 0..<5 {
            let fm = FileManager.default
            if fm.fileExists(atPath: candidate.appendingPathComponent(".git").path)
                || fm.fileExists(atPath: candidate.appendingPathComponent("package.json").path) { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return start
    }

    /// Hasta tres coincidencias "ruta:línea" del texto en el código del proyecto.
    static func hints(for term: String, in root: URL) -> [String] {
        guard term.count >= 3 else { return [] }
        var args = ["-rnF", "-m1", "--binary-files=without-match"]
        for dir in ["node_modules", ".git", ".next", "dist", "build", ".build", "Pods", ".venv", "coverage"] {
            args.append("--exclude-dir=\(dir)")
        }
        for ext in ["tsx", "jsx", "ts", "js", "vue", "svelte", "astro", "html", "php", "erb", "md", "mdx"] {
            args.append("--include=*.\(ext)")
        }
        args += ["-e", term, "."]
        guard let out = run("/usr/bin/grep", args, in: root, timeout: 6) else { return [] }
        return out.split(separator: "\n").prefix(3).compactMap { raw in
            var parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            var path = String(parts[0])
            if path.hasPrefix("./") { path.removeFirst(2) }
            parts[0] = Substring(path)
            return "\(path):\(parts[1])"
        }
    }

    private static func run(_ tool: String, _ args: [String], in directory: URL?, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Historial y comparación entre recorridos

struct CrawlSnapshot: Codable {
    struct Entry: Codable, Hashable {
        let key: String
        let text: String
        let url: String
        let problems: [String]
    }
    let date: Date
    let entries: [Entry]
}

struct CrawlDiff {
    let previousDate: Date
    let newLinks: [CrawlSnapshot.Entry]
    let goneLinks: [CrawlSnapshot.Entry]
    let newProblems: [CrawlSnapshot.Entry]
    let fixed: [CrawlSnapshot.Entry]
    var isEmpty: Bool { newLinks.isEmpty && goneLinks.isEmpty && newProblems.isEmpty && fixed.isEmpty }
}

enum CrawlHistory {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudePet/claudwler", isDirectory: true)
    }

    static func slug(_ site: String) -> String {
        String(site.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    }

    static func load(site: String) -> CrawlSnapshot? {
        let url = directory.appendingPathComponent("\(slug(site)).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CrawlSnapshot.self, from: data)
    }

    static func save(_ snapshot: CrawlSnapshot, site: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: directory.appendingPathComponent("\(slug(site)).json"), options: .atomic)
    }

    static func diff(previous: CrawlSnapshot, current: CrawlSnapshot) -> CrawlDiff {
        let before = Dictionary(previous.entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Dictionary(current.entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var newLinks: [CrawlSnapshot.Entry] = [], gone: [CrawlSnapshot.Entry] = []
        var newProblems: [CrawlSnapshot.Entry] = [], fixed: [CrawlSnapshot.Entry] = []
        for (key, entry) in now {
            guard let old = before[key] else { newLinks.append(entry); continue }
            if !Set(entry.problems).subtracting(old.problems).isEmpty { newProblems.append(entry) }
            if !Set(old.problems).subtracting(entry.problems).isEmpty { fixed.append(old) }
        }
        for (key, entry) in before where now[key] == nil {
            if entry.problems.isEmpty { gone.append(entry) } else { fixed.append(entry) }
        }
        let order: (CrawlSnapshot.Entry, CrawlSnapshot.Entry) -> Bool = { $0.key < $1.key }
        return CrawlDiff(previousDate: previous.date, newLinks: newLinks.sorted(by: order), goneLinks: gone.sorted(by: order),
                         newProblems: newProblems.sorted(by: order), fixed: fixed.sorted(by: order))
    }
}
