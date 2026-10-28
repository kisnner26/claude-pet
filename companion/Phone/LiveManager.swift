import ActivityKit
import Foundation
import VistoCore

/// Mantiene la Isla Dinámica al día: aparece cuando un agente trabaja o espera tu respuesta y se va cuando todo queda en calma.
/// Las actualizaciones las hace la app, así que se mueven mientras Visto está activa o iOS le da tiempo; sin notificaciones push, no hay más.
@MainActor
final class LiveManager {
    private var activity: Activity<VistoActivityAttributes>?
    private var idleSince: Date?

    func update(_ client: VistoClient) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let lead = client.agents.first(where: \.isBusy) ?? client.agents.first(where: { $0.state == "waiting" }) ?? client.agents.first
        let ask = client.asks.first
        let busy = lead?.isBusy == true || lead?.state == "waiting" || ask != nil || !client.questions.isEmpty
        guard let lead, client.isConnected else { end(); return }
        if !busy {
            // un respiro antes de retirarla, para ver el «listo»
            if idleSince == nil { idleSince = Date() }
            if Date().timeIntervalSince(idleSince ?? Date()) > 25 { end() }
            if lead.state != "done" && lead.state != "error" { return }
        } else { idleSince = nil }
        let state = VistoActivityAttributes.ContentState(agent: lead.agent, state: lead.state, project: lead.project, since: lead.since,
                                                          pending: client.asks.count + client.questions.count, askID: ask?.id, askTool: ask?.tool,
                                                          canAllow: ask?.canAllow ?? true, context: lead.contextRemaining)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(180))
        if let a = activity, a.activityState == .active {
            Task { await a.update(content) }
        } else {
            activity = try? Activity.request(attributes: VistoActivityAttributes(host: client.hostName ?? "Mac"), content: content, pushType: nil)
        }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil; idleSince = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
