import SwiftUI
import AppKit

/// El halo que enciende el icono de la app del agente en el Dock mientras trabaja. Es una ventana transparente que no recibe clics,
/// colocada justo encima del icono; desaparece cuando el agente deja de trabajar.
@MainActor
final class DockGlow {
    static let shared = DockGlow()

    private final class Model: ObservableObject {
        @Published var tint = Color(hex: 0xE0824F)
        @Published var animated = true
    }

    private var panel: NSPanel?
    private let model = Model()
    private var shownFrame: CGRect?

    func apply(frame: CGRect?, tint: Color, animated: Bool) {
        guard let frame else { hide(); return }
        let target = frame.insetBy(dx: -10, dy: -10)
        model.tint = tint; model.animated = animated
        if panel == nil {
            let p = NSPanel(contentRect: target, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            // por encima del Dock (nivel 20)
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: GlowView(model: model))
            panel = p
        }
        if shownFrame != target { panel?.setFrame(target, display: true); shownFrame = target }
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
        shownFrame = nil
    }

    private struct GlowView: View {
        @ObservedObject var model: Model
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !model.animated)) { ctx in
                let t = model.animated ? ctx.date.timeIntervalSinceReferenceDate : 0
                let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.6)
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(model.tint.opacity(0.14 + 0.16 * pulse))
                    RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(model.tint.opacity(0.55 + 0.4 * pulse), lineWidth: 2)
                }
                .shadow(color: model.tint.opacity(0.7), radius: 6 + 6 * pulse)
                .padding(6)
            }
        }
    }
}
