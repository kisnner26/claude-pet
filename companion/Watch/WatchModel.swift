import Combine
import CoreMotion
import Foundation
import VistoCore
import WatchConnectivity
import WatchKit

/// El reloj intenta hablar directo con claude pet por Wi-Fi; si no puede, usa lo que le retransmite el iPhone.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    static let shared = WatchModel()
    let client = VistoClient()
    /// Girar la muñeca dos veces con fuerza deniega el permiso que tengas delante. Solo deniega: es lo seguro. Empieza apagado.
    @Published var wristDeny: Bool = UserDefaults.standard.bool(forKey: "wristDeny") { didSet { UserDefaults.standard.set(wristDeny, forKey: "wristDeny"); syncMotion() } }
    private let motion = CMMotionManager()
    private var flicks: [Date] = []
    private var lastSign = 0.0
    @Published var code: String? = VistoStore.code
    @Published var language: Lang = L.current
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
        client.configure(code: code, deviceName: "Apple Watch", relay: VistoStore.relay)
        client.start()
        let s = WCSession.default; s.delegate = self; s.activate(); session = s
        QuickDecision.decide = { allow in await WatchModel.shared.quickDecide(allow: allow) }
        QuickDecision.focus = { on in await MainActor.run { WatchModel.shared.setFocus(on) }; return on ? L.tr("Modo foco activado.") : L.tr("Modo foco apagado.") }
    }

    func quickDecide(allow: Bool) async -> String {
        start()
        for _ in 0..<60 where asks.isEmpty { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard let ask = asks.last(where: { allow ? $0.canAllow : true }) else { return asks.isEmpty ? L.tr("No hay permisos pendientes.") : L.tr("Lo pendiente es de riesgo alto: apruébalo en la Mac.") }
        answer(ask, allow: allow)
        return allow ? L.t("Permitido: \(ask.tool).", "Allowed: \(ask.tool).") : L.t("Denegado: \(ask.tool).", "Denied: \(ask.tool).")
    }

    // MARK: gesto de muñeca

    /// El giroscopio solo corre mientras hay algo que denegar y el gesto está activo: no gasta batería el resto del tiempo.
    func syncMotion() {
        let want = wristDeny && !asks.isEmpty
        if want, !motion.isGyroActive, motion.isGyroAvailable {
            motion.gyroUpdateInterval = 1.0 / 30
            motion.startGyroUpdates(to: .main) { [weak self] d, _ in
                guard let self, let r = d?.rotationRate else { return }
                // giro de muñeca: velocidad angular fuerte sobre el eje del antebrazo, de ida y de vuelta
                let v = r.y
                guard abs(v) > 4.5 else { return }
                let sign: Double = v > 0 ? 1 : -1
                let now = Date()
                if sign != self.lastSign { self.flicks.append(now); self.lastSign = sign }
                self.flicks.removeAll { now.timeIntervalSince($0) > 0.8 }
                if self.flicks.count >= 3, let ask = self.asks.first { self.flicks = []; self.answer(ask, allow: false) }
            }
        } else if !want, motion.isGyroActive { motion.stopGyroUpdates(); flicks = []; lastSign = 0 }
    }

    func answer(_ ask: Ask, allow: Bool) {
        WKInterfaceDevice.current().play(allow ? .success : .failure)
        if client.isConnected { client.answer(ask.id, allow: allow) }
        else if let s = session, s.isReachable { s.sendMessage(["answer": [ask.id, allow]], replyHandler: nil, errorHandler: nil) }
        relayed.asks.removeAll { $0.id == ask.id }
        syncMotion()
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
        if let l = ctx["lang"] as? String, let lang = Lang(rawValue: l), lang != L.current { L.set(lang); language = lang }
        if let r = ctx["relay"] as? String {
            let p = r.split(separator: ":").map(String.init)
            VistoStore.relay = p.count == 3 ? RelayEndpoint(host: p[0], port: UInt16(p[1]) ?? 7777, tls: p[2] == "1") : nil
        }
        if let c = ctx["code"] as? String {
            let v = c.isEmpty ? nil : c
            VistoStore.code = v; code = v
            client.configure(code: v, deviceName: "Apple Watch", relay: VistoStore.relay)
            if v == nil { client.stop() } else { client.start() }
        }
        if let d = ctx["snap"] as? Data, let new = try? JSONDecoder().decode(VistoSnapshot.self, from: d) {
            let old = Set(relayed.asks.map(\.id) + relayed.questions.map(\.id))
            relayed = new
            syncMotion()
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
