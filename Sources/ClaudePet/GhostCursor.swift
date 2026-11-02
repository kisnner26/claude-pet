import SwiftUI
import AppKit

/// El cursor fantasma del agente: una flecha del color de su mascota que se desliza hasta la pestana del archivo que acaba de tocar.
@MainActor
final class GhostCursor {
    static let shared = GhostCursor()

    private final class Model: ObservableObject {
        @Published var tint = Color(hex: 0xE0824F)
        @Published var ring: CGFloat = 0
        @Published var alpha: CGFloat = 1
    }

    private var move: GhostMove?
    private var panel: NSPanel?
    private let model = Model()

    func start(from: CGPoint, to: CGPoint, tint: Color, now: TimeInterval) {
        move = GhostMove(from: from, to: to, start: now)
        model.tint = tint
        ensurePanel()
    }

    func tick(now: TimeInterval) {
        guard let m = move else { return }
        let f = m.frame(at: now)
        if f.done { move = nil; panel?.orderOut(nil); return }
        model.ring = f.ring; model.alpha = f.alpha
        // la punta de la flecha queda justo en el punto (el panel mide 80 y la punta esta en el centro)
        panel?.setFrameOrigin(NSPoint(x: f.point.x - 40, y: f.point.y - 40))
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    func stop() { move = nil; panel?.orderOut(nil) }

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: GhostView(model: model))
        panel = p
    }

    private struct Arrow: Shape {
        func path(in r: CGRect) -> Path {
            // la flecha clasica del raton, con la punta arriba a la izquierda de su caja
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 17))
            p.addLine(to: CGPoint(x: 4.5, y: 13))
            p.addLine(to: CGPoint(x: 8, y: 20.5))
            p.addLine(to: CGPoint(x: 11, y: 19))
            p.addLine(to: CGPoint(x: 7.6, y: 12))
            p.addLine(to: CGPoint(x: 13, y: 12))
            p.closeSubpath()
            return p
        }
    }

    private struct GhostView: View {
        @ObservedObject var model: Model
        var body: some View {
            ZStack {
                Circle().stroke(model.tint, lineWidth: 2.5).frame(width: 14 + 52 * model.ring, height: 14 + 52 * model.ring).opacity(Double((1 - model.ring) * 0.9) * (model.ring > 0 ? 1 : 0))
                // la punta (0,0) de la flecha en el centro de la ventana
                Arrow().fill(Color.white).overlay(Arrow().stroke(model.tint, lineWidth: 1.6)).frame(width: 14, height: 21)
                    .shadow(color: model.tint.opacity(0.8), radius: 5)
                    .offset(x: 7, y: 10.5)
            }
            .opacity(model.alpha)
            .frame(width: 80, height: 80)
        }
    }
}
