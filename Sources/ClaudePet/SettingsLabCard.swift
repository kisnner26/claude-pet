import SwiftUI
import AppKit

/// El laboratorio: galaxia, ciudad y radar vienen incluidos y se abren con un clic. Necesitan node 20 o superior.
struct LabCard: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var lab = LabLauncher.shared
    @State private var message = ""
    @State private var busy: LabTool?

    var body: some View {
        SCard(title: "laboratorio", footer: lab.available ? "programas incluidos, sin dependencias: escuchan solo en tu Mac (127.0.0.1) y no escriben nada. se cierran al salir de claude pet." : "necesitan node 20 o superior (brew install node).") {
            ForEach(Array(LabTool.allCases.enumerated()), id: \.element) { i, tool in
                if i > 0 { SDivider() }
                SRow(title: tool.title, detail: lab.urls[tool].map { "abierta en el puerto \($0.port ?? 0)" } ?? tool.detail) {
                    HStack(spacing: 8) {
                        if lab.isRunning(tool) { SButton(title: "detener", symbol: "stop.fill") { lab.stop(tool) } }
                        SButton(title: busy == tool ? "abriendo…" : "abrir", symbol: tool.symbol) { run(tool) }
                            .disabled(!lab.available || busy != nil)
                    }
                }
            }
            if !message.isEmpty { SDivider(); SRow(title: message) { EmptyView() } }
        }
    }

    private func run(_ tool: LabTool) {
        busy = tool; message = ""
        let ws = store.mission.workspace
        Task { @MainActor in
            if case .failure(let why) = await lab.open(tool, workspace: ws) { message = why }
            busy = nil
        }
    }
}
