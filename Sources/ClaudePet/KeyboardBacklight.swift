import Foundation

/// Acceso a la retroiluminacion del teclado integrado con `KeyboardBrightnessClient`, de CoreBrightness (framework privado de macOS:
/// Apple puede cambiarlo en cualquier actualizacion; si falta o no responde, la funcion simplemente no se activa).
final class KeyboardBacklight: @unchecked Sendable {
    private typealias IDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias GetF = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias GetB = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias SetFade = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    private let client: NSObject?
    private let id: UInt64
    var available: Bool { client != nil }

    init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { client = nil; id = 0; return }
        let c = cls.init()
        func call<T>(_ name: String, _ type: T.Type) -> T? {
            let sel = NSSelectorFromString(name)
            return c.responds(to: sel) ? unsafeBitCast(c.method(for: sel), to: type) : nil
        }
        guard let list = call("copyKeyboardBacklightIDs", IDs.self),
              let ids = list(c, NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber], !ids.isEmpty,
              let builtIn = call("isKeyboardBuiltIn:", GetB.self) else { client = nil; id = 0; return }
        // el teclado integrado; si ninguno lo es (un Mac de sobremesa con un teclado externo) no se toca nada
        guard let chosen = ids.map(\.uint64Value).first(where: { builtIn(c, NSSelectorFromString("isKeyboardBuiltIn:"), $0) }) else { client = nil; id = 0; return }
        client = c; id = chosen
    }

    private func call<T>(_ name: String, _ type: T.Type) -> T? {
        guard let client else { return nil }
        let sel = NSSelectorFromString(name)
        return client.responds(to: sel) ? unsafeBitCast(client.method(for: sel), to: type) : nil
    }

    var brightness: Float? {
        guard let client, let f = call("brightnessForKeyboard:", GetF.self) else { return nil }
        return f(client, NSSelectorFromString("brightnessForKeyboard:"), id)
    }

    /// Cuando el sistema atenua o suprime la luz (por inactividad o con la tapa casi cerrada) no se debe despertar: manda el sistema.
    var systemOwnsLight: Bool {
        guard let client else { return true }
        func flag(_ name: String) -> Bool { call(name, GetB.self).map { $0(client, NSSelectorFromString(name), id) } ?? false }
        return flag("isBacklightDimmedOnKeyboard:") || flag("isBacklightSuppressedOnKeyboard:")
    }

    @discardableResult
    func set(_ value: Float, fade: Int32 = 0) -> Bool {
        guard let client, let f = call("setBrightness:fadeSpeed:commit:forKeyboard:", SetFade.self) else { return false }
        return f(client, NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:"), min(1, max(0, value)), fade, true, id)
    }
}
