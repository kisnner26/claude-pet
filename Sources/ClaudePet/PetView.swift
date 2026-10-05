import SwiftUI
import AppKit

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct PetView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.125)) { ctx in
                let tick = store.animationsEnabled ? Int(ctx.date.timeIntervalSinceReferenceDate * 8) : 0
                Canvas { gc, size in
                    let u = size.width / 16
                    for p in Sprite.pixels(store.state, tick: tick, cue: store.cue(at: ctx.date)) {
                        gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c))
                    }
                }
                .frame(width: 112, height: 112)
            }
        }
        .padding(8)
        .frame(width: 128, height: 128)
        // casi invisible: mantiene el arrastre de la ventana sin dibujar ningun panel
        .background(Color.black.opacity(0.001))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
    }
}
