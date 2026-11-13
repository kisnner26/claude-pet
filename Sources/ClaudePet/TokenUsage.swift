import Foundation

/// Contadores de uso de un mensaje (o la suma de varios). Solo numeros: nunca contenido.
struct TokenUsage: Equatable {
    var input = 0          // tokens de entrada nuevos (sin cache)
    var cacheRead = 0      // tokens leidos de la cache
    var cacheCreate = 0    // tokens escritos en la cache
    var output = 0         // tokens de salida
    var messages = 0

    var total: Int { input + cacheRead + cacheCreate + output }
    /// Todo lo que se mando como entrada, venga de donde venga.
    var promptTotal: Int { input + cacheRead + cacheCreate }

    /// Aciertos de cache: de lo que se mando como entrada, que parte se leyo de la cache. nil si no hay entrada.
    var cacheHitRate: Double? {
        let p = promptTotal
        guard p > 0 else { return nil }
        return Double(cacheRead) / Double(p)
    }
    var cacheHitPercent: Int? { cacheHitRate.map { Int(($0 * 100).rounded()) } }

    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, cacheRead: a.cacheRead + b.cacheRead, cacheCreate: a.cacheCreate + b.cacheCreate,
                   output: a.output + b.output, messages: a.messages + b.messages)
    }
    static func += (a: inout TokenUsage, b: TokenUsage) { a = a + b }
}

/// Lee el bloque `usage` de una linea de transcript. No conserva nada mas que los cuatro contadores y el id para no contar dos veces.
enum TokenUsageParser {
    struct Row: Equatable {
        let id: String?
        let usage: TokenUsage
        let cwdName: String?   // solo el ultimo componente de la carpeta
        var workspace: String? = nil   // la carpeta completa: solo en memoria, para auditar su CLAUDE.md; nunca se registra
    }

    static func parse(_ row: [String: Any]) -> Row? {
        guard let message = row["message"] as? [String: Any], let usage = message["usage"] as? [String: Any] else { return nil }
        let u = TokenUsage(input: count(usage["input_tokens"]), cacheRead: count(usage["cache_read_input_tokens"]),
                           cacheCreate: count(usage["cache_creation_input_tokens"]), output: count(usage["output_tokens"]), messages: 1)
        guard u.total > 0 else { return nil }
        let cwd = (row["cwd"] as? String).flatMap { $0.split(separator: "/").last.map(String.init) }
        return Row(id: message["id"] as? String, usage: u, cwdName: cwd, workspace: (row["cwd"] as? String).flatMap { $0.hasPrefix("/") ? $0 : nil })
    }

    /// Un mensaje de Claude se escribe en varias lineas (una por bloque de contenido) con el mismo `id` y el mismo uso:
    /// se cuenta una vez. Si el uso crece entre lineas (la salida se va completando), vale el mayor.
    struct Accumulator {
        private var perID: [String: TokenUsage] = [:]
        private var loose = TokenUsage()
        private(set) var project: String?
        private(set) var workspace: String?
        var maxTrackedIDs = 200_000

        mutating func add(_ row: Row) {
            if let name = row.cwdName { project = name }
            if let path = row.workspace { workspace = path }
            guard let id = row.id else { loose += row.usage; return }
            if var old = perID[id] {
                old.input = max(old.input, row.usage.input); old.cacheRead = max(old.cacheRead, row.usage.cacheRead)
                old.cacheCreate = max(old.cacheCreate, row.usage.cacheCreate); old.output = max(old.output, row.usage.output)
                perID[id] = old
            } else if perID.count < maxTrackedIDs { perID[id] = row.usage }
            else { loose += row.usage }
        }
        var usage: TokenUsage { perID.values.reduce(loose, +) }
    }

    private static func count(_ v: Any?) -> Int {
        if let n = v as? NSNumber { return max(0, n.intValue) }
        return 0
    }
}
