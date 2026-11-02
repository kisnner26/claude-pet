import SwiftUI
import AppKit

/// El archivo que la mascota lleva: aparece sobre su cabeza con el icono de su tipo y su nombre y vuela hasta el editor.
@MainActor
final class FileFlights {
    static let shared = FileFlights()

    private final class Model: ObservableObject {
        @Published var icon = NSImage()
        @Published var name = ""
        @Published var scale: CGFloat = 1
        @Published var alpha: CGFloat = 1
        @Published var tint = Color(hex: 0xE0824F)
    }

    private struct Job { var flight: FileFlight; var icon: NSImage; var name: String; var tint: Color }
    private var queue: [Job] = []
    private var current: Job?
    private var seen: Set<String> = []
    private var primed = false
    private var panel: NSPanel?
    private let model = Model()

    private static func key(_ s: IslandStep) -> String { "\(s.agent)|\(s.tool)|\(s.target)|\(Int(s.at.timeIntervalSince1970 * 10))" }

    /// `centers`: donde esta cada mascota ahora (centro del panel). Se llama en cada tick del escritorio.
    func tick(now: TimeInterval, store: PetStore, centers: [IslandAgentTab: CGPoint], windows: [DeskWindow], animated: Bool) {
        let steps = store.recentIslandSteps
        if !primed { seen = Set(steps.map(Self.key)); primed = true }      // lo que ya habia no se repite
        if animated {
            let host = WindowCatalog.agentWindow(project: store.terminalProject, in: windows)
            for step in steps where seen.insert(Self.key(step)).inserted {
                guard now > 0, Date().timeIntervalSince(step.at) < 6, let file = FileCarry.editedFile(tool: step.tool, target: step.target),
                      let agent = IslandAgentTab(rawValue: step.agent), let pet = centers[agent],
                      let to = FileCarry.destination(file: file.name, project: store.terminalProject, windows: windows, host: host) else { continue }
                let icon = NSWorkspace.shared.icon(forFileType: file.ext.isEmpty ? "txt" : file.ext)
                icon.size = NSSize(width: 34, height: 34)
                queue.append(Job(flight: FileFlight(from: CGPoint(x: pet.x, y: pet.y + 58), to: to, start: now), icon: icon, name: String(file.name.prefix(22)),
                                 tint: Color(hex: agent == .claude ? 0xE0824F : 0x5270E8)))
                if queue.count > 3 { queue.removeFirst() }
            }
        } else { for s in steps { seen.insert(Self.key(s)) } }
        advance(now: now)
    }

    private func advance(now: TimeInterval) {
        if current == nil, !queue.isEmpty {
            var job = queue.removeFirst()
            job.flight.start = now            // el vuelo empieza cuando le toca, no cuando se encolo
            current = job
            model.icon = job.icon; model.name = job.name; model.tint = job.tint
            ensurePanel()
        }
        guard let job = current else { return }
        let f = job.flight.frame(at: now)
        if f.done { current = nil; panel?.orderOut(nil); return }
        model.scale = f.scale; model.alpha = f.alpha
        panel?.setFrameOrigin(NSPoint(x: f.point.x - 70, y: f.point.y - 30))
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    func stop() { queue.removeAll(); current = nil; panel?.orderOut(nil) }

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 140, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: FlightView(model: model))
        panel = p
    }

    private struct FlightView: View {
        @ObservedObject var model: Model
        var body: some View {
            VStack(spacing: 3) {
                Image(nsImage: model.icon).resizable().interpolation(.high).frame(width: 34, height: 34).shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                Text(model.name).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundColor(.black).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(model.tint))
            }
            .scaleEffect(model.scale).opacity(model.alpha)
            .frame(width: 140, height: 60)
        }
    }
}
