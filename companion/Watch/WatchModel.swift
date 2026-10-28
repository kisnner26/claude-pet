import Combine
import Foundation
import VistoCore
import WatchConnectivity
import WatchKit

/// El reloj intenta hablar directo con claude pet por Wi-Fi; si no puede, usa lo que le retransmite el iPhone.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    let client = VistoClient()
    @Published var code: String? = VistoStore.code
    @Published private(set) var relayed: [Ask] = []
    @Published private(set) var relayedPlan: PlanSnapshot?
    @Published private(set) var reachable = false
    private var session: WCSession?
    private var started = false

    /// Lo directo manda; si no hay conexión se usa lo del iPhone.
    var asks: [Ask] { (client.isConnected ? client.asks : relayed).filter { !$0.isExpired() } }
    var plan: PlanSnapshot? { client.isConnected ? client.plan : relayedPlan }
    var connected: Bool { client.isConnected || reachable }

    func start() {
        guard !started else { return }
        started = true
        client.onNewAsk = { _ in WKInterfaceDevice.current().play(.notification) }
        client.configure(code: code, deviceName: "Apple Watch")
        client.start()
        let s = WCSession.default; s.delegate = self; s.activate(); session = s
    }

    func answer(_ ask: Ask, allow: Bool) {
        WKInterfaceDevice.current().play(allow ? .success : .failure)
        if client.isConnected { client.answer(ask.id, allow: allow) }
        else if let s = session, s.isReachable { s.sendMessage(["answer": [ask.id, allow]], replyHandler: nil, errorHandler: nil) }
        relayed.removeAll { $0.id == ask.id }
    }

    private func apply(_ ctx: [String: Any]) {
        if let c = ctx["code"] as? String {
            let v = c.isEmpty ? nil : c
            VistoStore.code = v; code = v
            client.configure(code: v, deviceName: "Apple Watch")
            if v == nil { client.stop() } else { client.start() }
        }
        if let d = ctx["asks"] as? Data, let list = try? JSONDecoder().decode([Ask].self, from: d) {
            let old = Set(relayed.map(\.id))
            relayed = list
            if !client.isConnected, list.contains(where: { !old.contains($0.id) }) { WKInterfaceDevice.current().play(.notification) }
        }
        if let d = ctx["plan"] as? Data { relayedPlan = try? JSONDecoder().decode(PlanSnapshot?.self, from: d) ?? nil }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext, r = session.isReachable
        Task { @MainActor in
            self.reachable = r; self.apply(ctx)
            if r { session.sendMessage(["needState": 1], replyHandler: nil, errorHandler: nil) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) { Task { @MainActor in self.apply(context) } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.apply(message) } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r; if r { session.sendMessage(["needState": 1], replyHandler: nil, errorHandler: nil) } }
    }
}
