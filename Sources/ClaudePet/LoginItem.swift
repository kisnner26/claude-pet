import SwiftUI
import ServiceManagement

/// Lo que el sistema dice del elemento de inicio de sesion de la app, ya traducido a lo que la interfaz distingue.
enum LoginItemState: Equatable {
    /// Sin paquete .app (binario suelto de `.build/debug`): `SMAppService.mainApp` no tiene a que apuntar.
    case unavailable
    case off
    case on
    /// Registrado, pero el usuario debe aprobarlo en Ajustes del Sistema.
    case needsApproval
    /// El sistema no encuentra la app (movida, borrada o sin firma que acepte).
    case notFound
}

/// Lo que se dibuja para cada estado. Es pura: la prueba interna la recorre entera.
struct LoginItemPresentation: Equatable {
    var isOn: Bool
    var canToggle: Bool
    var detail: String
    var warning: String?
    var offersSystemSettings: Bool
}

enum LoginItem {
    static var isPackaged: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Traduccion del estado del sistema. Sin paquete no se consulta nada: el resultado seria engañoso.
    static func state(status: SMAppService.Status, packaged: Bool) -> LoginItemState {
        guard packaged else { return .unavailable }
        switch status {
        case .enabled: return .on
        case .notRegistered: return .off
        case .requiresApproval: return .needsApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    /// Estado real, leido del sistema en este momento (no se guarda aparte).
    static func state() -> LoginItemState {
        guard isPackaged else { return .unavailable }
        return state(status: SMAppService.mainApp.status, packaged: true)
    }

    static func presentation(_ state: LoginItemState, errorCode: Int? = nil) -> LoginItemPresentation {
        let normal = "abre claude pet en la barra de menús cada vez que inicias sesión en este Mac."
        var p: LoginItemPresentation
        switch state {
        case .unavailable:
            p = LoginItemPresentation(isOn: false, canToggle: false,
                                      detail: "solo está disponible con la app instalada: este binario se ejecuta suelto, sin paquete .app.",
                                      warning: nil, offersSystemSettings: false)
        case .off:
            p = LoginItemPresentation(isOn: false, canToggle: true, detail: normal, warning: nil, offersSystemSettings: false)
        case .on:
            p = LoginItemPresentation(isOn: true, canToggle: true, detail: normal, warning: nil, offersSystemSettings: false)
        case .needsApproval:
            p = LoginItemPresentation(isOn: false, canToggle: true, detail: normal,
                                      warning: "macOS necesita tu aprobación: actívala en Ajustes del Sistema, General, Ítems de inicio.",
                                      offersSystemSettings: true)
        case .notFound:
            p = LoginItemPresentation(isOn: false, canToggle: true, detail: normal,
                                      warning: "macOS no encuentra la app. muévela a Aplicaciones y vuelve a intentarlo.",
                                      offersSystemSettings: false)
        }
        if let errorCode, state != .unavailable {
            p.warning = "no se pudo cambiar (código \(errorCode)). prueba otra vez o revisa Ajustes del Sistema."
            p.offersSystemSettings = true
        }
        return p
    }

    /// Registra o quita el elemento. Devuelve el codigo del error si fallo; nunca su mensaje.
    static func change(on: Bool) async -> Int? {
        do {
            if on { try SMAppService.mainApp.register() }
            else if SMAppService.mainApp.status != .notRegistered { try await SMAppService.mainApp.unregister() }
            return nil
        } catch {
            Diag.login.error("cambio fallido: \(Diag.code(error), privacy: .public)")
            return (error as NSError).code
        }
    }

    /// Una palabra para el diagnostico.
    static func describe(_ s: LoginItemState) -> String {
        switch s {
        case .unavailable: return "no disponible (sin paquete)"
        case .off: return "desactivado"
        case .on: return "activado"
        case .needsApproval: return "pendiente de aprobación"
        case .notFound: return "app no encontrada"
        }
    }
}

/// Estado de la tarjeta de ajustes. Se vuelve a leer al aparecer y cuando la app vuelve a primer plano
/// (el usuario viene de Ajustes del Sistema); no hay temporizador.
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var errorCode: Int?
    @Published private(set) var working = false

    init() { state = LoginItem.state() }

    func refresh() { state = LoginItem.state() }

    func set(_ on: Bool) {
        guard LoginItem.isPackaged, !working else { return }
        working = true
        // el registro habla con el sistema por XPC: fuera del hilo principal
        Task.detached(priority: .userInitiated) { [weak self] in
            let code = await LoginItem.change(on: on)
            let after = LoginItem.state()
            await self?.finish(code: code, state: after)
        }
    }

    private func finish(code: Int?, state after: LoginItemState) {
        errorCode = code
        state = after
        working = false
        if code == nil { Diag.login.info("abrir al iniciar sesion: \(LoginItem.describe(after), privacy: .public)") }
    }
}

struct LoginItemCard: View {
    @StateObject private var model = LoginItemModel()

    var body: some View {
        let p = LoginItem.presentation(model.state, errorCode: model.errorCode)
        SCard(title: "al iniciar sesión") {
            SToggle(title: "abrir al iniciar sesión", detail: p.detail,
                    isOn: Binding(get: { p.isOn }, set: { model.set($0) }))
                .disabled(!p.canToggle || model.working)
                .opacity(p.canToggle ? 1 : 0.5)
            if let warning = p.warning {
                SDivider()
                SRow(title: "atención", detail: warning) {
                    if p.offersSystemSettings {
                        SButton(title: "abrir Ajustes del Sistema", symbol: "arrow.up.right") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
