import Foundation

/// Formato compacto y estructurado de lo que se inyecta al agente: una etiqueta que envuelve, una linea por nota con sus
/// atributos (tipo, edad, autor, ambito) y nada de prosa de relleno. Y el presupuesto de tokens estimado.
enum BrainFormat {
    struct Block: Equatable {
        var text: String
        var tokens: Int
        var shown: Int
        var truncated: Bool
    }

    static func age(_ date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 3600 { return "ahora" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func open(_ h: RecallHit, now: Date) -> String {
        let n = h.note
        var a = "<nota tipo=\"\(n.kind.label)\" edad=\"\(age(n.at, now: now))\" autor=\"\(n.agent)\""
        if h.isGlobal { a += " ambito=\"global\"" }
        if n.stale == true { a += " obsoleta=\"posible\"" }
        if let s = n.sources, !s.isEmpty { a += " resume=\"\(s.count)\"" }
        return a + ">"
    }

    /// Una linea por nota. `maxChars` recorta el texto (dejando la frase que coincidio a la vista) si no cabe.
    static func line(_ h: RecallHit, now: Date, maxChars: Int? = nil) -> String {
        var body = escape(h.note.text)
        if let maxChars, body.count > maxChars {
            let chars = Array(h.note.text)
            let from = min(h.childOffset, max(0, chars.count - 1))
            var piece = String(chars[from...])
            if piece.count > maxChars { piece = String(piece.prefix(max(1, maxChars - 1))) + "…" }
            body = escape((from > 0 ? "…" : "") + piece)
        }
        return open(h, now: now) + body + "</nota>"
    }

    /// Mete notas en orden hasta agotar `budget` tokens estimados (cabecera y cierre incluidos). Nunca devuelve mas de `max`.
    /// Si ni la primera cabe entera, se recorta; si ni recortada cabe, no se inyecta nada.
    static func block(project: String, hits: [RecallHit], total: Int, now: Date, budget: Int, max: Int, notice: String? = nil) -> Block {
        let name = BrainStore.clean(project: project)
        var head = "<notas-del-proyecto proyecto=\"\(name)\" mostradas=\"%d\" de=\"\(total)\""
        if let notice { head += " aviso=\"\(notice)\"" }
        head += ">"
        let foot = "</notas-del-proyecto>"
        func header(_ shown: Int) -> String { head.replacingOccurrences(of: "%d", with: "\(shown)") }
        let fixed = BrainText.estimateTokens(header(99) + "\n" + foot)
        var lines: [String] = [], used = fixed, truncated = false
        for h in hits.prefix(max) {
            var l = line(h, now: now)
            var cost = BrainText.estimateTokens(l + "\n")
            if used + cost > budget {
                guard lines.isEmpty else { break }
                // la primera nota sola no cabe: se recorta a lo que quede
                let room = Int(Double(budget - used) * 3.5) - open(h, now: now).count - "</nota>\n".count
                guard room >= 40 else { break }
                l = line(h, now: now, maxChars: room); cost = BrainText.estimateTokens(l + "\n"); truncated = true
                if used + cost > budget { break }
            }
            lines.append(l); used += cost
        }
        if lines.isEmpty { return Block(text: "", tokens: 0, shown: 0, truncated: false) }
        let text = header(lines.count) + "\n" + lines.joined(separator: "\n") + "\n" + foot + "\n"
        return Block(text: text, tokens: BrainText.estimateTokens(text), shown: lines.count, truncated: truncated)
    }
}
