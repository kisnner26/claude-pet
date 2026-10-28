import AppIntents
import Foundation

/// Atajos de Visto: botón de acción del iPhone y del Apple Watch Ultra, Siri, Atajos y el centro de control.
/// Cada plataforma registra aquí cómo responder; los intents solo piden «permite» o «deniega» y devuelven una frase.
enum QuickDecision {
    nonisolated(unsafe) static var decide: (@Sendable (Bool) async -> String)?
    nonisolated(unsafe) static var focus: (@Sendable (Bool) async -> String)?
}

struct AllowPendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Permitir el permiso pendiente"
    static var description = IntentDescription("Permite el permiso más reciente que espera Claude, si no es de riesgo alto.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await QuickDecision.decide?(true) ?? "Visto no está lista."))
    }
}

struct DenyPendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Denegar el permiso pendiente"
    static var description = IntentDescription("Deniega el permiso más reciente que espera Claude.")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await QuickDecision.decide?(false) ?? "Visto no está lista."))
    }
}

struct FocusModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Modo foco en la Mac"
    static var openAppWhenRun = false
    @Parameter(title: "Activar") var on: Bool
    init() {}
    init(on: Bool) { self.on = on }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await QuickDecision.focus?(on) ?? "Visto no está lista."))
    }
}

struct VistoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AllowPendingIntent(), phrases: ["Permitir en \(.applicationName)", "Aprobar en \(.applicationName)"], shortTitle: "Permitir", systemImageName: "checkmark.circle")
        AppShortcut(intent: DenyPendingIntent(), phrases: ["Denegar en \(.applicationName)", "Rechazar en \(.applicationName)"], shortTitle: "Denegar", systemImageName: "xmark.circle")
    }
}
