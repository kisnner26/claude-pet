import Combine
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
    private var session: WCSession?
    private var sub: AnyCancellable?

    static let categoryAllow = "visto.ask"          // permitir y denegar
    static let categoryDenyOnly = "visto.ask.high"   // riesgo alto: solo denegar

    func start() {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: "allow", title: "Permitir", options: [])
        let deny = UNNotificationAction(identifier: "deny", title: "Denegar", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryAllow, actions: [allow, deny], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryDenyOnly, actions: [deny], intentIdentifiers: [], options: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        client.onNewAsk = { [weak self] a in self?.notify(a); UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        client.onNewQuestion = { [weak self] q in self?.notify(question: q); UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        client.onEvent = { [weak self] kind, agent, project, secs in self?.notify(event: kind, agent: agent, project: project, seconds: secs) }
        client.onChange = { [weak self] in self?.changed() }
        client.configure(code: code, deviceName: UIDevice.current.name)
        client.start()
        if WCSession.isSupported() { let s = WCSession.default; s.delegate = self; s.activate(); session = s }
    }

    func pair(_ raw: String) -> Bool {
        guard Pairing.isValid(raw) else { return false }
        let c = Pairing.normalize(raw)
        VistoStore.code = c; code = c
        client.configure(code: c, deviceName: UIDevice.current.name)
        client.start()
        pushCode()
        return true
    }

    func unpair() {
        VistoStore.code = nil; code = nil
        client.configure(code: nil, deviceName: UIDevice.current.name)
        client.stop()
        pushCode()
    }

    func retry() { client.configure(code: code, deviceName: UIDevice.current.name); client.stop(); client.start() }

    private func notify(_ a: Ask) {
        let c = UNMutableNotificationContent()
        c.title = "Claude pide permiso: \(a.tool)"
        c.subtitle = a.project
        c.body = a.detail.isEmpty ? "Sin detalle" : String(a.detail.prefix(160))
        c.sound = .default
        c.categoryIdentifier = a.canAllow ? Self.categoryAllow : Self.categoryDenyOnly
        c.userInfo = ["id": a.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: a.id, content: c, trigger: nil))
    }

    private func notify(question q: QAsk) {
        let c = UNMutableNotificationContent()
        c.title = "Claude pregunta"
        c.subtitle = q.project
        c.body = String((q.items.first?.question ?? "").prefix(160))
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: q.id, content: c, trigger: nil))
    }

    private func notify(event kind: String, agent: String, project: String, seconds: Int) {
        let ok = kind == "done"
        UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
        let c = UNMutableNotificationContent()
        c.title = ok ? "\(VTFormat.agentName(agent)) terminó" : "\(VTFormat.agentName(agent)) falló"
        c.subtitle = project
        c.body = ok ? "Trabajó \(VTFormat.duration(seconds))." : "Se detuvo con un error después de \(VTFormat.duration(seconds))."
        c.sound = ok ? .default : UNNotificationSound.defaultCritical
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        if let s = session, s.isReachable { s.sendMessage(["event": [kind, agent, project, seconds]], replyHandler: nil, errorHandler: nil) }
    }

    private func changed() {
        pushToWatch()
        UNUserNotificationCenter.current().setBadgeCount(client.asks.count + client.questions.count) { _ in }
    }

    // MARK: acciones (con historial)

    func answer(_ ask: Ask, allow: Bool) {
        client.answer(ask.id, allow: allow)
        record(DecisionRecord(tool: ask.tool, project: ask.project, allowed: allow, at: Date()))
        clearNotification(ask.id)
    }

    func reply(_ q: QAsk, picks: [[Int]]) {
        client.reply(q.id, picks: picks)
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
        var ctx = s.applicationContext; ctx["code"] = code ?? ""
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
