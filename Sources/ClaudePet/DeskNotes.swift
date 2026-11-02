import SwiftUI
import AppKit

/// Un aviso corto sobre la cabeza de una mascota del escritorio ("su ventana esta en otro espacio").
@MainActor
final class DeskNotes {
    static let shared = DeskNotes()

    private final class Model: ObservableObject { @Published var text = ""; @Published var tint = Color(hex: 0xE0824F) }
    private var panels: [IslandAgentTab: (panel: NSPanel, model: Model)] = [:]

    func update(notes: [IslandAgentTab: String], centers: [IslandAgentTab: CGPoint]) {
        for agent in IslandAgentTab.allCases {
            guard let text = notes[agent], let c = centers[agent] else { panels[agent]?.panel.orderOut(nil); continue }
            let entry = panels[agent] ?? makePanel(agent)
            if entry.model.text != text { entry.model.text = text }
            entry.panel.setFrameOrigin(NSPoint(x: c.x - 90, y: c.y + 46))
            if !entry.panel.isVisible { entry.panel.orderFrontRegardless() }
        }
    }

    func hideAll() { for e in panels.values { e.panel.orderOut(nil) } }

    private func makePanel(_ agent: IslandAgentTab) -> (panel: NSPanel, model: Model) {
        let model = Model()
        model.tint = Color(hex: agent == .claude ? 0xE0824F : 0x5270E8)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 26), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: NoteView(model: model))
        panels[agent] = (p, model)
        return (p, model)
    }

    private struct NoteView: View {
        @ObservedObject var model: Model
        var body: some View {
            Text(model.text).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.black).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(model.tint))
                .frame(width: 180, height: 26)
        }
    }
}
