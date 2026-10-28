import Foundation
import VistoCore

/// Aprobar permisos desde el iPhone o el Apple Watch con la app Visto (carpeta `companion/`).
/// Es opt-in. claude pet escucha en la red local con un canal cifrado cuya clave sale de un codigo que solo tu conoces.
/// Desde fuera solo se puede permitir o denegar esta vez (nunca «siempre»), y lo de riesgo alto solo se puede denegar:
/// aprobarlo exige estar delante de la Mac. El perimetro y las reglas ya se aplicaron antes de que un permiso llegue aqui.
enum RemoteWire {
    /// El hook deja de esperar a los 110 s; con margen para no ofrecer un permiso que ya no existe.
    static let lifetime: TimeInterval = 105
    static let maxDetail = 300

    static func risk(of ask: PermissionAsk) -> PermissionRisk {
        PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project).risk
    }

    static func wire(_ ask: PermissionAsk) -> VistoCore.Ask {
        VistoCore.Ask(id: ask.id, tool: String(ask.tool.prefix(40)), project: String(ask.project.prefix(40)), detail: String(ask.detail.prefix(maxDetail)),
                      risk: risk(of: ask).rawValue, expires: ask.at.addingTimeInterval(lifetime))
    }

    /// Por que se rechaza una respuesta de fuera, o nil si vale. La politica, sin red.
    static func verdict(allow: Bool, ask: PermissionAsk?, now: Date) -> String? {
        guard let ask else { return "ya no está pendiente" }
        if now.timeIntervalSince(ask.at) > lifetime { return "caducó" }
        if allow, risk(of: ask) == .high { return "riesgo alto: apruébalo en la Mac" }
        return nil
    }

    static func snapshot(_ u: PlanUsage?) -> PlanSnapshot? {
        guard let u else { return nil }
        func w(_ x: PlanWindow?) -> VistoCore.PlanWindow? { x.map { VistoCore.PlanWindow(usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) } }
        return PlanSnapshot(five: w(u.five), week: w(u.week))
    }
}

/// El anfitrion de Visto dentro de claude pet: guarda el codigo, escucha, envia los permisos pendientes y recibe las respuestas.
final class RemoteLink: @unchecked Sendable {
    static var codePath: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_PET_VISTO_CODE"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.claude-pet/visto-code"
    }

    private let host: VistoHost
    private let codePath: String
    private let lock = NSLock()
    private var current: [PermissionAsk] = []
    private var sent: Set<String> = []
    private var plan: PlanSnapshot?
    private var running = false
    private let advertise: Bool

    /// La respuesta ya paso la politica. Se llama en una cola interna.
    var onAnswer: ((String, PermissionDecision) -> Void)?
    var onPeersChanged: (([String]) -> Void)?

    init(codePath: String = RemoteLink.codePath, advertise: Bool = true, hostName: String = Host.current().localizedName ?? "Mac") {
        self.codePath = codePath; self.advertise = advertise
        host = VistoHost(hostName: hostName)
        host.onAnswer = { [weak self] id, allow in self?.answered(id, allow) }
        host.onPeerReady = { [weak self] id in self?.greet(id) }
        host.onPeersChanged = { [weak self] peers in self?.onPeersChanged?(peers.map(\.name)) }
    }

    var port: UInt16 { host.port }
    var peers: [String] { host.peers.map(\.name) }

    /// El codigo vive en un archivo 0600; se crea la primera vez.
    func code() -> String {
        if let c = try? String(contentsOfFile: codePath, encoding: .utf8), Pairing.isValid(c) { return Pairing.normalize(c) }
        return writeNewCode()
    }

    @discardableResult
    private func writeNewCode() -> String {
        let c = Pairing.newCode()
        let dir = (codePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: codePath, contents: Data(c.utf8), attributes: [.posixPermissions: 0o600])
        chmod(codePath, 0o600)
        return c
    }

    func start() throws {
        try host.start(code: code(), advertise: advertise)
        lock.lock(); running = true; lock.unlock()
    }

    func stop() {
        lock.lock(); running = false; sent = []; lock.unlock()
        host.stop()
    }

    /// Codigo nuevo: se desconectan todos los dispositivos y hay que volver a emparejarlos.
    func regenerateCode() throws -> String {
        let c = writeNewCode()
        lock.lock(); let on = running; sent = []; lock.unlock()
        if on { try host.rotate(code: c, advertise: advertise) }
        return c
    }

    func sync(_ asks: [PermissionAsk]) {
        lock.lock()
        current = asks
        guard running else { lock.unlock(); return }
        let ids = Set(asks.map(\.id))
        let gone = sent.subtracting(ids), fresh = asks.filter { !sent.contains($0.id) }
        sent = ids
        lock.unlock()
        for id in gone { host.broadcast(.gone(id: id)) }
        for a in fresh { host.broadcast(.ask(RemoteWire.wire(a))) }
    }

    func sendPlan(_ p: PlanSnapshot?) {
        lock.lock(); plan = p; let on = running; lock.unlock()
        if on { host.broadcast(.plan(p)) }
    }

    /// Quien se conecta tarde ve lo que ya espera.
    private func greet(_ id: UUID) {
        lock.lock(); let asks = current, p = plan; lock.unlock()
        for a in asks { host.send(.ask(RemoteWire.wire(a)), to: id) }
        host.send(.plan(p), to: id)
    }

    private func answered(_ id: String, _ allow: Bool) {
        lock.lock(); let ask = current.first { $0.id == id }; lock.unlock()
        if let why = RemoteWire.verdict(allow: allow, ask: ask, now: Date()) { host.broadcast(.refused(id: id, why: why)); return }
        onAnswer?(id, allow ? .allow : .deny)
    }
}
