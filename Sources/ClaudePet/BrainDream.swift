import Foundation

/// El cerebro "suena": de noche, o tras un buen rato sin usar la Mac, repasa las notas como lo hace el sueno con los recuerdos.
/// Une las que dicen casi lo mismo, marca las que hablan de archivos que ya no existen y senala los pendientes que llevan dias abiertos.
/// Nunca borra nada que no sea un duplicado: lo dudoso se marca para que lo decidas tu por la manana.
enum BrainDream {
    static let staleAfterPendingDays = 14.0
    static let fileExtensions = ["swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "md", "json", "yml", "yaml", "toml", "sh", "html", "css", "plist"]

    // MARK: parecido entre notas

    private static let stopwords: Set<String> = ["que", "los", "las", "una", "uno", "por", "con", "para", "del", "esta", "este", "como", "pero", "sin", "muy", "mas", "the", "and", "for", "with", "hay", "son", "ser", "fue", "cuando", "donde", "porque", "todo", "toda"]

    static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let words = folded.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        // los numeros cuentan aunque sean cortos: "version 2" y "version 3" no son la misma nota
        return Set(words.filter { ($0.count >= 3 || $0.contains(where: \.isNumber)) && !stopwords.contains($0) })
    }

    /// Dos notas son la misma si comparten casi todas sus palabras, o si una esta entera dentro de la otra y no es trivial.
    static func areDuplicates(_ a: String, _ b: String) -> Bool {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let inter = Double(ta.intersection(tb).count), union = Double(ta.union(tb).count)
        if inter / union >= 0.75 { return true }
        return Double(min(ta.count, tb.count)) >= 4 && inter / Double(min(ta.count, tb.count)) >= 0.95
    }

    // MARK: archivos que una nota menciona

    /// Rutas o nombres de archivo que aparecen en el texto (`src/App.swift`, `Brain.swift`...).
    static func mentionedPaths(_ text: String) -> [String] {
        let trim = CharacterSet(charactersIn: "`'\"()[]{}<>,;:!?¿¡")
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            var w = raw.trimmingCharacters(in: trim)
            while w.hasSuffix(".") { w.removeLast() }
            if w.isEmpty || w.lowercased().hasPrefix("http") || w.contains("@") { continue }
            let ext = (w as NSString).pathExtension.lowercased()
            let looksLikeFile = fileExtensions.contains(ext) && w.count > ext.count + 1
            let looksLikePath = w.contains("/") && w.count > 3 && w.contains { $0.isLetter }
            if (looksLikeFile || looksLikePath), !out.contains(w) { out.append(w) }
        }
        return out
    }

    // MARK: el repaso

    struct Outcome: Equatable {
        var notes: [BrainNote]
        var merged = 0
        var stale: [BrainNote] = []
        var lingering: [BrainNote] = []
        /// notas antiguas que se condensaron en un resumen (las originales quedan archivadas, no borradas)
        var condensed = 0
    }

    /// `exists` recibe cada ruta mencionada y dice si sigue estando (relativa al proyecto o absoluta).
    /// Con `condense` las notas antiguas de un mismo tema se resumen (memoria episodica); sin el, el repaso es el de siempre.
    static func consolidate(_ all: [BrainNote], now: Date, condense: Bool = false, exists: (String) -> Bool) -> Outcome {
        let archived = all.filter { $0.archived == true }
        let input = all.filter { $0.archived != true }
        var kept: [BrainNote] = []
        var merged = 0
        for note in input.sorted(by: { $0.at > $1.at }) {
            if let i = kept.firstIndex(where: { $0.kind == note.kind && areDuplicates($0.text, note.text) }) {
                // la mas nueva manda, salvo que la vieja la escribieras tu: tus palabras no se pierden
                if note.agent == "tu", kept[i].agent != "tu" {
                    let when = kept[i].at
                    kept[i] = BrainNote(id: note.id, at: when, agent: note.agent, kind: note.kind, text: note.text)
                }
                merged += 1
                continue
            }
            kept.append(note)
        }
        var stale: [BrainNote] = [], lingering: [BrainNote] = []
        for i in kept.indices {
            let paths = mentionedPaths(kept[i].text)
            kept[i].stale = !paths.isEmpty && paths.allSatisfy { !exists($0) } ? true : nil
            if kept[i].stale == true { stale.append(kept[i]) }
            if kept[i].kind == .pendiente, now.timeIntervalSince(kept[i].at) > staleAfterPendingDays * 86_400 { lingering.append(kept[i]) }
        }
        var condensed = 0
        var archivedOut = archived
        if condense {
            let r = condenseOld(kept, now: now)
            kept = r.live; archivedOut += r.archived; condensed = r.groups
        }
        if archivedOut.count > maxArchived { archivedOut = Array(archivedOut.sorted { $0.at > $1.at }.prefix(maxArchived)) }
        let everything = archivedOut.isEmpty ? kept : (kept + archivedOut).sorted { $0.at > $1.at }
        return Outcome(notes: everything, merged: merged, stale: stale, lingering: lingering, condensed: condensed)
    }
}

// MARK: memoria episodica

extension BrainDream {
    static let condenseAfterDays = 30.0, condenseMinGroup = 3, condenseSimilarity = 0.25
    /// tope de notas archivadas por proyecto: el archivo se lee con un limite de tamano, asi que no puede crecer sin fin
    static let maxArchived = 300

    /// Frases del texto que mas terminos del tema comparten, hasta `maxChars`, en su orden original. Extractivo: no genera texto.
    static func extractiveSummary(_ notes: [BrainNote], maxChars: Int = BrainStore.maxText) -> String {
        let sets = notes.map { tokens($0.text) }
        var count: [String: Int] = [:]
        for s in sets { for t in s { count[t, default: 0] += 1 } }
        let theme = Set(count.filter { $0.value >= 2 }.keys)
        guard !theme.isEmpty else { return "" }
        struct Sent { let text: String; let order: Int; let score: Int }
        var all: [Sent] = [], order = 0
        for n in notes.sorted(by: { $0.at < $1.at }) {
            for s in BrainText.sentences(n.text) {
                all.append(Sent(text: s.text, order: order, score: tokens(s.text).intersection(theme).count)); order += 1
            }
        }
        var chosen: [Sent] = [], used = 0
        for s in all.sorted(by: { $0.score != $1.score ? $0.score > $1.score : $0.order > $1.order }) where s.score > 0 {
            if chosen.contains(where: { areDuplicates($0.text, s.text) }) { continue }
            let add = s.text.count + (chosen.isEmpty ? 0 : 1)
            if used + add > maxChars { continue }
            chosen.append(s); used += add
        }
        return chosen.sorted { $0.order < $1.order }.map(\.text).joined(separator: " ")
    }

    /// Junta las notas viejas (hechos y decisiones de mas de 30 dias) que hablan de lo mismo en una nota-resumen.
    /// Las originales no se borran: pasan a `archived` y el resumen guarda sus ids en `sources`.
    /// Los cuidados, los tratos y los pendientes no se tocan: son reglas o trabajo vivo.
    static func condenseOld(_ notes: [BrainNote], now: Date) -> (live: [BrainNote], archived: [BrainNote], groups: Int) {
        let old = notes.filter { ($0.kind == .hecho || $0.kind == .decision) && $0.sources == nil && now.timeIntervalSince($0.at) > condenseAfterDays * 86_400 }
        var clusters: [[BrainNote]] = []
        for n in old.sorted(by: { $0.at < $1.at }) {
            let t = tokens(n.text)
            guard !t.isEmpty else { continue }
            func sim(_ a: Set<String>, _ b: Set<String>) -> Double { Double(a.intersection(b).count) / Double(max(1, a.union(b).count)) }
            if let i = clusters.firstIndex(where: { c in c[0].kind == n.kind && c.contains { sim(tokens($0.text), t) >= condenseSimilarity } }) { clusters[i].append(n) }
            else { clusters.append([n]) }
        }
        var live = notes, archived: [BrainNote] = [], groups = 0
        for c in clusters where c.count >= condenseMinGroup {
            let text = extractiveSummary(c)
            guard !text.isEmpty, !BrainStore.looksSecret(text) else { continue }
            let ids = Set(c.map(\.id))
            let agent = c.contains { $0.agent == "tu" } ? "tu" : (Dictionary(grouping: c, by: \.agent).max { $0.value.count < $1.value.count }?.key ?? "claude")
            var summary = BrainNote(id: UUID(), at: c.map(\.at).max() ?? now, agent: agent, kind: c[0].kind, text: text)
            summary.sources = c.sorted { $0.at < $1.at }.map(\.short)
            live.removeAll { ids.contains($0.id) }
            live.append(summary)
            archived += c.map { var a = $0; a.archived = true; return a }
            groups += 1
        }
        live.sort { $0.at > $1.at }
        return (live, archived, groups)
    }

}

extension BrainDream {
    /// Repasa todos los proyectos con notas y suma el resultado. Sin carpeta conocida para un proyecto no se juzga si sus archivos existen.
    static func run(store: BrainStore = .shared, perimeterRoots: [String], now: Date = Date(), condense: Bool = BrainSettings.load().smartRecall) -> DreamReport {
        var r = DreamReport(at: now)
        for project in store.projects() {
            let root = DreamRoots.root(for: project.name, perimeterRoots: perimeterRoots)
            let index = root.map { ProjectFileIndex.build(root: $0) }
            let outcome = store.dream(project: project.name, now: now, condense: condense, exists: { index?.exists($0) ?? true })
            r.projects += 1; r.merged += outcome.merged; r.stale += outcome.stale.count; r.lingering += outcome.lingering.count
            r.notesAfter += outcome.notes.filter { $0.archived != true }.count; r.condensed += outcome.condensed
        }
        return r
    }
}

/// Lo que se cuenta por la manana.
struct DreamReport: Codable, Equatable {
    var at: Date
    var projects = 0
    var merged = 0
    var stale = 0
    var lingering = 0
    var notesAfter = 0
    var condensed = 0
    var seen = false

    init(at: Date) { self.at = at }
    /// Los partes guardados antes de existir `condensed` se siguen leyendo.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Key.self)
        at = try c.decode(Date.self, forKey: .at)
        projects = try c.decodeIfPresent(Int.self, forKey: .projects) ?? 0
        merged = try c.decodeIfPresent(Int.self, forKey: .merged) ?? 0
        stale = try c.decodeIfPresent(Int.self, forKey: .stale) ?? 0
        lingering = try c.decodeIfPresent(Int.self, forKey: .lingering) ?? 0
        notesAfter = try c.decodeIfPresent(Int.self, forKey: .notesAfter) ?? 0
        condensed = try c.decodeIfPresent(Int.self, forKey: .condensed) ?? 0
        seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? false
    }
    enum Key: String, CodingKey { case at, projects, merged, stale, lingering, notesAfter, condensed, seen }

    var isQuiet: Bool { merged == 0 && stale == 0 && lingering == 0 && condensed == 0 }

    var lines: [String] {
        var out: [String] = []
        if merged > 0 { out.append("uní \(merged) \(merged == 1 ? "nota casi igual a otra" : "notas casi iguales a otras")") }
        if stale > 0 { out.append("\(stale) \(stale == 1 ? "nota habla" : "notas hablan") de archivos que ya no existen") }
        if lingering > 0 { out.append("\(lingering) \(lingering == 1 ? "pendiente lleva" : "pendientes llevan") más de \(Int(BrainDream.staleAfterPendingDays)) días abiertos") }
        if condensed > 0 { out.append("condensé \(condensed) \(condensed == 1 ? "tema antiguo" : "temas antiguos") en un resumen (las originales quedan archivadas)") }
        if out.isEmpty { out.append("todo en orden: nada que unir ni que revisar") }
        return out
    }

    /// Una sola frase para la cabecera de la pagina del cerebro.
    var headline: String { isQuiet ? "mientras dormías: todo en orden" : "mientras dormías: " + lines.joined(separator: " · ") }
}
