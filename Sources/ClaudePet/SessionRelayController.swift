import AppKit
import SwiftUI

/// Coordina el relevo manual: crear, previsualizar y copiar contexto antes de abrir el destino.
@MainActor
final class SessionRelayController: ObservableObject {
    @Published private(set) var latest: SessionCapsule?
    @Published private(set) var latestURL: URL?

    func create(source: Agent, workspace: String, project: String, task: String, state: PetState, health: GitHealth) {
        do {
            let selected = workspace.isEmpty ? chooseWorkspace() : workspace
            guard let selected else { return }
            let selectedProject = project.isEmpty ? URL(fileURLWithPath: selected).lastPathComponent : project
            let selectedHealth = workspace.isEmpty ? GitPulse.scan(selected) : health
            let capsule = try SessionCapsuleFactory.make(source: source, workspace: selected, project: selectedProject, task: task, state: state, health: selectedHealth)
            let url = try SessionCapsuleStore.save(capsule)
            latest = capsule; latestURL = url
            copy(SessionCapsulePrompt.build(capsule, destination: source.other))
            inform("relevo listo", "se guardó localmente y el contexto quedó copiado. revísalo antes de pegarlo en \(source.other.displayName).")
        } catch {
            inform("claude pet", error.localizedDescription)
        }
    }

    func continueLatest(in destination: Agent) {
        do {
            let item: (capsule: SessionCapsule, url: URL)
            if let latest, let latestURL { item = (latest, latestURL) } else { item = try SessionCapsuleStore.latest() }
            guard approve(capsule: item.capsule, destination: destination) else { return }
            copy(SessionCapsulePrompt.build(item.capsule, destination: destination))
            latest = item.capsule; latestURL = item.url
            open(destination)
        } catch {
            inform("claude pet", error.localizedDescription)
        }
    }

    private func approve(capsule: SessionCapsule, destination: Agent) -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿continuar en \(destination.displayName)?"
        alert.informativeText = "Se copiará una cápsula de relevo de «\(capsule.project)» al portapapeles y se abrirá \(destination.displayName). Al pegarla, su contenido se enviará a \(destination.provider). No incluye la transcripción completa ni credenciales."
        alert.addButton(withTitle: "copiar y abrir")
        alert.addButton(withTitle: "cancelar")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Codex no expone una carpeta activa a la mascota. En ese caso el usuario la elige una vez,
    /// sin leer sesiones privadas ni depender de que Claude esté abierto.
    private func chooseWorkspace() -> String? {
        let panel = NSOpenPanel()
        panel.message = "elige la carpeta del proyecto para este relevo"
        panel.prompt = "usar carpeta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func open(_ agent: Agent) {
        let bundle = agent == .claude ? AppPresence.claudeBundle : AppPresence.codexBundle
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
