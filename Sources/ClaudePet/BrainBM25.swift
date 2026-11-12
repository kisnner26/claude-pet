import Foundation

/// BM25 clasico (Okapi) sobre un conjunto pequeno de documentos ya partidos en terminos. Sin dependencias.
struct BM25Index {
    let docs: [[String]]
    private let freqs: [[String: Int]]
    private let df: [String: Int]
    private let avgLen: Double
    let k1: Double, b: Double

    init(docs: [[String]], k1: Double = 1.2, b: Double = 0.75) {
        self.docs = docs; self.k1 = k1; self.b = b
        var f: [[String: Int]] = [], d: [String: Int] = [:]
        for doc in docs {
            var m: [String: Int] = [:]
            for t in doc { m[t, default: 0] += 1 }
            for t in m.keys { d[t, default: 0] += 1 }
            f.append(m)
        }
        freqs = f; df = d
        avgLen = docs.isEmpty ? 0 : Double(docs.reduce(0) { $0 + $1.count }) / Double(docs.count)
    }

    /// idf con el suavizado "+1" de Lucene: nunca negativo.
    func idf(_ term: String) -> Double {
        let n = Double(docs.count), d = Double(df[term] ?? 0)
        return log(1 + (n - d + 0.5) / (d + 0.5))
    }

    /// Una puntuacion por documento (0 si no comparte ningun termino con la consulta).
    func scores(_ query: [String]) -> [Double] {
        let q = Array(Set(query))
        return docs.indices.map { i in
            let len = Double(docs[i].count)
            var s = 0.0
            for t in q {
                guard let tf = freqs[i][t] else { continue }
                let f = Double(tf)
                s += idf(t) * f * (k1 + 1) / (f + k1 * (1 - b + b * (avgLen > 0 ? len / avgLen : 1)))
            }
            return s
        }
    }
}
