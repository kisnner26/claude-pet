import Foundation

struct PersonalityTrait: Equatable, Identifiable {
    let key: String
    let label: String          // nombre del eje
    let adjective: String      // lo que significa tenerlo alto
    let value: Double          // 0...1
    let note: String
    var id: String { key }
}

struct PersonalityProfile: Equatable {
    let agent: String
    let events: Int
    let activeDays: Int
    let stage: String
    let traits: [PersonalityTrait]
    let summary: String
    var formed: Bool { events >= 10 }
}

/// Personalidad de cada agente: sale solo de lo vivido con quien lo usa (el registro local y sus notas), nunca de datos inventados.
/// Los rasgos se mueven con la relacion: un agente nuevo no tiene carácter y lo va ganando con los dias.
enum Personality {
    static let window: TimeInterval = 14 * 86_400
    static let stages: [(min: Int, name: String)] = [(0, "recién conocidos"), (30, "se van conociendo"), (200, "compañeros"), (800, "cómplices")]

    /// Los recuerdos antiguos sin autor son de claude: era el unico agente que se registraba.
    static func belongs(_ e: PetMemoryEvent, to agent: String) -> Bool { e.agent == agent || (e.agent.isEmpty && agent == "claude") }

    static func stage(events: Int) -> String { stages.last { events >= $0.min }!.name }

    static func profile(agent: String, events all: [PetMemoryEvent], notes: Int, now: Date = Date(), calendar: Calendar = .current) -> PersonalityProfile {
        let mine = all.filter { belongs($0, to: agent) }
        let recent = mine.filter { $0.at >= now.addingTimeInterval(-window) }
        let days = Set(recent.map { calendar.startOfDay(for: $0.at) }).count
        let errors = mine.filter { $0.kind == .error }.count
        let enough = mine.count >= 10
        let night = recent.filter { let h = calendar.component(.hour, from: $0.at); return h >= 22 || h < 5 }.count
        let projects = Set(mine.map(\.project).filter { !$0.isEmpty }).count

        let traits = [
            PersonalityTrait(key: "constancia", label: "constancia", adjective: "constante", value: min(1, Double(days) / 14), note: "\(days) de 14 días"),
            PersonalityTrait(key: "precision", label: "precisión", adjective: "preciso", value: enough ? 1 - Double(errors) / Double(mine.count) : 0.5, note: enough ? "\(errors) fallos en \(mine.count)" : "aún poco que medir"),
            PersonalityTrait(key: "noche", label: "noctámbulo", adjective: "nocturno", value: recent.isEmpty ? 0 : Double(night) / Double(recent.count), note: recent.isEmpty ? "sin datos" : "\(Int((Double(night) / Double(recent.count) * 100).rounded())) % de noche"),
            PersonalityTrait(key: "exploracion", label: "exploración", adjective: "explorador", value: min(1, Double(projects) / 6), note: "\(projects) proyectos"),
            PersonalityTrait(key: "memoria", label: "memoria", adjective: "memorioso", value: min(1, Double(notes) / 20), note: "\(notes) notas propias"),
        ]
        let strong = traits.filter { $0.value >= 0.5 }.sorted { $0.value > $1.value }.prefix(2).map(\.adjective)
        let summary: String
        if !enough { summary = "todavía formándose" }
        else if strong.isEmpty { summary = "tranquilo y reservado" }
        else { summary = strong.joined(separator: " y ") }
        return PersonalityProfile(agent: agent, events: mine.count, activeDays: days, stage: stage(events: mine.count), traits: traits, summary: summary)
    }

    /// Lo que el agente recibe: su propio carácter, como tono y no como regla.
    static func briefing(_ p: PersonalityProfile) -> String {
        guard p.formed else { return "personalidad: aún se está formando contigo (\(p.events) recuerdos). sé tú mismo y deja notas de tipo trato cuando notes cómo le gusta trabajar.\n" }
        return "personalidad que has formado con este usuario: \(p.summary) (\(p.stage), \(p.events) recuerdos en \(p.activeDays) días activos). úsala como tono, nunca a costa de la precisión.\n"
    }
}
