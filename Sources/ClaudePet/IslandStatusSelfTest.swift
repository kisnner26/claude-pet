import SwiftUI

enum IslandStatusSelfTest {
    static func alertLabel(_ activity: Activity) -> String { "alerta de seguridad: \(activity.title)" }
    static func tone(for state: PetState) -> String {
        switch state {
        case .waiting: return "ámbar"
        case .error: return "rojo"
        case .done: return "verde"
        case .tool, .thinking, .starting: return "azul"
        case .idle: return "invisible"
        }
    }
    static func run() -> Bool {
        let ok = tone(for: .waiting) == "ámbar" && tone(for: .error) == "rojo" && tone(for: .done) == "verde"
            && tone(for: .thinking) == "azul" && tone(for: .idle) == "invisible"
            && alertLabel(Activity(title: "claude parece bloqueado", subtitle: "", origin: "")) == "alerta de seguridad: claude parece bloqueado"
        print(ok ? "ESTADO VISUAL OK" : "ESTADO VISUAL FALLOS")
        return ok
    }
}
