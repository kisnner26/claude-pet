import Foundation

/// Reciprocal rank fusion: une varias listas ordenadas (la lexical y la semantica) sin tener que comparar sus puntuaciones,
/// que no estan en la misma escala. Cada elemento suma 1 / (k + posicion) por cada lista donde aparece.
enum BrainFusion {
    static let k = 60.0

    /// `rankings` son listas de ids ordenadas de mejor a peor. Devuelve id -> puntuacion fusionada.
    static func rrf(_ rankings: [[Int]], k: Double = BrainFusion.k) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for list in rankings {
            for (pos, id) in list.enumerated() { out[id, default: 0] += 1 / (k + Double(pos) + 1) }
        }
        return out
    }
}
