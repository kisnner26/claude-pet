import Foundation
import ServiceManagement

/// `ClaudePet --selftest-login`: la traduccion del estado de SMAppService a lo que ensena la interfaz.
/// No registra nada en el sistema: solo usa la parte pura.
enum LoginItemSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        // estado del sistema -> estado de la app
        check("map-enabled", LoginItem.state(status: .enabled, packaged: true) == .on)
        check("map-off", LoginItem.state(status: .notRegistered, packaged: true) == .off)
        check("map-approval", LoginItem.state(status: .requiresApproval, packaged: true) == .needsApproval)
        check("map-notfound", LoginItem.state(status: .notFound, packaged: true) == .notFound)
        for s in [SMAppService.Status.enabled, .notRegistered, .requiresApproval, .notFound] {
            check("map-sin-paquete-\(s.rawValue)", LoginItem.state(status: s, packaged: false) == .unavailable)
        }

        // estado de la app -> interfaz
        let on = LoginItem.presentation(.on)
        check("ui-on", on.isOn && on.canToggle && on.warning == nil && !on.offersSystemSettings)
        let off = LoginItem.presentation(.off)
        check("ui-off", !off.isOn && off.canToggle && off.warning == nil)
        let ap = LoginItem.presentation(.needsApproval)
        check("ui-approval", !ap.isOn && ap.canToggle && ap.warning != nil && ap.offersSystemSettings)
        let nf = LoginItem.presentation(.notFound)
        check("ui-notfound", !nf.isOn && nf.warning != nil && !nf.offersSystemSettings)
        let un = LoginItem.presentation(.unavailable, errorCode: 7)
        check("ui-sin-paquete", !un.isOn && !un.canToggle && un.warning == nil && !un.detail.isEmpty)
        let err = LoginItem.presentation(.off, errorCode: 1)
        check("ui-error", err.warning?.contains("código 1") == true && err.offersSystemSettings && !err.isOn)

        // el binario de pruebas corre suelto: nunca debe parecer activado
        check("suelto-no-disponible", LoginItem.isPackaged || LoginItem.state() == .unavailable)

        // todo texto del interruptor tiene su traduccion
        let saved = L.current
        defer { L.current = saved }
        L.current = .en
        let all: [LoginItemPresentation] = [on, off, ap, nf, un, err]
        for p in all {
            check("en-detalle: \(p.detail)", L.tr(p.detail) != p.detail)
            if let w = p.warning { check("en-aviso: \(w)", L.tr(w) != w) }
        }
        for t in ["al iniciar sesión", "abrir al iniciar sesión", "atención", "abrir Ajustes del Sistema"] { check("en-titulo: \(t)", L.tr(t) != t) }
        check("en-error-con-cifra", L.tr("no se pudo cambiar (código 42). prueba otra vez o revisa Ajustes del Sistema.") == "couldn't change it (code 42). Try again or check System Settings.")

        // buscador de ajustes
        check("busca-login", SettingsPage.matching("iniciar sesion") == [.comportamiento] && SettingsPage.matching("login").contains(.comportamiento))

        print(failures == 0 ? "INICIO OK" : "INICIO \(failures) FALLOS")
        return failures == 0
    }
}
