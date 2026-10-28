import Combine
import LocalAuthentication
import Foundation
import UIKit
import UserNotifications
import VistoCore
import WatchConnectivity

/// Cliente de claude pet en el iPhone, avisos locales con botones y puente hacia el reloj.
@MainActor
final class PhoneModel: NSObject, ObservableObject {
    static let shared = PhoneModel()
    let client = VistoClient()
    @Published var code: String? = VistoStore.code
    @Published var watchPaired = false
    @Published private(set) var history: [DecisionRecord] = DecisionRecord.load()
    private var started = false
    private let live = LiveManager()
    @Published var requireFaceID: Bool = UserDefaults.standard.bool(forKey: "auth.faceid") { didSet { UserDefaults.standard.set(requireFaceID, forKey: "auth.faceid") } }
    /// Relay para usar Visto fuera de la red local (opcional). Al cambiarlo se reconecta y se avisa al reloj.
    @Published var relay: RelayEndpoint? = VistoStore.relay {
        didSet {
            VistoStore.relay = relay
            guard started else { return }
            client.configure(code: code, deviceName: UIDevice.current.name, relay: relay)
            pushCode()
        }
    }
    @Published var language: Lang = L.current {
        didSet { L.set(language); registerCategories(); pushCode() }
    }
    private var session: WCSession?
    private var sub: AnyCancellable?

    static let categoryAllow = "visto.ask"          // permitir y denegar
    static let categoryDenyOnly = "visto.ask.high"   // riesgo alto: solo denegar

    func start() {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        client.onNewAsk = { [weak self] a in self?.notify(a); Feel.shared.ask(tool: a.tool, project: a.project, risky: !a.canAllow) }
        client.onNewQuestion = { [weak self] q in self?.notify(question: q); Feel.shared.question(project: q.project) }
        client.onEvent = { [weak self] kind, agent, project, secs in self?.notify(event: kind, agent: agent, project: project, seconds: secs) }
        client.onChange = { [weak self] in self?.changed() }
        QuickDecision.decide = { allow in await PhoneModel.shared.quickDecide(allow: allow) }
        QuickDecision.focus = { on in await MainActor.run { PhoneModel.shared.client.setFocus(on) }; return on ? L.tr("Modo foco activado.") : L.tr("Modo foco apagado.") }
        LiveBridge.decide = { id, allow in await PhoneModel.shared.decideByID(id, allow: allow) }
        client.configure(code: code, deviceName: UIDevice.current.name, relay: relay)
        client.start()
        if WCSession.isSupported() { let s = WCSession.default; s.delegate = self; s.activate(); session = s }
    }

    private func registerCategories() {
        let allow = UNNotificationAction(identifier: "allow", title: L.tr("Permitir"), options: [])
        let deny = UNNotificationAction(identifier: "deny", title: L.tr("Denegar"), options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryAllow, actions: [allow, deny], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryDenyOnly, actions: [deny], intentIdentifiers: [], options: []),
        ])
    }

    func pair(_ raw: String, relay scanned: RelayEndpoint? = nil) -> Bool {
        guard Pairing.isValid(raw) else { return false }
        let c = Pairing.normalize(raw)
        VistoStore.code = c; code = c
        if let scanned { relay = scanned }      // el QR de la Mac trae su relay
        client.configure(code: c, deviceName: UIDevice.current.name, relay: relay)
        client.start()
        pushCode()
        return true
    }

    func unpair() {
        VistoStore.code = nil; code = nil
        client.configure(code: nil, deviceName: UIDevice.current.name, relay: relay)
        client.stop()
        pushCode()
    }

    func retry() { client.configure(code: code, deviceName: UIDevice.current.name, relay: relay); client.stop(); client.start() }

    private func notify(_ a: Ask) {
        let c = UNMutableNotificationContent()
        c.title = L.t("Claude pide permiso: \(a.tool)", "Claude asks for permission: \(a.tool)")
        c.subtitle = a.project
        c.body = a.detail.isEmpty ? L.tr("Sin detalle") : String(a.detail.prefix(160))
        c.sound = .default
        c.categoryIdentifier = a.canAllow ? Self.categoryAllow : Self.categoryDenyOnly
        c.userInfo = ["id": a.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: a.id, content: c, trigger: nil))
    }

    private func notify(question q: QAsk) {
        let c = UNMutableNotificationContent()
        c.title = L.tr("Claude pregunta")
        c.subtitle = q.project
        c.body = String((q.items.first?.question ?? "").prefix(160))
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: q.id, content: c, trigger: nil))
    }

    private func notify(event kind: String, agent: String, project: String, seconds: Int) {
        let ok = kind == "done"
        if ok { Feel.shared.done(agent: agent, project: project) } else { Feel.shared.failed(agent: agent, project: project) }
        let c = UNMutableNotificationContent()
        c.title = ok ? L.t("\(VTFormat.agentName(agent)) terminó", "\(VTFormat.agentName(agent)) finished") : L.t("\(VTFormat.agentName(agent)) falló", "\(VTFormat.agentName(agent)) failed")
        c.subtitle = project
        c.body = ok ? L.t("Trabajó \(VTFormat.duration(seconds)).", "Worked for \(VTFormat.duration(seconds)).") : L.t("Se detuvo con un error después de \(VTFormat.duration(seconds)).", "Stopped with an error after \(VTFormat.duration(seconds)).")
        c.sound = ok ? .default : UNNotificationSound.defaultCritical
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        if let s = session, s.isReachable { s.sendMessage(["event": [kind, agent, project, seconds]], replyHandler: nil, errorHandler: nil) }
    }

    private var lastFeedCount = 0
    private var lastLeadState = "idle"

    private func changed() {
        pushToWatch()
        live.update(client)
        // cada paso nuevo de un agente se nota; y se nota cuando empieza a pensar
        if client.feed.count != lastFeedCount { if client.agents.contains(where: { $0.state == "tool" }) { Feel.shared.tick() }; lastFeedCount = client.feed.count }
        let lead = client.agents.first(where: \.isBusy)?.state ?? "idle"
        if lead == "thinking", lastLeadState != "thinking" { Feel.shared.thinking() }
        lastLeadState = lead
        UNUserNotificationCenter.current().setBadgeCount(client.asks.count + client.questions.count) { _ in }
    }

    // MARK: acciones (con historial)

    /// Permitir puede pedir Face ID (ajuste). Denegar nunca lo pide: es siempre lo seguro.
    private func authorized(_ allow: Bool) async -> Bool {
        guard allow, requireFaceID else { return true }
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L.tr("Permitir lo que pide Claude"))) ?? false
    }

    func answer(_ ask: Ask, allow: Bool) {
        Task { if await authorized(allow) { commit(ask, allow: allow) } else { Feel.shared.denied() } }
    }

    /// «Permitir siempre»: pide Face ID igual que permitir, y la Mac guarda la regla.
    func answerAlways(_ ask: Ask) {
        Task {
            guard await authorized(true) else { Feel.shared.denied(); return }
            client.answerAlways(ask.id)
            Feel.shared.allowed()
            record(DecisionRecord(tool: ask.tool, project: ask.project, allowed: true, at: Date()))
            clearNotification(ask.id)
        }
    }

    private func commit(_ ask: Ask, allow: Bool) {
        client.answer(ask.id, allow: allow)
        if allow { Feel.shared.allowed() } else { Feel.shared.denied() }
        record(DecisionRecord(tool: ask.tool, project: ask.project, allowed: allow, at: Date()))
        clearNotification(ask.id)
    }

    /// Para Siri, el botón de acción y la Isla Dinámica: espera a conectar un momento (la app puede acabar de despertar).
    func quickDecide(allow: Bool) async -> String {
        start()
        for _ in 0..<50 where !(client.isConnected && !client.asks.isEmpty) { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard client.isConnected else { return L.tr("No encuentro claude pet en la red.") }
        guard let ask = client.asks.last(where: { allow ? $0.canAllow : true }) else {
            return client.asks.isEmpty ? L.tr("No hay permisos pendientes.") : L.tr("Lo pendiente es de riesgo alto: apruébalo en la Mac.")
        }
        guard await authorized(allow) else { return L.tr("No se confirmó con Face ID.") }
        commit(ask, allow: allow)
        return allow ? L.t("Permitido: \(ask.tool) en \(ask.project).", "Allowed: \(ask.tool) in \(ask.project).") : L.t("Denegado: \(ask.tool) en \(ask.project).", "Denied: \(ask.tool) in \(ask.project).")
    }

    func decideByID(_ id: String, allow: Bool) async {
        start()
        for _ in 0..<30 where !client.isConnected { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard let ask = client.asks.first(where: { $0.id == id }), await authorized(allow) else { return }
        commit(ask, allow: allow)
    }

    func reply(_ q: QAsk, picks: [[Int]]) {
        client.reply(q.id, picks: picks)
        Feel.shared.allowed()
        record(DecisionRecord(tool: "Pregunta", project: q.project, allowed: true, at: Date()))
        clearNotification(q.id)
    }

    private func record(_ r: DecisionRecord) {
        history = Array(([r] + history).prefix(30))
        DecisionRecord.save(history)
    }

    func clearHistory() { history = []; DecisionRecord.save([]) }

    private func clearNotification(_ id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: reloj

    private func pushCode() {
        guard let s = session, s.activationState == .activated else { return }
        var ctx = s.applicationContext; ctx["code"] = code ?? ""; ctx["lang"] = language.rawValue; ctx["relay"] = relay.map { "\($0.host):\($0.port):\($0.tls ? 1 : 0)" } ?? ""
        try? s.updateApplicationContext(ctx)
    }

    private func pushToWatch() {
        guard let s = session, s.activationState == .activated, s.isPaired, let data = try? JSONEncoder().encode(client.snapshot) else { return }
        if s.isReachable { s.sendMessage(["snap": data], replyHandler: nil, errorHandler: nil) }
        var ctx = s.applicationContext
        ctx["snap"] = data
        try? s.updateApplicationContext(ctx)
    }

    fileprivate func handleWatch(_ message: [String: Any]) {
        if let a = message["answer"] as? [Any], a.count == 2, let id = a[0] as? String, let allow = a[1] as? Bool {
            if let ask = client.asks.first(where: { $0.id == id }) { answer(ask, allow: allow) } else { client.answer(id, allow: allow) }
        }
        if let r = message["reply"] as? Data, let obj = try? JSONDecoder().decode(WatchReply.self, from: r) {
            if let q = client.questions.first(where: { $0.id == obj.id }) { reply(q, picks: obj.picks) } else { client.reply(obj.id, picks: obj.picks) }
        }
        if let f = message["focus"] as? Bool { client.setFocus(f) }
        if message["needState"] != nil { pushToWatch() }
    }
}

struct WatchReply: Codable { var id: String; var picks: [[Int]] }

/// Lo que decidiste desde el móvil: solo herramienta, proyecto y resultado. Nunca el comando.
struct DecisionRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var tool: String
    var project: String
    var allowed: Bool
    var at: Date
    static func load() -> [DecisionRecord] {
        guard let d = UserDefaults.standard.data(forKey: "decisions"), let l = try? JSONDecoder().decode([DecisionRecord].self, from: d) else { return [] }
        return l
    }
    static func save(_ l: [DecisionRecord]) { UserDefaults.standard.set(try? JSONEncoder().encode(l), forKey: "decisions") }
}

extension PhoneModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["id"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case "allow": if let a = client.asks.first(where: { $0.id == id }) { self.answer(a, allow: true) } else { client.answer(id, allow: true) }
            case "deny": if let a = client.asks.first(where: { $0.id == id }) { self.answer(a, allow: false) } else { client.answer(id, allow: false) }
            default: break
            }
        }
    }
}

extension PhoneModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.watchPaired = session.isPaired; self.pushCode(); self.pushToWatch() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.watchPaired = session.isPaired; self.pushCode() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.handleWatch(message) } }
}
