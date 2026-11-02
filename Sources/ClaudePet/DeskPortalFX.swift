import SwiftUI
import AppKit

/// Los efectos de sacar y volver a meter a una mascota: resplandor de la isla, ondas de choque, chispas, estela y polvo al caer.
/// Es una ventana transparente que no recibe clics y que solo existe mientras dura algun efecto.
@MainActor
final class DeskPortalFX {
    static let shared = DeskPortalFX()

    enum Kind {
        case emerge(from: CGPoint, to: CGPoint)
        case pop(at: CGPoint)
        case dive(from: CGPoint, to: CGPoint)
    }

    fileprivate struct Item {
        var kind: Kind
        var start: TimeInterval
        var tint: Color
        var seed: Int
        var duration: TimeInterval
    }

    fileprivate final class Model: ObservableObject { var items: [Item] = []; var origin = CGPoint.zero; var top: CGFloat = 0 }
    private let model = Model()
    private var panel: NSPanel?
    private var cleanup: Timer?

    static func duration(of kind: Kind) -> TimeInterval {
        switch kind {
        case .emerge: return DeskPortal.emergeDuration + 0.2
        case .pop: return DeskPortal.popDuration + 0.1
        case .dive: return DeskPortal.diveDuration + 0.75
        }
    }

    func play(_ kind: Kind, tint: Color, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        model.items.append(Item(kind: kind, start: now, tint: tint, seed: Int(now * 1000) & 0xFFFF, duration: Self.duration(of: kind)))
        ensurePanel()
        if cleanup == nil {
            cleanup = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { DeskPortalFX.shared.sweep() } }
        }
    }

    func stop() { model.items.removeAll(); sweep() }

    private func sweep() {
        let now = ProcessInfo.processInfo.systemUptime
        model.items.removeAll { now - $0.start > $0.duration }
        if model.items.isEmpty { cleanup?.invalidate(); cleanup = nil; panel?.orderOut(nil) }
    }

    private func ensurePanel() {
        // una sola ventana sobre todas las pantallas
        let union = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return }
        model.origin = union.origin; model.top = union.maxY
        if panel == nil {
            let p = NSPanel(contentRect: union, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: FXView(model: model))
            panel = p
        }
        if panel?.frame != union { panel?.setFrame(union, display: true) }
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    // MARK: hoja de contacto

    /// `ClaudePet --snapshot-portal <ruta.png>`: fotogramas de salir y de volver, dibujados con el mismo codigo que usan las ventanas de efectos.
    static func renderSheet(to path: String) {
        let anchor = CGPoint(x: 840, y: 1030), spot = CGPoint(x: 1090, y: 700)
        let origin = CGPoint(x: 690, y: 640), top: CGFloat = 1060
        let cell = CGSize(width: 520, height: 420)
        func p(_ a: CGPoint) -> CGPoint { CGPoint(x: a.x - origin.x, y: top - a.y) }
        let tint = Color(hex: 0xE0824F)
        func cellView(_ label: String, _ build: @escaping (inout GraphicsContext) -> Void) -> some View {
            Canvas { gc, size in
                gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(hex: 0x2A2D36), Color(hex: 0x15161A)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                gc.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 30)), with: .color(Color.white.opacity(0.08)))      // la barra de menus
                let a = p(anchor)
                gc.fill(Path(roundedRect: CGRect(x: a.x - 70, y: a.y - 14, width: 140, height: 30), cornerRadius: 15), with: .color(.black))      // la isla
                build(&gc)
                gc.draw(Text(label).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.75)), at: CGPoint(x: 8, y: size.height - 16), anchor: .leading)
            }.frame(width: cell.width, height: cell.height)
        }
        func pet(_ gc: inout GraphicsContext, _ f: DeskPortal.Frame) {
            guard f.alpha > 0.01 else { return }
            let c = p(f.center)
            var g = gc
            g.opacity = Double(f.alpha)
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .degrees(f.rotation))
            g.scaleBy(x: f.scale * (1 + f.squash), y: f.scale * (1 - f.squash))
            let px = Sprite.pixels(.tool, tick: 2)
            g.translateBy(x: -48, y: -48)
            PetFace.draw(&g, size: CGSize(width: 96, height: 96), pixels: px, pose: PetPose())
        }
        let ceiling = anchor.y + 10
        let outTimes: [Double] = [0.04, 0.14, 0.26, 0.4, 0.55, 0.68, 0.8]
        let backTimes: [Double] = [0.08, 0.22, 0.36, 0.5, 0.6, 0.72, 0.95]
        let view = VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(Array(outTimes.enumerated()), id: \.offset) { _, t in
                    cellView(String(format: "salir  %.2f s", t)) { gc in
                        let item = Item(kind: .emerge(from: anchor, to: spot), start: 0, tint: tint, seed: 3, duration: 2)
                        FXView.draw(item, now: t, in: &gc, p)
                        pet(&gc, DeskPortal.emerge(from: anchor, to: spot, at: t, ceiling: ceiling))
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(Array(backTimes.enumerated()), id: \.offset) { _, t in
                    cellView(String(format: "volver  %.2f s", t)) { gc in
                        let item = Item(kind: .dive(from: spot, to: anchor), start: 0, tint: tint, seed: 3, duration: 2)
                        FXView.draw(item, now: t, in: &gc, p)
                        pet(&gc, DeskPortal.dive(from: spot, to: anchor, at: t, ceiling: ceiling))
                    }
                }
            }
        }.background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // MARK: dibujo

    fileprivate struct FXView: View {
        let model: Model
        var body: some View {
            TimelineView(.animation) { ctx in
                let _ = ctx.date
                Canvas { gc, size in
                    let now = ProcessInfo.processInfo.systemUptime
                    func p(_ a: CGPoint) -> CGPoint { CGPoint(x: a.x - model.origin.x, y: model.top - a.y) }
                    for item in model.items { Self.draw(item, now: now, in: &gc, p) }
                }
            }
            .allowsHitTesting(false)
        }

        static func tone(_ i: Int, _ tint: Color) -> Color { i == 1 ? .white : (i == 2 ? Color(hex: 0xFFE9A8) : tint) }

        static func spark(_ gc: inout GraphicsContext, _ s: DeskPortal.Spark, tint: Color, _ p: (CGPoint) -> CGPoint) {
            guard s.alpha > 0.01 else { return }
            let c = p(s.point), r = s.size
            // una estrella de cuatro puntas
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - r)); path.addLine(to: CGPoint(x: c.x + r * 0.28, y: c.y - r * 0.28))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y)); path.addLine(to: CGPoint(x: c.x + r * 0.28, y: c.y + r * 0.28))
            path.addLine(to: CGPoint(x: c.x, y: c.y + r)); path.addLine(to: CGPoint(x: c.x - r * 0.28, y: c.y + r * 0.28))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y)); path.addLine(to: CGPoint(x: c.x - r * 0.28, y: c.y - r * 0.28)); path.closeSubpath()
            gc.fill(path, with: .color(tone(s.tone, tint).opacity(Double(s.alpha))))
        }

        static func glow(_ gc: inout GraphicsContext, at c: CGPoint, radius: CGFloat, alpha: Double, tint: Color) {
            guard alpha > 0.01, radius > 1 else { return }
            let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
            gc.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [tint.opacity(alpha), tint.opacity(alpha * 0.35), tint.opacity(0)]), center: c, startRadius: 0, endRadius: radius))
        }

        static func ring(_ gc: inout GraphicsContext, at c: CGPoint, t: Double, radius: CGFloat, delay: Double = 0, tint: Color, line: CGFloat = 3) {
            guard let r = DeskPortal.ring(t: t, max: radius, delay: delay) else { return }
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r.radius, y: c.y - r.radius, width: r.radius * 2, height: r.radius * 2)), with: .color(tint.opacity(Double(r.alpha))), lineWidth: line * (1 - 0.6 * (r.radius / radius)))
        }

        static func dust(_ gc: inout GraphicsContext, at c: CGPoint, t: Double) {
            let k = DeskPortal.clamp01(t / 0.5)
            guard k < 1 else { return }
            for i in 0..<6 {
                let side: CGFloat = i % 2 == 0 ? 1 : -1, n = CGFloat(i / 2) + 1
                let x = c.x + side * (14 + 30 * n * DeskPortal.easeOut(k)), r = 7 + 5 * n * k
                gc.fill(Path(ellipseIn: CGRect(x: x - r, y: c.y + 36 - r * 0.6 - 6 * k, width: r * 2, height: r * 1.2)), with: .color(Color.white.opacity(Double((1 - k) * 0.28))))
            }
        }

        static func trail(_ gc: inout GraphicsContext, path: (TimeInterval) -> CGPoint, t: TimeInterval, tint: Color, _ p: (CGPoint) -> CGPoint) {
            for s in DeskPortal.trail(path: path, t: t) {
                let c = p(s.point)
                gc.fill(Path(ellipseIn: CGRect(x: c.x - s.size / 2, y: c.y - s.size / 2, width: s.size, height: s.size)), with: .color(tint.opacity(Double(s.alpha))))
            }
        }

        static func draw(_ item: Item, now: TimeInterval, in gc: inout GraphicsContext, _ p: (CGPoint) -> CGPoint) {
            let t = now - item.start
            guard t >= 0 else { return }
            let tint = item.tint
            switch item.kind {
            case .emerge(let from, let to):
                let a = p(from), b = p(to)
                // la isla se enciende, suelta dos ondas y una rafaga de chispas
                let g = t < 0.55 ? sin(t / 0.55 * .pi) : 0
                glow(&gc, at: a, radius: 62, alpha: 0.7 * g, tint: tint)
                ring(&gc, at: a, t: t, radius: 70, tint: tint); ring(&gc, at: a, t: t, radius: 96, delay: 0.09, tint: .white, line: 2)
                for s in DeskPortal.burst(center: from, t: t / 0.6, seed: item.seed, count: 16, radius: 80) { spark(&gc, s, tint: tint, p) }
                // la estela del vuelo
                if t < DeskPortal.emergeDuration { trail(&gc, path: { DeskPortal.emerge(from: from, to: to, at: $0, ceiling: DesktopPets.ceiling()).center }, t: t, tint: tint, p) }
                // y al caer: onda, chispas pequenas y polvo
                let tl = DeskPortal.emergeDuration * 0.66
                if t > tl {
                    ring(&gc, at: CGPoint(x: b.x, y: b.y + 40), t: t - tl, radius: 54, tint: tint, line: 2.5)
                    for s in DeskPortal.burst(center: CGPoint(x: to.x, y: to.y - 40), t: (t - tl) / 0.55, seed: item.seed &+ 5, count: 9, radius: 46) { spark(&gc, s, tint: tint, p) }
                    dust(&gc, at: b, t: t - tl)
                }
            case .pop(let at):
                let a = p(at)
                glow(&gc, at: a, radius: 56, alpha: 0.5 * max(0, 1 - t / 0.35), tint: tint)
                ring(&gc, at: a, t: t, radius: 62, tint: tint); ring(&gc, at: a, t: t, radius: 88, delay: 0.07, tint: .white, line: 2)
                for s in DeskPortal.burst(center: at, t: t / 0.5, seed: item.seed, count: 12, radius: 66) { spark(&gc, s, tint: tint, p) }
            case .dive(let from, let to):
                let b = p(to)
                if t < DeskPortal.diveDuration { trail(&gc, path: { DeskPortal.dive(from: from, to: to, at: $0, ceiling: DesktopPets.ceiling()).center }, t: t, tint: tint, p) }
                // la isla se enciende al acercarse y la recibe con ondas y chispas
                let near = DeskPortal.clamp01((t - DeskPortal.diveDuration * 0.55) / (DeskPortal.diveDuration * 0.45))
                glow(&gc, at: b, radius: 70, alpha: Double(near) * 0.45 * (t < DeskPortal.diveDuration ? 1 : max(0, 1 - (t - DeskPortal.diveDuration) / 0.6)), tint: tint)
                let ta = t - DeskPortal.diveDuration
                if ta > 0 {
                    ring(&gc, at: b, t: ta, radius: 84, tint: tint); ring(&gc, at: b, t: ta, radius: 110, delay: 0.1, tint: .white, line: 2)
                    for s in DeskPortal.burst(center: to, t: ta / 0.6, seed: item.seed, count: 18, radius: 92) { spark(&gc, s, tint: tint, p) }
                }
            }
        }
    }
}
