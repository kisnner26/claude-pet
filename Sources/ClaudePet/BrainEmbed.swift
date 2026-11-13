import Foundation
import NaturalLanguage

/// Vectores de palabras. Es un protocolo para poder probar sin el modelo del sistema y para el caso "no hay embeddings".
protocol BrainWordVectors {
    func vector(for word: String) -> [Double]?
    /// Palabras vecinas en el espacio de significado con su distancia (menor = mas cerca).
    func neighbors(of word: String, count: Int) -> [(word: String, distance: Double)]
}

extension BrainWordVectors {
    func neighbors(of word: String, count: Int) -> [(word: String, distance: Double)] { [] }
}

/// Embeddings de palabras de Apple (NaturalLanguage), fuera de linea. Si el idioma no esta en este equipo, `make` devuelve nil.
/// Se usan vectores de palabras y no de frases a proposito: el modelo de frases tarda unos 280 ms en cargarse y 5-12 ms por frase
/// (medido), demasiado para un hook que corre en cada mensaje; el de palabras carga en ~10 ms.
struct NLWordVectors: BrainWordVectors {
    let embedding: NLEmbedding
    let language: NLLanguage

    func vector(for word: String) -> [Double]? { embedding.vector(for: word) }
    func neighbors(of word: String, count: Int) -> [(word: String, distance: Double)] {
        embedding.neighbors(for: word, maximumCount: count).map { (word: $0.0, distance: $0.1) }
    }

    /// Elige espanol o ingles segun el texto de la consulta (espanol si no se puede decidir).
    static func make(for sample: String) -> NLWordVectors? {
        let rec = NLLanguageRecognizer()
        rec.languageConstraints = [.spanish, .english]
        rec.processString(sample)
        let first = rec.dominantLanguage ?? .spanish
        for l in [first, first == .spanish ? NLLanguage.english : .spanish] {
            if let e = NLEmbedding.wordEmbedding(for: l) { return NLWordVectors(embedding: e, language: l) }
        }
        return nil
    }
}

enum BrainSemantic {
    /// Umbral de coseno del vector medio de palabras. Medido: el coseno medio separa mal (pares relevantes 0.35-0.81, irrelevantes
    /// 0.37-0.63), asi que el umbral es alto a proposito y casi solo deja pasar parecidos fuertes; lo que aporta de verdad es `expand`.
    static let minCosine = 0.70
    /// Distancia maxima de un vecino para usarlo como sinonimo (medido: coche->vehiculo 0.75, servidor->ordenador 0.87, database->metadata 0.85).
    static let maxNeighborDistance = 0.90

    /// Expansion de la consulta: sinonimos y palabras cercanas de las palabras de la consulta (como terminos de busqueda).
    /// Es la parte util del modelo de palabras: "coche" encuentra una nota que dice "vehiculo" sin compartir ni una palabra.
    static func expand(query: String, vectors: BrainWordVectors?, perWord: Int = 2) -> [String] {
        guard let vectors else { return [] }
        var out: [String] = []
        for raw in query.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let w = String(raw)
            guard w.count >= 4, !BrainText.stopwords.contains(BrainText.fold(w)) else { continue }
            for n in vectors.neighbors(of: w, count: perWord + 2).filter({ $0.distance <= maxNeighborDistance && $0.word.lowercased() != w }).prefix(perWord) {
                out += BrainText.terms(n.word)
            }
        }
        return Array(Set(out).subtracting(BrainText.terms(query)))
    }

    /// Vector medio de las palabras con significado de un texto (las que el modelo conoce). nil si no conoce ninguna.
    static func embed(_ text: String, _ vectors: BrainWordVectors) -> [Double]? {
        var sum: [Double] = [], n = 0
        let lower = text.lowercased()
        for raw in lower.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let w = String(raw)
            if BrainText.stopwords.contains(BrainText.fold(w)) || w.count < 3 { continue }
            guard let v = vectors.vector(for: w) ?? vectors.vector(for: BrainText.fold(w)) else { continue }
            if sum.isEmpty { sum = [Double](repeating: 0, count: v.count) }
            guard v.count == sum.count else { continue }
            for i in v.indices { sum[i] += v[i] }
            n += 1
        }
        return n == 0 ? nil : sum
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na == 0 || nb == 0 ? 0 : dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Coseno de la consulta con cada documento; nil donde el modelo no conoce ninguna palabra. Con `vectors == nil`, todo nil.
    static func scores(query: String, docs: [String], vectors: BrainWordVectors?) -> [Double?] {
        guard let vectors, let q = embed(query, vectors) else { return docs.map { _ in nil } }
        return docs.map { d in embed(d, vectors).map { cosine(q, $0) } }
    }
}
