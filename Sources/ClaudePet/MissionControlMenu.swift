import SwiftUI

struct MissionControlMenu: View {
    @ObservedObject var control: MissionControl

    var body: some View {
        Group {
            Text(control.collision ? "posible colisión: claude y codex en el mismo proyecto" : "coordinación: sin colisiones")
            Text("git: \(control.git.label)")
            Text("sesión: \(control.focusLabel)")
            Button("actualizar salud git") { control.refreshGit() }
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
                ForEach(control.timeline.prefix(6)) { item in
                    HStack {
                        Text(item.at, format: .dateTime.hour().minute())
                        Text("\(item.agent): \(item.state.label.lowercased())\(item.project.isEmpty ? "" : " · \(item.project)")")
                    }
                }
            }
        }
    }
}
