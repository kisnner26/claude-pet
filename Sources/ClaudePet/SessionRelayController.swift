import Foundation
import SwiftUI

/// Coordina el relevo manual: elegir proyecto, aportar contexto, previsualizar y guardar.
@MainActor
final class SessionRelayController: ObservableObject {
    @Published private(set) var latest: SessionCapsule?
    @Published private(set) var latestURL: URL?
    private let interaction: SessionRelayInteraction

    init(interaction: SessionRelayInteraction? = nil) { self.interaction = interaction ?? .live }

    func prepare(source: Agent, workspace: String, context: String, state: PetState) throws -> (SessionCapsule, String) {
        let selected = try SessionCapsuleFactory.validateWorkspace(workspace)
        let capsule = try SessionCapsuleFactory.make(source: source, workspace: selected, project: "",
                                                     task: context, state: state, health: GitPulse.scan(selected))
        return (capsule, SessionCapsulePrompt.build(capsule, destination: source.other))
    }

    @discardableResult
    func saveAndContinue(_ capsule: SessionCapsule, prompt: String) throws -> URL {
        let url = try SessionCapsuleStore.save(capsule)
        latest = capsule
        latestURL = url
        interaction.copy(prompt)
        interaction.open(capsule.source.other)
        return url
    }

    func copyAndContinue(_ capsule: SessionCapsule) {
        interaction.copy(SessionCapsulePrompt.build(capsule, destination: capsule.source.other))
        latest = capsule
        interaction.open(capsule.source.other)
    }

    func chooseProject(suggested: String) -> String? { interaction.chooseWorkspace(suggested) }

    func create(source: Agent, workspace: String, task: String, state: PetState) {
        do {
            guard let chosen = interaction.chooseWorkspace(workspace) else { return }
            let selected = try SessionCapsuleFactory.validateWorkspace(chosen)
            let sourceTask = source == .claude && selected == URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL.path ? task : ""
            guard let context = interaction.editContext(source, URL(fileURLWithPath: selected).lastPathComponent, sourceTask) else { return }
            let capsule = try SessionCapsuleFactory.make(source: source, workspace: selected, project: "",
                                                         task: context, state: state, health: GitPulse.scan(selected))
            let prompt = SessionCapsulePrompt.build(capsule, destination: source.other)
            guard interaction.preview(prompt, "revisar relevo de \(capsule.project)", "guardar relevo") else { return }
            let url = try SessionCapsuleStore.save(capsule)
            latest = capsule
            latestURL = url
            interaction.copy(prompt)
            interaction.showSaved(url, source.other)
        } catch {
            interaction.inform("claude pet", error.localizedDescription)
        }
    }

    func continueLatest(in destination: Agent) {
        do {
            let item = try SessionCapsuleStore.latest()
            let prompt = SessionCapsulePrompt.build(item.capsule, destination: destination)
            guard interaction.preview(prompt, "continuar en \(destination.displayName)", "copiar y abrir") else { return }
            interaction.copy(prompt)
            latest = item.capsule
            latestURL = item.url
            interaction.open(destination)
        } catch {
            interaction.inform("claude pet", error.localizedDescription)
        }
    }

    func revealLatest() {
        do { interaction.reveal(try SessionCapsuleStore.latest().url) }
        catch { interaction.inform("claude pet", error.localizedDescription) }
    }
}
