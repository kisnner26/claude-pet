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
            Text(control.gitBreakdown)
            Button("copiar estado de git") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString("rama: \(control.git.branch.isEmpty ? "sin rama" : control.git.branch)\n\(control.git.label)\n\(control.gitBreakdown)", forType: .string)
            }
            if !control.git.branch.isEmpty { Text("rama: \(control.git.branch)") }
            Text("sesión: \(control.focusLabel)")
            Text("foco: \(control.brief.title.lowercased())")
            if !control.topTools.isEmpty {
                Text("herramientas: " + control.topTools.map { "\($0.name) ×\($0.count)" }.joined(separator: " · "))
            }
            Button("copiar foco operativo") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(control.brief.title)\n\(control.brief.detail)", forType: .string)
            }
            Button("actualizar salud git") { control.refreshGit() }
            Button("abrir carpeta del proyecto") { control.openWorkspace() }
            Button("copiar informe técnico") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.diagnosticReport, forType: .string)
            }
            Button("copiar actividad reciente") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.timelineExport, forType: .string)
            }
            Button("copiar actividad como markdown") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.timelineMarkdown, forType: .string)
            }
            Button("copiar actividad como json") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(control.timelineJSON, forType: .string)
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
            Picker("ordenar actividad", selection: $control.timelineOrder) {
                ForEach(MissionTimelineOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("filtrar proyecto", selection: Binding(get: { control.timelineProject.isEmpty ? "todos" : control.timelineProject }, set: { control.timelineProject = $0 == "todos" ? "" : $0 })) {
                ForEach(control.timelineProjects, id: \.self) { Text($0).tag($0) }
            }
            Text(control.filteredTimelineLabel)
            Text(control.timelineAgentCounts)
            Text("último evento: \(control.lastActivityLabel)")
            Button("limpiar actividad reciente", systemImage: "trash") { control.clearTimeline() }
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
