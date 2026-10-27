import SwiftUI
import AppKit

/// Estado observable que dibuja la isla; el controlador solo actualiza estos valores.
@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .hidden
    @Published var reason: IslandReason = .none
    @Published var size = CGSize(width: 184, height: 38)
    @Published var hasNotch = true
    @Published var placement: IslandPlacement = .top
    /// La barra de menus esta oculta (autoocultar o pantalla completa): en reposo no se dibuja nada.
    @Published var menuBarHidden = false
    @Published var countdown: Double?
    @Published var gaze = CGPoint.zero
    @Published var hover = false
    var pokes: [TimeInterval] = []
    var hopStart: TimeInterval?
    var greetUntil: TimeInterval = 0
    var onPetClick: () -> Void = {}

    func poke() {
        pokes.append(ProcessInfo.processInfo.systemUptime)
        if pokes.count > 6 { pokes.removeFirst(pokes.count - 6) }
        onPetClick()
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Que esquinas se redondean: las que miran hacia dentro de la pantalla, o todas si flota.
enum IslandCorners { case bottom, top, leading, all }

extension IslandPlacement {
    var corners: IslandCorners { switch self { case .top: return .bottom; case .bottom: return .top; case .side: return .leading; case .floating: return .all } }
}

struct IslandShape: Shape {
    var radius: CGFloat
    var corners: IslandCorners = .bottom
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        let rad = min(radius, r.width / 2, r.height / 2)
        let tl = corners == .top || corners == .leading || corners == .all ? rad : 0
        let tr = corners == .top || corners == .all ? rad : 0
        let bl = corners == .bottom || corners == .leading || corners == .all ? rad : 0
        let br = corners == .bottom || corners == .all ? rad : 0
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        if tr > 0 { p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tr), control: CGPoint(x: r.maxX, y: r.minY)) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        if br > 0 { p.addQuadCurve(to: CGPoint(x: r.maxX - br, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY)) }
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        if bl > 0 { p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bl), control: CGPoint(x: r.minX, y: r.maxY)) }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        if tl > 0 { p.addQuadCurve(to: CGPoint(x: r.minX + tl, y: r.minY), control: CGPoint(x: r.minX, y: r.minY)) }
        p.closeSubpath()
        return p
    }
}
