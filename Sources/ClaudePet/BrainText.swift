import Foundation

/// Texto para la busqueda del cerebro: normaliza (tildes, mayusculas), parte en terminos y en frases.
/// Todo es local y sin modelos: nada de aqui sale del proceso.
enum BrainText {
    static let stopwords: Set<String> = [
        // espanol
        "que", "los", "las", "una", "uno", "unos", "unas", "por", "con", "para", "del", "esta", "este", "esto", "estos", "estas", "como", "pero", "sin", "muy", "mas", "hay", "son", "ser", "fue", "era", "cuando", "donde", "porque", "todo", "toda", "todos", "todas", "sus", "les", "nos", "mis", "tus", "mio", "tuyo", "ese", "esa", "eso", "ahora", "tambien", "solo", "sobre", "entre", "hasta", "desde", "segun", "puede", "pueden", "hacer", "quiero", "necesito", "favor", "gracias", "hola", "vale", "dale", "bien", "ya", "aqui", "alli", "tiene", "tienen", "esta", "estan", "estoy", "estamos", "cual", "cuales", "algo", "nada", "otro", "otra", "otros", "otras", "asi", "si", "no", "el", "la", "lo", "le", "se", "me", "te", "mi", "tu", "su", "un", "al", "en", "es", "de", "y", "o", "a", "e", "u",
        // ingles
        "the", "and", "for", "with", "this", "that", "these", "those", "from", "have", "has", "had", "are", "was", "were", "been", "being", "can", "could", "should", "would", "will", "shall", "may", "might", "must", "not", "but", "you", "your", "our", "its", "their", "them", "they", "there", "here", "what", "when", "where", "which", "who", "how", "why", "any", "all", "some", "into", "onto", "over", "just", "also", "than", "then", "too", "very", "please", "thanks", "thank", "hello", "okay", "yes", "need", "want", "does", "did", "doing", "make", "get", "got", "let", "out", "off", "about", "after", "before", "again", "one", "two", "use", "using", "used", "is", "it", "in", "on", "of", "to", "an", "as", "at", "by", "be", "do", "we", "he", "she", "if", "or", "so", "up"
    ]

    /// minusculas y sin tildes: "Decisión" == "decision"
    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() }

    /// Quita el plural mas comun (-es, -s) para que "hooks"/"hook" y "notas"/"nota" coincidan. Deliberadamente simple.
    static func stem(_ w: String) -> String {
        guard w.count > 3, w.allSatisfy({ $0.isLetter }) else { return w }
        if w.count > 5, w.hasSuffix("es") { return String(w.dropLast(2)) }
        if w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    /// Terminos de busqueda en orden (con repeticiones): sin palabras vacias, con numeros aunque sean cortos.
    static func terms(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).compactMap { raw in
            let w = String(raw)
            guard !stopwords.contains(w) else { return nil }
            guard w.count >= 3 || w.contains(where: \.isNumber) else { return nil }
            return stem(w)
        }
    }

    /// Frases de un texto con el desplazamiento (en caracteres) donde empiezan. No corta en "Brain.swift" ni en "v2.1".
    static func sentences(_ text: String) -> [(text: String, offset: Int)] {
        let chars = Array(text)
        var out: [(String, Int)] = []
        var start = 0
        func flush(_ end: Int) {
            var s = start
            while s < end, chars[s].isWhitespace { s += 1 }
            var e = end
            while e > s, chars[e - 1].isWhitespace { e -= 1 }
            if e > s { out.append((String(chars[s..<e]), s)) }
        }
        for i in chars.indices {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let breaks = c == "\n" || ((c == "." || c == "!" || c == "?" || c == ";") && (next == nil || next!.isWhitespace))
            if breaks { flush(i + 1); start = i + 1 }
        }
        flush(chars.count)
        return out.isEmpty ? [(text, 0)] : out
    }

    /// Estimacion barata de tokens: unos 3,5 caracteres por token. Sobrestima un poco a proposito.
    static func estimateTokens(_ s: String) -> Int { Int((Double(s.count) / 3.5).rounded(.up)) }
}
