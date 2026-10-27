import SwiftUI
import AppKit

/// Estado observable que dibuja la isla; el controlador solo actualiza estos valores.
@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .hidden
    @Published var reason: IslandReason = .none
    @Published var size = CGSize(width: 184, height: 38)
    @Published var hasNotch = true
    @Published var countdown: Double?
    @Published var gaze = CGPoint.zero
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

struct IslandShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
