import AppKit
import SwiftUI

/// Une el traspaso con la interfaz: pide confirmacion antes de enviar nada, muestra el avance en la
/// burbuja y deja a mano el resultado. No decide nada por su cuenta.
@MainActor
final class HandoffController: ObservableObject {
    @Published private(set) var job: ReviewJob?
    @Published private(set) var notice: Activity?
    @Published private(set) var noticeState: PetState = .tool
    @Published private(set) var lastResult: URL?
    private var noticeToken = 0

    var running: Bool { job?.state == .running }

    /// Pregunta, y solo si el usuario acepta lanza la revision. Devuelve el motivo si no se puede.
    @discardableResult
    func requestReview(reviewer: Agent, workspace: String, project: String, task: String, confirm: Bool = true) -> String? {
        guard !running else { return "ya hay una revisión en curso" }
        switch Handoff.prepare(workspace: workspace, author: reviewer.other, project: project, task: task) {
        case .failure(let error):
            if confirm { inform("claude pet", error.message) }
            return error.message
        case .success(let ready):
            if confirm && !approve(reviewer: reviewer, project: project.isEmpty ? workspace : project, bytes: ready.bytes) { return "cancelado" }
            let job = ReviewJob(reviewer: reviewer, workspace: workspace, project: project, prompt: ready.prompt)
            self.job = job
            job.onChange = { [weak self, weak job] state in
                Task { @MainActor in if let job { self?.changed(job, state) } }
            }
            job.start()
            return nil
        }
    }

    func cancel() { job?.cancel() }

    private func changed(_ job: ReviewJob, _ state: ReviewJob.State) {
        guard job === self.job else { return }
        noticeToken += 1
        switch state {
        case .running:
            notice = Activity(title: "\(job.reviewer.displayName) revisa lo de \(job.author.displayName)", subtitle: "solo lectura", origin: "")
            noticeState = .tool
        case .done:
            lastResult = job.result
            if let url = job.result { NSWorkspace.shared.open(url) }
            show(Activity(title: "revisión lista", subtitle: job.reviewer.displayName, origin: ""), state: .done)
        case .failed(let message):
            show(Activity(title: "revisión fallida", subtitle: message, origin: ""), state: .error)
        case .cancelled, .idle:
            notice = nil
        }
    }

    private func show(_ activity: Activity, state: PetState) {
        notice = activity
        noticeState = state
        let token = noticeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.noticeToken == token, self.job?.state != .running else { return }
            self.notice = nil
        }
    }

    /// Crea un worktree para que el agente indicado trabaje aparte; deja la ruta en el portapapeles.
    func isolate(agent: Agent, workspace: String) {
        do {
            let made = try Handoff.createWorktree(workspace: workspace, agent: agent)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(made.path, forType: .string)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: made.path)])
            inform("claude pet", "Worktree creado en la rama \(made.branch).\n\(made.path)\nLa ruta está en el portapapeles: abre \(agent.rawValue) ahí.")
        } catch let error as HandoffError {
            inform("claude pet", error.message)
        } catch {
            inform("claude pet", error.localizedDescription)
        }
    }

    private func approve(reviewer: Agent, project: String, bytes: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Enviar el diff a \(reviewer.displayName)?"
        alert.informativeText = "Se enviará el diff sin commitear de «\(project)» (unos \(bytes / 1024 + 1) KB), junto con tu última tarea, a \(reviewer.rawValue) (\(reviewer.provider)) en modo solo lectura. No modificará nada."
        alert.addButton(withTitle: "Enviar")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

struct HandoffMenu: View {
    @ObservedObject var store: PetStore
    @ObservedObject var handoff: HandoffController
    @ObservedObject var control: MissionControl

    var body: some View {
        Group {
            if handoff.running, let job = handoff.job {
                Text("\(job.reviewer.displayName) está revisando…")
                Button("cancelar revisión") { handoff.cancel() }
            } else {
                ForEach(Agent.allCases, id: \.self) { reviewer in
                    Button("pedir a \(reviewer.rawValue) que revise lo de \(reviewer.other.rawValue)") { store.requestReview(by: reviewer) }
                        .disabled(control.workspace.isEmpty || AgentLocator.find(reviewer.rawValue) == nil)
                }
                if control.workspace.isEmpty { Text("aún no conozco el proyecto (usa claude una vez)") }
            }
            if let url = handoff.lastResult { Button("abrir la última revisión") { NSWorkspace.shared.open(url) } }
            if control.collision {
                Divider()
                Text("colisión: claude y codex en \(control.project)")
                Button("pausar a claude hasta mi próximo mensaje") { store.pauseClaude() }
                ForEach(Agent.allCases, id: \.self) { agent in
                    Button("worktree aislado para \(agent.rawValue)") { handoff.isolate(agent: agent, workspace: control.workspace) }
                }
            }
        }
    }
}
