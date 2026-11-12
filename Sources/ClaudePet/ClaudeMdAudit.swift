import Foundation

enum TokenEstimate {
    /// Estimacion barata: unos 3,5 caracteres por token. Es una aproximacion, no el recuento real del modelo.
    static func tokens(characters: Int) -> Int { characters <= 0 ? 0 : Int((Double(characters) / 3.5).rounded(.up)) }
    static func tokens(_ text: String) -> Int { tokens(characters: text.count) }
}

/// Revision de un `CLAUDE.md`: Claude Code lo lee entero al empezar cada sesion, asi que cada token de mas se paga siempre.
struct ClaudeMdAudit: Equatable {
    enum Finding: Equatable {
        case missing
        case long(tokens: Int)
        case veryLong(tokens: Int)
        case agingSection(heading: String)       // seccion de estado o pendientes, que se queda vieja
        case staleDate(heading: String, date: String)
        case empty
    }

    static let longTokens = 2_000
    static let veryLongTokens = 4_000
    static let staleDays = 90

    let exists: Bool
    let tokens: Int
    let findings: [Finding]
    var isHealthy: Bool { findings.isEmpty }

    /// Palabras de encabezado que casi siempre describen algo con fecha de caducidad.
    private static let agingWords = ["pendiente", "todo", "wip", "en curso", "estado actual", "por hacer", "proximos", "próximos", "esta semana",
                                     "temporal", "hoy", "roadmap", "next steps", "in progress", "current status", "status", "changelog", "bugs conocidos", "known issues"]

    static func audit(text: String?, now: Date = Date()) -> ClaudeMdAudit {
        guard let text else { return ClaudeMdAudit(exists: false, tokens: 0, findings: [.missing]) }
        let tokens = TokenEstimate.tokens(text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ClaudeMdAudit(exists: true, tokens: 0, findings: [.empty]) }
        var findings: [Finding] = []
        if tokens >= veryLongTokens { findings.append(.veryLong(tokens: tokens)) } else if tokens >= longTokens { findings.append(.long(tokens: tokens)) }

        var heading: String?
        var aging = Set<String>()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("#") {
                heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                let folded = SettingsPage.fold(heading ?? "")
                if let h = heading, !h.isEmpty, agingWords.contains(where: { containsWord(folded, SettingsPage.fold($0)) }), aging.insert(h).inserted {
                    findings.append(.agingSection(heading: h))
                }
            }
            if let date = firstISODate(in: line), let when = parse(date), now.timeIntervalSince(when) > Double(staleDays) * 86_400 {
                let h = heading ?? ""
                if !findings.contains(.staleDate(heading: h, date: date)) { findings.append(.staleDate(heading: h, date: date)) }
            }
        }
        return ClaudeMdAudit(exists: true, tokens: tokens, findings: findings)
    }

    /// Lee `CLAUDE.md` de la carpeta (tope de 1 MB). Si no existe, `missing`.
    static func audit(folder: URL, now: Date = Date()) -> ClaudeMdAudit {
        let url = folder.appendingPathComponent("CLAUDE.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return audit(text: nil, now: now) }
        guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 1 << 20) else { return audit(text: "", now: now) }
        try? handle.close()
        return audit(text: String(decoding: data, as: UTF8.self), now: now)
    }

    private static func containsWord(_ folded: String, _ word: String) -> Bool {
        guard let range = folded.range(of: word) else { return false }
        let before = range.lowerBound == folded.startIndex || !folded[folded.index(before: range.lowerBound)].isLetter
        var tail = folded[range.upperBound...]
        if word != "todo", tail.hasPrefix("es") || tail.hasPrefix("s") { tail = tail.dropFirst(tail.hasPrefix("es") ? 2 : 1) }   // plural
        let after = tail.isEmpty || !tail.first!.isLetter
        return before && after
    }

    private static func firstISODate(in line: String) -> String? {
        let chars = Array(line.utf8)
        guard chars.count >= 10 else { return nil }
        for i in 0...(chars.count - 10) {
            let w = chars[i..<(i + 10)]
            let s = Array(w)
            guard s[4] == 45, s[7] == 45, [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ (48...57).contains(s[$0]) }), s[0] == 50 else { continue }
            return String(decoding: s, as: UTF8.self)
        }
        return nil
    }

    private static func parse(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)
    }
}

extension ClaudeMdAudit.Finding {
    /// Frase para la pagina de ajustes (se traduce con `L10nEN`).
    var message: String {
        switch self {
        case .missing: return L.t("no tiene CLAUDE.md: cada sesión empieza sin saber cómo se compila ni cómo se prueba", "no CLAUDE.md: every session starts without knowing how to build or test")
        case .empty: return L.t("CLAUDE.md está vacío", "CLAUDE.md is empty")
        case .long(let t): return L.t("CLAUDE.md pesa unos \(t) tokens en cada sesión: conviene recortarlo", "CLAUDE.md weighs about \(t) tokens in every session: worth trimming")
        case .veryLong(let t): return L.t("CLAUDE.md pesa unos \(t) tokens en cada sesión: es demasiado, deja solo lo imprescindible", "CLAUDE.md weighs about \(t) tokens in every session: too much, keep only the essentials")
        case .agingSection(let h): return L.t("la sección «\(h)» envejece rápido: mejor fuera del archivo", "the section \"\(h)\" ages fast: better kept out of the file")
        case .staleDate(_, let d): return L.t("menciona una fecha de hace más de \(ClaudeMdAudit.staleDays) días (\(d))", "mentions a date older than \(ClaudeMdAudit.staleDays) days (\(d))")
        }
    }
}
