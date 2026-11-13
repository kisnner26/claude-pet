import Foundation

/// Segunda pasada: reordena las candidatas de la primera con senales baratas.
/// Es un re-ranker HEURISTICO, no un cross-encoder: un cross-encoder lee consulta y nota juntas con un modelo y aqui no hay ninguno.
enum BrainRerank {
    // pesos de cada senal (suman sobre la puntuacion fusionada, ya normalizada a 0...1 respecto a la mejor candidata)
    static let wProximity = 0.35, wFresh = 0.20, wProject = 0.08, stalePenalty = 0.40

    /// Un "cuidado" o un "trato" valen mas que un "hecho": equivocarse ahi cuesta mas.
    static func kindWeight(_ k: BrainKind) -> Double {
        switch k {
        case .cuidado: return 0.25
        case .trato, .decision: return 0.15
        case .pendiente: return 0.12
        case .hecho: return 0.03
        }
    }

    /// Vida media en dias: un hecho envejece rapido, un cuidado o un trato casi no.
    static func halfLife(_ k: BrainKind) -> Double {
        switch k {
        case .hecho: return 45
        case .pendiente: return 30
        case .decision: return 240
        case .cuidado, .trato: return 365
        }
    }

    static func freshness(_ n: BrainNote, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(n.at) / 86_400)
        return pow(0.5, days / halfLife(n.kind))
    }

    /// 0...1: cuantos terminos distintos de la consulta aparecen y que tan juntos. Terminos pegados valen mas que dispersos.
    static func proximity(queryTerms: [String], text: String) -> Double {
        let q = Set(queryTerms)
        guard !q.isEmpty else { return 0 }
        let doc = BrainText.terms(text)
        var positions: [(Int, String)] = []
        for (i, t) in doc.enumerated() where q.contains(t) { positions.append((i, t)) }
        let present = Set(positions.map(\.1))
        guard !present.isEmpty else { return 0 }
        var best = Int.max
        for s in positions.indices {
            var seen = Set<String>()
            for e in s..<positions.count {
                seen.insert(positions[e].1)
                if seen.count == present.count { best = min(best, positions[e].0 - positions[s].0 + 1); break }
            }
        }
        let coverage = Double(present.count) / Double(q.count)
        return coverage * Double(present.count) / Double(max(best, present.count))
    }

    /// `fusion` ya viene normalizada (la mejor candidata vale 1); sin consulta vale 0 y manda el resto.
    static func score(note n: BrainNote, isGlobal: Bool, fusion: Double, queryTerms: [String], now: Date) -> Double {
        var s = fusion
        s += wProximity * proximity(queryTerms: queryTerms, text: n.text)
        s += wFresh * freshness(n, now: now)
        s += kindWeight(n.kind)
        if !isGlobal { s += wProject }
        if n.stale == true { s -= stalePenalty }
        return s
    }
}
