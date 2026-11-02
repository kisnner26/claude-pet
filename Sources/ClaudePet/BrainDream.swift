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
        return Set(words.filter { $0.count >= 3 && !stopwords.contains($0) })
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
    }

    /// `exists` recibe cada ruta mencionada y dice si sigue estando (relativa al proyecto o absoluta).
    static func consolidate(_ input: [BrainNote], now: Date, exists: (String) -> Bool) -> Outcome {
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
        return Outcome(notes: kept, merged: merged, stale: stale, lingering: lingering)
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
    var seen = false

    var isQuiet: Bool { merged == 0 && stale == 0 && lingering == 0 }

    var lines: [String] {
        var out: [String] = []
        if merged > 0 { out.append("uní \(merged) \(merged == 1 ? "nota casi igual a otra" : "notas casi iguales a otras")") }
        if stale > 0 { out.append("\(stale) \(stale == 1 ? "nota habla" : "notas hablan") de archivos que ya no existen") }
        if lingering > 0 { out.append("\(lingering) \(lingering == 1 ? "pendiente lleva" : "pendientes llevan") más de \(Int(BrainDream.staleAfterPendingDays)) días abiertos") }
        if out.isEmpty { out.append("todo en orden: nada que unir ni que revisar") }
        return out
    }

    /// Una sola frase para la cabecera de la pagina del cerebro.
    var headline: String { isQuiet ? "mientras dormías: todo en orden" : "mientras dormías: " + lines.joined(separator: " · ") }
}
