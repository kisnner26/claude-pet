import AppKit

/// Saca una foto del arbol de accesibilidad de la ventana de un editor para buscar la pestana de un archivo.
/// Va acotado (profundidad, numero de nodos y tiempo) porque algunas apps tienen arboles enormes. Los editores hechos con Electron
/// (VS Code, Cursor) solo exponen su arbol si algo se lo pide; sin el, no se encuentra la pestana y el cursor va a la barra de titulo.
enum EditorLocator {
    static let maxDepth = 9, maxNodes = 600, maxSeconds = 0.25

    /// Foto de la ventana de `pid` cuyo marco (AppKit) coincide con `frame`. Se puede llamar fuera del hilo principal.
    static func snapshot(pid: Int32, frame: CGRect, primaryHeight: CGFloat) -> AXSnap? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success, let windows = raw as? [AXUIElement] else { return nil }
        for w in windows {
            guard let f = frameOf(w, primaryHeight: primaryHeight), abs(f.minX - frame.minX) < 3, abs(f.minY - frame.minY) < 3, abs(f.width - frame.width) < 3 else { continue }
            var budget = maxNodes
            let deadline = Date().addingTimeInterval(maxSeconds)
            return node(w, depth: 0, budget: &budget, deadline: deadline, primaryHeight: primaryHeight)
        }
        return nil
    }

    /// Contenido que no se lee nunca: el texto de los documentos y las paginas web. Solo interesan los titulos de pestanas y ventanas.
    static let contentRoles: Set<String> = ["AXTextArea", "AXTextField", "AXWebArea", "AXSecureTextField", "AXComboBox"]

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        if let s = v as? String, !s.isEmpty { return String(s.prefix(100)) }
        return nil
    }

    private static func frameOf(_ e: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success, AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let pv = p, let sv = s else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &point), AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return nil }
        return DeskGeo.appKit(CGRect(origin: point, size: size), primaryHeight: primaryHeight)
    }

    private static func node(_ e: AXUIElement, depth: Int, budget: inout Int, deadline: Date, primaryHeight: CGFloat) -> AXSnap {
        budget -= 1
        let role = string(e, kAXRoleAttribute) ?? ""
        // el contenido de documentos y paginas ni se lee ni se recorre
        if contentRoles.contains(role) { return AXSnap(role: role, texts: [], frame: frameOf(e, primaryHeight: primaryHeight)) }
        var snap = AXSnap(role: role, texts: [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { string(e, $0) }, frame: frameOf(e, primaryHeight: primaryHeight))
        guard depth < maxDepth, budget > 0, Date() < deadline else { return snap }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let list = kids as? [AXUIElement] else { return snap }
        for child in list {
            guard budget > 0, Date() < deadline else { break }
            snap.children.append(node(child, depth: depth + 1, budget: &budget, deadline: deadline, primaryHeight: primaryHeight))
        }
        return snap
    }
}
