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
                    if let peer = store.peer, !store.gameActive {
                        let color = peer.state == .waiting ? Pal.body : (peer.state == .error ? Pal.dark : Pal.cream.opacity(0.6))
                        var cable = Path(); cable.move(to: CGPoint(x: 4, y: 17)); cable.addLine(to: CGPoint(x: 35, y: 17 + (tick % 2) * 2)); cable.addLine(to: CGPoint(x: 70, y: 17)); cable.addLine(to: CGPoint(x: 108, y: 34))
                        gc.stroke(cable, with: .color(color), style: StrokeStyle(lineWidth: peer.state == .tool ? 3 : 2, lineCap: .square))
                        if peer.state == .tool { gc.fill(Path(ellipseIn: CGRect(x: 53, y: 12, width: 6, height: 6)), with: .color(Pal.light)) }
                    }
                    let u = size.width / 16
                    if store.bugBattleLevel > 0 {
                        let level = store.bugBattleLevel
                        for i in 0..<(level * 3) {
                            let x = CGFloat(72 + (i * 7 + tick * 3) % 34), y = CGFloat(72 + (i * 11) % 26)
                            gc.fill(Path(CGRect(x: x, y: y, width: 5, height: 5)), with: .color(i % 2 == 0 ? Pal.dark : Pal.cream))
                        }
                    }
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
