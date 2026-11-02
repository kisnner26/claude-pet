import AppKit

/// Las ventanas reales de la pantalla, de mas al frente a mas al fondo, para que las mascotas puedan posarse en ellas.
/// Solo se leen posiciones, tamanos, el nombre de la app y el titulo (lo mismo que ya usa "saltar a la terminal"); no se captura la pantalla.
enum WindowCatalog {
    @MainActor
    static func snapshot(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> [DeskWindow] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { row -> DeskWindow? in
            guard let number = row[kCGWindowNumber as String] as? Int,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = row[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { return nil }
            let cg = CGRect(x: x, y: y, width: w, height: h)
            let layer = (row[kCGWindowLayer as String] as? Int) ?? 0
            let alpha = (row[kCGWindowAlpha as String] as? Double) ?? 1
            guard DeskGeo.isUsable(layer: layer, frame: cg, alpha: alpha, isOwn: pid == ownPID) else { return nil }
            return DeskWindow(id: number, pid: pid, owner: (row[kCGWindowOwnerName as String] as? String) ?? "",
                              title: (row[kCGWindowName as String] as? String) ?? "", frame: DeskGeo.appKit(cg, primaryHeight: primaryHeight))
        }
    }

    /// Apps donde suele trabajar un agente: terminales, editores y la propia app de Claude.
    static let agentHosts = ["terminal", "iterm", "ghostty", "warp", "wezterm", "alacritty", "kitty", "hyper", "tabby", "visual studio code", "code", "cursor", "zed", "xcode", "claude", "windsurf"]

    static func isAgentHost(_ owner: String) -> Bool {
        let o = owner.lowercased()
        return agentHosts.contains { o == $0 || o.contains($0) }
    }

    /// La ventana donde trabaja el agente: la mas al frente de una app anfitriona cuyo titulo menciona el proyecto; si ninguna lo dice
    /// (sin titulos, o el agente vive en la app de Claude), la mas al frente de cualquier anfitriona.
    static func agentWindow(project: String, in windows: [DeskWindow]) -> Int? {
        let hosts = windows.indices.filter { isAgentHost(windows[$0].owner) }
        if !project.isEmpty, let named = hosts.first(where: { windows[$0].title.lowercased().contains(project.lowercased()) }) { return named }
        return hosts.first
    }

    /// Los titulos reales salen de la accesibilidad (que ya tienes concedida): CoreGraphics no los da sin el permiso de grabar la pantalla.
    @MainActor
    static func fillTitles(_ windows: [DeskWindow]) -> [DeskWindow] {
        guard AXIsProcessTrusted() else { return windows }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var out = windows
        var cache: [Int32: [(CGRect, String)]] = [:]
        for i in out.indices where out[i].title.isEmpty && isAgentHost(out[i].owner) {
            let pid = out[i].pid
            if cache[pid] == nil { cache[pid] = axWindows(pid: pid, primaryHeight: primaryHeight) }
            if let match = cache[pid]?.first(where: { abs($0.0.minX - out[i].frame.minX) < 3 && abs($0.0.minY - out[i].frame.minY) < 3 && abs($0.0.width - out[i].frame.width) < 3 }) {
                out[i].title = match.1
            }
        }
        return out
    }

    /// Ventanas de una app segun la accesibilidad, ya en coordenadas de AppKit.
    private static func axWindows(pid: Int32, primaryHeight: CGFloat) -> [(CGRect, String)] {
        let app = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success, let list = raw as? [AXUIElement] else { return [] }
        return list.compactMap { w -> (CGRect, String)? in
            var t: CFTypeRef?, p: CFTypeRef?, s: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success, AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success,
                  let pv = p, let sv = s else { return nil }
            var point = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(pv as! AXValue, .cgPoint, &point), AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return nil }
            _ = AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            return (DeskGeo.appKit(CGRect(origin: point, size: size), primaryHeight: primaryHeight), (t as? String) ?? "")
        }
    }
}
