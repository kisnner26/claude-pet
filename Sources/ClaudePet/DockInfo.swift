import AppKit

struct DockItem: Equatable {
    var title: String
    /// En coordenadas de AppKit.
    var frame: CGRect
}

/// Los iconos del Dock (nombre y posicion) leidos por accesibilidad, para que una mascota camine hasta el de la app del agente.
enum DockInfo {
    /// El Dock solo sirve de pista si esta abajo y a la vista: de lado o escondido no se camina por el.
    static func isUsableLayout(orientation: String?, autohide: Bool) -> Bool { (orientation ?? "bottom") == "bottom" && !autohide }

    static func currentLayoutUsable() -> Bool {
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        let autohide = (CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool) ?? false
        return isUsableLayout(orientation: orientation, autohide: autohide)
    }

    private static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() }

    /// El icono de una app por su nombre: exacto primero y, si no, el que lo contiene ("Visual Studio Code" frente a "Code").
    static func item(forApp name: String, in items: [DockItem]) -> DockItem? {
        let n = fold(name)
        guard !n.isEmpty else { return nil }
        return items.first { fold($0.title) == n } ?? items.first { let t = fold($0.title); return t.contains(n) || (t.count >= 4 && n.contains(t)) }
    }

    @MainActor
    static func items() -> [DockItem] {
        guard AXIsProcessTrusted(), let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &kids) == .success, let top = kids as? [AXUIElement] else { return [] }
        var out: [DockItem] = []
        for list in top {
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXRoleAttribute as CFString, &role) == .success, (role as? String) == "AXList" else { continue }
            var items: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items) == .success, let icons = items as? [AXUIElement] else { continue }
            for icon in icons {
                var title: CFTypeRef?, pos: CFTypeRef?, size: CFTypeRef?
                guard AXUIElementCopyAttributeValue(icon, kAXTitleAttribute as CFString, &title) == .success, let t = title as? String, !t.isEmpty,
                      AXUIElementCopyAttributeValue(icon, kAXPositionAttribute as CFString, &pos) == .success,
                      AXUIElementCopyAttributeValue(icon, kAXSizeAttribute as CFString, &size) == .success, let pv = pos, let sv = size else { continue }
                var p = CGPoint.zero, s = CGSize.zero
                guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s), s.width > 10 else { continue }
                out.append(DockItem(title: t, frame: DeskGeo.appKit(CGRect(origin: p, size: s), primaryHeight: primaryHeight)))
            }
        }
        return out
    }
}
