import SwiftUI
import AppKit

/// Cuando la mascota se harta de los golpes: a veces, al segundo toque seguido, se enfada, se hace gigante, camina hasta una ventana,
/// la patea y la minimiza (nunca la cierra). Todo lo que decide es puro para poder probarlo sin ventanas.
enum RageTrigger {
    static let cooldown: TimeInterval = 60
    static let window: TimeInterval = 1.5
    static let chance = 0.35

    /// Al segundo toque en `window` segundos, con una probabilidad, y no antes de `cooldown` desde el ultimo enfado.
    /// `roll` es un numero de 0 a 1 (inyectado para poder probarlo). El tercer toque marea, asi que el enfado tiene que llegar antes.
    static func shouldRage(pokes: [TimeInterval], now: TimeInterval, roll: Double, lastRage: TimeInterval?) -> Bool {
        if let last = lastRage, now - last < cooldown { return false }
        let recent = pokes.filter { $0 <= now && now - $0 < window }
        return recent.count == 2 && roll < chance
    }
}

struct RageFrame: Equatable {
    /// Tamano relativo: 0,16 = el de la isla, 1 = gigante.
    var size: Double
    /// Avance del paseo desde la isla hasta la ventana (0 a 1).
    var walk: Double
    var hop: Double
    var tilt: Double
    var squash: Double
    var kicking: Bool
    var glow: Double
    /// 0 a 1 mientras dura el golpe contra la ventana, nil si no ha llegado o ya paso.
    var impact: Double?
}

enum RageChoreography {
    static let duration: TimeInterval = 4.0
    static let growEnd = 0.8, walkEnd = 1.9, windupEnd = 2.15, kickEnd = 2.35, glareEnd = 3.1
    /// Instante del golpe: aqui es cuando la ventana se minimiza.
    static let impactAt: TimeInterval = 2.25
    static let small = 0.16

    static func frame(at t: TimeInterval) -> RageFrame {
        func ease(_ k: Double) -> Double { let c = min(1, max(0, k)); return c * c * (3 - 2 * c) }
        var f = RageFrame(size: small, walk: 0, hop: 0, tilt: 0, squash: 1, kicking: false, glow: 0, impact: nil)
        if t < growEnd {
            let k = max(0, t) / growEnd, c = 1.70158, back = 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2)
            f.size = small + (1 - small) * min(1.08, back)
            f.glow = ease(k); f.tilt = sin(t * 38) * 3 * (1 - k)
        } else if t < walkEnd {
            let k = (t - growEnd) / (walkEnd - growEnd)
            f.size = 1; f.walk = ease(k); f.hop = abs(sin(t * 11)) * 0.05; f.tilt = sin(t * 11) * 4; f.glow = 1
        } else if t < windupEnd {
            let k = (t - walkEnd) / (windupEnd - walkEnd)
            f.size = 1; f.walk = 1; f.tilt = -14 * ease(k); f.squash = 1 - 0.08 * ease(k); f.glow = 1
        } else if t < kickEnd {
            let k = (t - windupEnd) / (kickEnd - windupEnd)
            f.size = 1; f.walk = 1 + 0.05 * ease(k); f.tilt = -14 + 34 * ease(k); f.kicking = true; f.glow = 1
        } else if t < glareEnd {
            f.size = 1; f.walk = 1.05 - 0.05 * ease((t - kickEnd) / 0.3); f.tilt = 20 * (1 - ease((t - kickEnd) / 0.4)); f.glow = 1 - ease((t - kickEnd) / (glareEnd - kickEnd)) * 0.4
        } else {
            let k = (t - glareEnd) / (duration - glareEnd)
            f.size = 1 - (1 - small) * ease(k); f.walk = 1 - ease(k); f.glow = 0.6 * (1 - ease(k))
        }
        if t >= impactAt, t < impactAt + 0.45 { f.impact = (t - impactAt) / 0.45 }
        return f
    }
}

/// Una ventana de otra app que se ve en pantalla.
struct KickTarget: Equatable {
    var pid: pid_t
    var owner: String
    /// Marco en coordenadas de la pantalla (origen arriba a la izquierda).
    var frame: CGRect
    /// Marco global de CoreGraphics, para encontrar la misma ventana en la API de accesibilidad.
    var global: CGRect
}

enum WindowKick {
    /// La ventana de arriba que no es nuestra, de tamano razonable. Pura sobre la lista que da `CGWindowListCopyWindowInfo`.
    static func pick(from list: [[String: Any]], ownPID: pid_t, screen: CGRect, screenGlobal: CGRect) -> KickTarget? {
        let skip: Set<String> = ["Window Server", "Dock", "Control Center", "Notification Center", "SystemUIServer", "Spotlight"]
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let owner = w[kCGWindowOwnerName as String] as? String, !skip.contains(owner),
                  ((w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.5,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let x = (b["X"] as? NSNumber).map({ CGFloat(truncating: $0) }), let y = (b["Y"] as? NSNumber).map({ CGFloat(truncating: $0) }),
                  let width = (b["Width"] as? NSNumber).map({ CGFloat(truncating: $0) }), let height = (b["Height"] as? NSNumber).map({ CGFloat(truncating: $0) }) else { continue }
            let g = CGRect(x: x, y: y, width: width, height: height)
            guard width >= 240, height >= 160, g.intersects(screenGlobal), g.width * g.height < screenGlobal.width * screenGlobal.height * 0.97 else { continue }
            let local = CGRect(x: g.minX - screenGlobal.minX, y: g.minY - screenGlobal.minY, width: g.width, height: g.height)
            _ = screen
            return KickTarget(pid: pid, owner: owner, frame: local, global: g)
        }
        return nil
    }

    /// Minimiza la ventana (no la cierra). Necesita el permiso de accesibilidad; sin el no hace nada y devuelve false.
    @discardableResult
    static func minimize(_ t: KickTarget) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(t.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return false }
        func point(_ w: AXUIElement) -> CGPoint? {
            var v: CFTypeRef?; var p = CGPoint.zero
            guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &v) == .success, let ax = v, CFGetTypeID(ax) == AXValueGetTypeID(), AXValueGetValue(ax as! AXValue, .cgPoint, &p) else { return nil }
            return p
        }
        func size(_ w: AXUIElement) -> CGSize? {
            var v: CFTypeRef?; var s = CGSize.zero
            guard AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &v) == .success, let ax = v, CFGetTypeID(ax) == AXValueGetTypeID(), AXValueGetValue(ax as! AXValue, .cgSize, &s) else { return nil }
            return s
        }
        for w in windows {
            guard let p = point(w), let s = size(w), abs(p.x - t.global.minX) < 6, abs(p.y - t.global.minY) < 6, abs(s.width - t.global.width) < 6, abs(s.height - t.global.height) < 6 else { continue }
            return AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        }
        return false
    }
}

@MainActor
final class RageController {
    static let shared = RageController()
    private var panel: NSPanel?
    private(set) var running = false

    func start(agent: IslandAgentTab, store: PetStore) {
        guard store.rageEnabled, !running, store.animationsEnabled, !store.reduceMotion else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let global = CGRect(x: screen.frame.minX, y: primaryH - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        guard let target = WindowKick.pick(from: list, ownPID: ProcessInfo.processInfo.processIdentifier, screen: screen.frame, screenGlobal: global) else { return }

        running = true
        SoundEngine.shared.play(.error)
        let start = ProcessInfo.processInfo.systemUptime
        let panel = makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: RageOverlay(store: store, agent: agent, start: start, screen: screen.frame.size, target: target.frame))
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + RageChoreography.impactAt) {
            SoundEngine.shared.play(.denied)
            WindowKick.minimize(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + RageChoreography.duration + 0.15) { [weak self] in
            self?.panel?.orderOut(nil); self?.panel = nil; self?.running = false
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

struct RageOverlay: View {
    @ObservedObject var store: PetStore
    let agent: IslandAgentTab
    let start: TimeInterval
    let screen: CGSize
    let target: CGRect
    /// Para las capturas: un instante fijo en lugar del reloj.
    var fixedTime: TimeInterval?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let t = fixedTime ?? (ProcessInfo.processInfo.systemUptime - start)
            let f = RageChoreography.frame(at: t)
            let giant = min(screen.height * 0.42, 340)
            let side = giant * f.size
            // de pie junto a la ventana, por el lado con mas sitio; mira hacia ella
            let fromLeft = target.midX > screen.width / 2 ? true : false
            let home = CGPoint(x: screen.width / 2, y: 34 + giant * Self.small * 0.5)
            let stand = CGPoint(x: fromLeft ? max(giant * 0.5, target.minX - giant * 0.3) : min(screen.width - giant * 0.5, target.maxX + giant * 0.3),
                                y: min(screen.height - giant * 0.4, max(target.midY + giant * 0.2, giant * 0.7)))
            let w = f.walk
            let pos = CGPoint(x: home.x + (stand.x - home.x) * w, y: max(side * 0.5 + 8, home.y + (stand.y - home.y) * w - CGFloat(f.hop) * giant))   // al crecer no se sale por arriba
            ZStack(alignment: .topLeading) {
                Canvas { gc, size in drawEffects(&gc, f: f, t: t, pos: pos, side: side) }
                pet(f: f, t: t, side: side)
                    .frame(width: side, height: side * (agent == .codex ? 21.0 / 18.0 : 1))
                    .scaleEffect(x: fromLeft ? 1 : -1, y: 1)
                    .position(x: pos.x, y: pos.y)
            }
            .frame(width: screen.width, height: screen.height)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private static let small = RageChoreography.small

    private func pose(_ f: RageFrame, _ t: TimeInterval) -> PetPose {
        var p = PetPose()
        p.rotation = f.tilt; p.scaleY = CGFloat(f.squash); p.scaleX = CGFloat(2 - f.squash) * 0.5 + 0.5
        p.blink = true       // entrecierra los ojos, furioso
        p.annoyed = true
        p.dx = f.kicking ? 0.9 : 0
        return p
    }

    @ViewBuilder private func pet(f: RageFrame, t: TimeInterval, side: CGFloat) -> some View {
        let tick = Int(t * 8)
        let p = pose(f, t)
        if agent == .codex {
            CodexMiniFrame(face: .annoyed, legs: f.kicking ? .kick : (tick % 2 == 0 ? .step : .stand), tick: tick, skin: store.codexSkin, wave: false, pose: p, outfits: store.outfitsNow(for: .codex))
        } else {
            Canvas { gc, size in
                var px = Sprite.pixels(.idle, tick: tick)
                px = store.dress(px, state: .idle, tick: tick)
                px = PetAnimator.apply(px, pose: p)
                PetFace.draw(&gc, size: size, pixels: px, pose: p)
            }
        }
    }

    private func drawEffects(_ gc: inout GraphicsContext, f: RageFrame, t: TimeInterval, pos: CGPoint, side: CGFloat) {
        // brillo rojo de furia detras del cuerpo
        if f.glow > 0.02 {
            let r = side * 0.95
            gc.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(colors: [Color(hex: 0xE5322D).opacity(0.5 * f.glow), .clear]), center: pos, startRadius: 0, endRadius: r))
        }
        // vapor que sale de la cabeza y marca de enfado
        if f.size > 0.5 {
            for i in 0..<5 {
                let k = (t * 0.9 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                let x = pos.x + CGFloat(i - 2) * side * 0.11 + CGFloat(sin(t * 3 + Double(i))) * 4
                let y = pos.y - side * 0.5 - CGFloat(k) * side * 0.35, r = side * 0.03 * CGFloat(1 + k)
                gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.5 * (1 - k))))
            }
            var vein = Path(); let c = CGPoint(x: pos.x + side * 0.28, y: pos.y - side * 0.42), s = side * 0.07
            for (dx, dy) in [(-1.0, -1.0), (1.0, 1.0), (1.0, -1.0), (-1.0, 1.0)] { vein.move(to: CGPoint(x: c.x + dx * s * 0.3, y: c.y + dy * s * 0.3)); vein.addLine(to: CGPoint(x: c.x + dx * s, y: c.y + dy * s)) }
            gc.stroke(vein, with: .color(Color(hex: 0xE5322D)), style: StrokeStyle(lineWidth: max(2, side * 0.018), lineCap: .round))
        }
        // polvo en cada pisada y golpe contra la ventana
        if t > RageChoreography.growEnd, t < RageChoreography.windupEnd {
            for i in 0..<3 {
                let k = (t * 5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let r = side * 0.04 * CGFloat(k + 0.3)
                gc.fill(Path(ellipseIn: CGRect(x: pos.x + CGFloat(i - 1) * side * 0.25 - r, y: pos.y + side * 0.5 - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.28 * (1 - k))))
            }
        }
        if let k = f.impact {
            let c = CGPoint(x: target.midX, y: target.midY)
            // el contorno de la ventana tiembla y salen rayos del golpe
            let j = CGFloat(sin(t * 80)) * 6 * CGFloat(1 - k)
            gc.stroke(Path(roundedRect: target.offsetBy(dx: j, dy: 0), cornerRadius: 10), with: .color(Color(hex: 0xE5322D).opacity(0.8 * (1 - k))), lineWidth: 5)
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi, r0 = 30 + 160 * CGFloat(k), r1 = r0 + 60 * CGFloat(1 - k)
                var ray = Path(); ray.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0)); ray.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                gc.stroke(ray, with: .color(Color(hex: 0xFFE08A).opacity(1 - k)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
    }
}
