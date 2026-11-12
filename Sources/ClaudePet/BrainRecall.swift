import Foundation

/// Una nota candidata, con el dato de si viene del cerebro global.
struct RecallCandidate {
    let note: BrainNote
    let isGlobal: Bool
}

/// Una nota elegida. `childOffset` es donde empieza la frase que mejor coincidio (para no perder el hilo si hay que recortar).
struct RecallHit {
    let note: BrainNote
    let isGlobal: Bool
    let score: Double
    let childOffset: Int
}

/// Recuperacion en dos etapas, todo local y sin modelo de lenguaje:
/// 1. padre-hijo: cada nota (padre) se parte en frases (hijas); se busca sobre las hijas y se entrega el padre entero;
/// 2. las hijas se puntuan con BM25 y, si hay embeddings, por significado; se fusionan con RRF y quedan N candidatas;
/// 3. el re-ranker heuristico reordena los padres y solo pasan los K mejores.
enum BrainRecall {
    static let candidates = 30

    struct Output {
        var hits: [RecallHit] = []
        /// si la puntuacion semantica participo (false = solo BM25, p. ej. sin embeddings en este equipo)
        var usedSemantic = false
        var children = 0
    }

    /// Notas relevantes para `query`, mejores primero. Sin terminos utiles en la consulta no devuelve nada: no inventa relevancia.
    static func search(query: String, notes: [RecallCandidate], limit: Int, now: Date = Date(), vectors: BrainWordVectors?, candidates n: Int = BrainRecall.candidates, minCosine: Double = BrainSemantic.minCosine) -> Output {
        let live = notes.filter { $0.note.archived != true }
        let qTerms = BrainText.terms(query)
        var out = Output()
        guard !qTerms.isEmpty, !live.isEmpty, limit > 0 else { return out }

        // padre -> hijas
        var childText: [String] = [], childParent: [Int] = [], childOffset: [Int] = []
        for (i, c) in live.enumerated() {
            for s in BrainText.sentences(c.note.text) { childText.append(s.text); childParent.append(i); childOffset.append(s.offset) }
        }
        out.children = childText.count

        // etapa 1: lexical + semantica, fusionadas
        let bm25 = BM25Index(docs: childText.map(BrainText.terms))
        let lex = bm25.scores(qTerms)
        let lexRank = Array(lex.indices.filter { lex[$0] > 0 }.sorted { lex[$0] > lex[$1] }.prefix(n))
        var rankings = [lexRank]
        // semantica: (a) la consulta ampliada con vecinos de significado, puntuada con el mismo BM25;
        //            (b) coseno del vector medio de palabras, solo parecidos fuertes
        let expansion = BrainSemantic.expand(query: query, vectors: vectors)
        if !expansion.isEmpty {
            let ex = bm25.scores(expansion)
            let exRank = Array(ex.indices.filter { ex[$0] > 0 }.sorted { ex[$0] > ex[$1] }.prefix(n))
            if !exRank.isEmpty { rankings.append(exRank); out.usedSemantic = true }
        }
        let sem = BrainSemantic.scores(query: query, docs: childText, vectors: vectors)
        let semRank = Array(sem.indices.filter { (sem[$0] ?? 0) >= minCosine }.sorted { (sem[$0] ?? 0) > (sem[$1] ?? 0) }.prefix(n))
        if !semRank.isEmpty { rankings.append(semRank); out.usedSemantic = true }
        let fused = BrainFusion.rrf(rankings)
        guard !fused.isEmpty else { return out }

        // las hijas vuelven a su padre: manda la mejor hija
        var best: [Int: (score: Double, child: Int)] = [:]
        for (child, score) in fused {
            let p = childParent[child]
            if best[p] == nil || score > best[p]!.score || (score == best[p]!.score && child < best[p]!.child) { best[p] = (score, child) }
        }
        let stage1 = best.sorted { $0.value.score != $1.value.score ? $0.value.score > $1.value.score : $0.key < $1.key }.prefix(n)
        guard let top = stage1.first?.value.score, top > 0 else { return out }

        // etapa 2: re-ranking heuristico solo de las candidatas
        let ranked = stage1.map { (p, b) -> RecallHit in
            let c = live[p]
            let s = BrainRerank.score(note: c.note, isGlobal: c.isGlobal, fusion: b.score / top, queryTerms: qTerms, now: now)
            return RecallHit(note: c.note, isGlobal: c.isGlobal, score: s, childOffset: childOffset[b.child])
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.note.at != $1.note.at { return $0.note.at > $1.note.at }
            return $0.note.id.uuidString < $1.note.id.uuidString
        }
        out.hits = Array(ranked.prefix(limit))
        return out
    }

    /// Sin consulta (al abrir la sesion): solo cuentan el tipo, la frescura, el proyecto y si esta marcada obsoleta.
    static func prioritize(_ notes: [RecallCandidate], now: Date = Date()) -> [RecallHit] {
        notes.filter { $0.note.archived != true }.map {
            RecallHit(note: $0.note, isGlobal: $0.isGlobal, score: BrainRerank.score(note: $0.note, isGlobal: $0.isGlobal, fusion: 0, queryTerms: [], now: now), childOffset: 0)
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.note.at > $1.note.at
        }
    }
}
