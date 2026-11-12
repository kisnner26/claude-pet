import Foundation

enum AdviceKind: String, CaseIterable {
    case rotateContext, longSession, vaguePrompt, heavyFile, lowCache
}

struct Advice: Equatable, Identifiable {
    let kind: AdviceKind
    let message: String
    /// Si es verdadero, la pagina ofrece llevarse las notas a una sesion nueva con `SessionCapsule`.
    let offersCapsule: Bool
    var id: AdviceKind { kind }
}

/// Lo que se sabe en este momento. Todo es opcional: sin dato, esa regla calla.
struct AdviceInput: Equatable {
    var contextRemainingFraction: Double?     // 0...1, de `ContextReading`
    var sessionAge: TimeInterval?
    var cacheHitRate: Double?
    var promptTokensMeasured = 0              // tamano de la muestra de la tasa de cache
    var promptWordCount: Int?                 // del ultimo prompt; el texto no se guarda
    var promptIsGeneric = false
    var lastFileExtension: String?            // del ultimo archivo leido; el hook solo manda el nombre
}

/// Reducir un prompt a su forma: cuantas palabras tiene y si es una peticion sin objeto. El texto se descarta al instante.
enum PromptShape {
    private static let generic = ["arregla todo", "mejora el codigo", "mejora todo", "revisa todo", "hazlo mejor", "optimiza todo", "haz que funcione",
                                  "arreglalo", "mejoralo", "fix it", "fix everything", "make it better", "improve the code", "improve everything", "review everything",
                                  "clean it up", "refactor everything", "refactoriza todo"]
    static func analyze(_ text: String) -> (words: Int, generic: Bool) {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let folded = SettingsPage.fold(text)
        let normalized = folded.filter { $0.isLetter || $0.isNumber || $0 == " " }
        let isGeneric = words <= 6 && generic.contains { normalized.contains($0) }
        return (words, isGeneric)
    }
}

enum SavingsAdvisor {
    static let rotateAt = 0.30                         // contexto restante
    static let longSessionHours = 3.0
    static let lowCacheRate = 0.5
    static let minCacheSample = 20_000
    static let heavyExtensions: Set<String> = ["pdf", "docx", "doc", "pptx", "ppt", "xlsx", "xls", "epub", "rtf"]

    /// Todos los consejos vigentes, del mas util al menos. La pagina de ajustes los lista todos.
    static func current(_ i: AdviceInput) -> [Advice] {
        var out: [Advice] = []
        if let remaining = i.contextRemainingFraction, remaining <= rotateAt {
            let used = Int(((1 - remaining) * 100).rounded())
            out.append(Advice(kind: .rotateContext, message: L.t("el contexto va por el \(used) %: abre una sesión nueva y llévate las notas para no arrastrar todo",
                                                                "context is at \(used)%: open a new session and take the notes along instead of dragging everything"), offersCapsule: true))
        }
        if let ext = i.lastFileExtension?.lowercased(), heavyExtensions.contains(ext) {
            out.append(Advice(kind: .heavyFile, message: L.t("leíste un .\(ext): el Markdown o el texto plano del mismo contenido gasta bastante menos",
                                                            "you read a .\(ext): Markdown or plain text of the same content costs far fewer tokens"), offersCapsule: false))
        }
        if i.promptIsGeneric {
            out.append(Advice(kind: .vaguePrompt, message: L.t("el último prompt era muy general: nombrar archivo y objetivo evita que explore de más",
                                                              "the last prompt was very general: naming the file and the goal keeps it from exploring too much"), offersCapsule: false))
        }
        if let rate = i.cacheHitRate, i.promptTokensMeasured >= minCacheSample, rate < lowCacheRate {
            out.append(Advice(kind: .lowCache, message: L.t("solo el \(Int((rate * 100).rounded())) % de la entrada sale de la caché: pausas largas entre mensajes o cambiar el contexto la invalidan",
                                                            "only \(Int((rate * 100).rounded()))% of the input comes from the cache: long pauses between messages or changing the context invalidate it"), offersCapsule: false))
        }
        if let age = i.sessionAge, age >= longSessionHours * 3600, !out.contains(where: { $0.kind == .rotateContext }) {
            out.append(Advice(kind: .longSession, message: L.t("la sesión lleva más de \(Int(age / 3600)) h: una nueva con un resumen suele salir más barata que seguir arrastrando el historial",
                                                              "this session is over \(Int(age / 3600)) h old: a fresh one with a summary is usually cheaper than carrying the whole history"), offersCapsule: true))
        }
        return out
    }

    /// Enfriamiento: nunca dos consejos seguidos, ni el mismo antes de media hora. Quien lo usa guarda esto en memoria, no en disco.
    struct Throttle: Equatable {
        var lastByKind: [AdviceKind: Date] = [:]
        var lastAny: Date?
        var perKind: TimeInterval = 30 * 60
        var anyGap: TimeInterval = 5 * 60
    }

    /// Como mucho un consejo, y solo si toca. Si lo devuelve, queda anotado en el `Throttle`.
    static func next(_ input: AdviceInput, throttle: inout Throttle, now: Date = Date()) -> Advice? {
        if let any = throttle.lastAny, now.timeIntervalSince(any) < throttle.anyGap { return nil }
        for advice in current(input) {
            if let last = throttle.lastByKind[advice.kind], now.timeIntervalSince(last) < throttle.perKind { continue }
            throttle.lastByKind[advice.kind] = now
            throttle.lastAny = now
            return advice
        }
        return nil
    }
}
