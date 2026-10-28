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
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        client.onNewAsk = { [weak self] a in self?.notify(a) }
        client.onChange = { [weak self] in self?.pushToWatch() }
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
        guard let s = session, s.activationState == .activated, s.isPaired else { return }
        let payload: [String: Any] = ["asks": (try? JSONEncoder().encode(client.asks)) ?? Data(), "plan": (try? JSONEncoder().encode(client.plan)) ?? Data(), "host": client.hostName ?? ""]
        if s.isReachable { s.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
        var ctx = s.applicationContext
        for (k, v) in payload { ctx[k] = v }
        try? s.updateApplicationContext(ctx)
    }

    fileprivate func handleWatch(_ message: [String: Any]) {
        if let a = message["answer"] as? [Any], a.count == 2, let id = a[0] as? String, let allow = a[1] as? Bool { client.answer(id, allow: allow); clearNotification(id) }
        if message["needState"] != nil { pushToWatch() }
    }
}

extension PhoneModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["id"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case "allow": client.answer(id, allow: true)
            case "deny": client.answer(id, allow: false)
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
