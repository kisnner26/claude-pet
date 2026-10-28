import Foundation
import CoreGraphics

/// Avisos al telefono aunque Visto este cerrada o el iPhone suspendido: claude pet publica en un tema de ntfy (ntfy.sh o tu propio servidor)
/// y la app gratuita de ntfy en el iPhone lo entrega como notificacion normal. No hace falta cuenta ni servidor propio.
/// Apagado de serie. El tema es el secreto: largo y aleatorio. Por defecto el aviso no lleva el comando, solo la herramienta y el proyecto.
enum PhoneAlertRules {
    static let defaultServer = "https://ntfy.sh"

    /// Tema nuevo: 26 caracteres de un alfabeto sin ambiguos, con aleatoriedad del sistema.
    static func newTopic() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        var g = SystemRandomNumberGenerator()
        return "cp" + String((0..<24).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &g)] })
    }

    static func validTopic(_ t: String) -> Bool { t.range(of: "^[a-z0-9]{16,40}$", options: .regularExpression) != nil }

    /// Servidor: solo https, sin credenciales en la direccion ni ruta; sin barra final.
    static func normalizedServer(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: trimmed), c.scheme == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else { return nil }
        return "https://" + host + (c.port.map { ":\($0)" } ?? "")
    }

    static func url(server: String, topic: String) -> URL? {
        guard let s = normalizedServer(server), validTopic(topic) else { return nil }
        return URL(string: s + "/" + topic)
    }

    /// Direccion para suscribirse desde la app de ntfy (QR): `ntfy://servidor/tema`.
    static func subscribeLink(server: String, topic: String) -> String? {
        guard let s = normalizedServer(server), validTopic(topic) else { return nil }
        return "ntfy://" + s.dropFirst("https://".count) + "/" + topic
    }

    enum Kind: Equatable { case permission, question, done, error }
    struct Message: Equatable { var title: String; var body: String; var priority: Int }

    /// El texto del aviso. `detail` solo entra si el usuario lo pidio y no parece contener un secreto.
    static func message(_ kind: Kind, agent: String, tool: String = "", project: String, detail: String = "", includeDetail: Bool = false, seconds: Int = 0, risky: Bool = false, language: Lang = L.current) -> Message {
        let name = agent == "codex" ? "Codex" : "Claude"
        let p = project.isEmpty ? "" : String(project.prefix(40))
        func t(_ es: String, _ en: String) -> String { language == .en ? en : es }
        var body: String
        switch kind {
        case .permission:
            body = p.isEmpty ? t("\(name) pide permiso: \(tool)", "\(name) asks permission: \(tool)") : t("\(name) pide permiso: \(tool) en \(p)", "\(name) asks permission: \(tool) in \(p)")
            if includeDetail, !detail.isEmpty, SecretDetector.find(in: detail, path: project) == nil { body += "\n" + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(100)) }
            if risky { body += "\n" + t("Riesgo alto: solo se puede denegar desde el teléfono.", "High risk: it can only be denied from the phone.") }
            return Message(title: "claude pet", body: body, priority: risky ? 5 : 4)
        case .question:
            return Message(title: "claude pet", body: p.isEmpty ? t("\(name) te hace una pregunta", "\(name) has a question") : t("\(name) te hace una pregunta en \(p)", "\(name) has a question in \(p)"), priority: 4)
        case .done:
            let mins = seconds >= 60 ? " (\(seconds / 60) min)" : ""
            return Message(title: "claude pet", body: p.isEmpty ? t("\(name) terminó", "\(name) finished") + mins : t("\(name) terminó en \(p)", "\(name) finished in \(p)") + mins, priority: 3)
        case .error:
            return Message(title: "claude pet", body: p.isEmpty ? t("\(name) falló", "\(name) failed") : t("\(name) falló en \(p)", "\(name) failed in \(p)"), priority: 4)
        }
    }

    /// Si toca avisar al telefono ahora: encendido, y (si se pidio) solo cuando no estas en el Mac. Con Visto conectada, ya avisa ella.
    static func shouldSend(enabled: Bool, onlyAway: Bool, idleSeconds: TimeInterval, awayAfter: TimeInterval = 60, vistoConnected: Bool, kind: Kind) -> Bool {
        guard enabled else { return false }
        if vistoConnected { return false }
        return !onlyAway || idleSeconds >= awayAfter
    }
}

final class PhoneAlerts: @unchecked Sendable {
    static let shared = PhoneAlerts()
    private let lock = NSLock()
    private var seen: Set<String> = []
    private var lastSent: [String: Date] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8; c.timeoutIntervalForResource = 12; c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    var onStatus: (@Sendable (String) -> Void)?

    /// Segundos sin tocar teclado ni raton.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// `key` evita repetir el mismo permiso/pregunta; `throttleKey` limita a un aviso cada 4 s del mismo tipo.
    func send(_ message: PhoneAlertRules.Message, key: String?, server: String, topic: String) {
        guard let url = PhoneAlertRules.url(server: server, topic: topic) else { onStatus?("servidor o tema no válidos"); return }
        lock.lock()
        if let key { if !seen.insert(key).inserted { lock.unlock(); return }; if seen.count > 300 { seen = [key] } }
        let kindKey = "\(message.priority)\(message.body.prefix(12))"
        if let last = lastSent[kindKey], Date().timeIntervalSince(last) < 4 { lock.unlock(); return }
        lastSent[kindKey] = Date()
        lock.unlock()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(message.body.utf8)
        req.setValue(message.title, forHTTPHeaderField: "Title")
        req.setValue(String(message.priority), forHTTPHeaderField: "Priority")
        session.dataTask(with: req) { [weak self] _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            self?.onStatus?(err != nil ? "sin conexión con el servidor" : code == 200 ? "" : "el servidor respondió \(code)")
        }.resume()
    }
}
