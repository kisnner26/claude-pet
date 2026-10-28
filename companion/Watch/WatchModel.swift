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
    @Published private(set) var relayed = VistoSnapshot()
    @Published private(set) var reachable = false
    private var session: WCSession?
    private var started = false

    /// Lo directo manda; si no hay conexión se usa lo del iPhone.
    var snap: VistoSnapshot { client.isConnected ? client.snapshot : relayed }
    var asks: [Ask] { snap.asks.filter { !$0.isExpired() } }
    var connected: Bool { client.isConnected || reachable }

    func start() {
        guard !started else { return }
        started = true
        client.onNewAsk = { _ in WKInterfaceDevice.current().play(.notification) }
        client.onNewQuestion = { _ in WKInterfaceDevice.current().play(.notification) }
        client.onEvent = { kind, _, _, _ in WKInterfaceDevice.current().play(kind == "done" ? .success : .failure) }
        client.configure(code: code, deviceName: "Apple Watch")
        client.start()
        let s = WCSession.default; s.delegate = self; s.activate(); session = s
    }

    func answer(_ ask: Ask, allow: Bool) {
        WKInterfaceDevice.current().play(allow ? .success : .failure)
        if client.isConnected { client.answer(ask.id, allow: allow) }
        else if let s = session, s.isReachable { s.sendMessage(["answer": [ask.id, allow]], replyHandler: nil, errorHandler: nil) }
        relayed.asks.removeAll { $0.id == ask.id }
    }

    func reply(_ q: QAsk, picks: [[Int]]) {
        WKInterfaceDevice.current().play(.success)
        if client.isConnected { client.reply(q.id, picks: picks) }
        else if let s = session, s.isReachable, let d = try? JSONEncoder().encode(WatchReply(id: q.id, picks: picks)) { s.sendMessage(["reply": d], replyHandler: nil, errorHandler: nil) }
        relayed.questions.removeAll { $0.id == q.id }
    }

    func setFocus(_ on: Bool) {
        WKInterfaceDevice.current().play(.click)
        if client.isConnected { client.setFocus(on) } else if let s = session, s.isReachable { s.sendMessage(["focus": on], replyHandler: nil, errorHandler: nil) }
        relayed.focus = on
    }

    private func apply(_ ctx: [String: Any]) {
        if let c = ctx["code"] as? String {
            let v = c.isEmpty ? nil : c
            VistoStore.code = v; code = v
            client.configure(code: v, deviceName: "Apple Watch")
            if v == nil { client.stop() } else { client.start() }
        }
        if let d = ctx["snap"] as? Data, let new = try? JSONDecoder().decode(VistoSnapshot.self, from: d) {
            let old = Set(relayed.asks.map(\.id) + relayed.questions.map(\.id))
            relayed = new
            if !client.isConnected, (new.asks.map(\.id) + new.questions.map(\.id)).contains(where: { !old.contains($0) }) { WKInterfaceDevice.current().play(.notification) }
        }
        if let e = ctx["event"] as? [Any], let kind = e.first as? String, !client.isConnected { WKInterfaceDevice.current().play(kind == "done" ? .success : .failure) }
    }
}

struct WatchReply: Codable { var id: String; var picks: [[Int]] }

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
