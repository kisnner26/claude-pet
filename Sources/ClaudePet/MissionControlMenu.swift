import SwiftUI

struct MissionControlMenu: View {
    @ObservedObject var control: MissionControl

    private func actions(for insight: MissionInsight) -> [MissionAction] {
        switch insight.id {
        case "recovery": return control.recovery == nil ? [] : [.openDiff, .clearRecovery]
        case "conflicts", "checkpoint", "staging", "untracked": return [.refreshGit, .openDiff]
        default: return []
        }
    }

    var body: some View {
        Group {
            Text(control.collision ? "posible colisión: claude y codex en el mismo proyecto" : "coordinación: sin colisiones")
            Text("git: \(control.git.label)")
            Text("sesión: \(control.focusLabel)")
            Button("actualizar salud git") { control.refreshGit() }
            Button("abrir carpeta del proyecto") { control.openWorkspace() }
            Button("copiar informe técnico") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.diagnosticReport, forType: .string)
            }
            Button("copiar actividad reciente") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.timelineExport, forType: .string)
            }
            Divider()
            Menu("panel operativo") {
                ForEach(control.insights) { insight in
                    Menu(insight.title) {
                        Text(insight.detail)
                        ForEach(actions(for: insight)) { action in
                            Button(action.title) { control.perform(action) }
                        }
                    }
                }
            }
            Picker("filtrar actividad", selection: $control.timelineFilter) {
                ForEach(MissionAgentFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            if let capsule = control.recovery {
                Divider()
                Text("cápsula de recuperación: \(capsule.project.isEmpty ? "proyecto" : capsule.project)")
                Text(capsule.createdAt, format: .dateTime.hour().minute())
                Text("git: \(capsule.health.label)")
                Button("abrir diff de recuperación") { DiffOpener.open(workspace: capsule.workspace) }
                Button("descartar cápsula") { control.clearRecovery() }
            }
            if !control.timeline.isEmpty {
                Divider()
                ForEach(control.filteredTimeline.prefix(6)) { item in
                    HStack {
                        Text(item.at, format: .dateTime.hour().minute())
                        Text("\(item.agent): \(item.state.label.lowercased())\(item.project.isEmpty ? "" : " · \(item.project)")")
                    }
                }
            }
        }
    }
}
