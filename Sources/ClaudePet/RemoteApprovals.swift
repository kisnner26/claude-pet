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
                      risk: risk(of: ask).rawValue, expires: ask.at.addingTimeInterval(lifetime), canAlways: canAlways(ask))
    }

    /// «Siempre» desde fuera: solo si la isla tambien lo ofreceria (riesgo no alto y una clave de regla clara) y el perimetro no se queja.
    static func canAlways(_ ask: PermissionAsk, violatesPerimeter: Bool = false) -> Bool {
        risk(of: ask) != .high && ApprovalRules.key(tool: ask.tool, detail: ask.detail) != nil && !violatesPerimeter
    }

    /// Por que se rechaza una respuesta de fuera, o nil si vale. La politica, sin red.
    static func verdict(allow: Bool, ask: PermissionAsk?, now: Date) -> String? {
        guard let ask else { return "ya no está pendiente" }
        if now.timeIntervalSince(ask.at) > lifetime { return "caducó" }
        if allow, risk(of: ask) == .high { return "riesgo alto: apruébalo en la Mac" }
        return nil
    }

    static func wire(_ q: QuestionAsk) -> QAsk {
        QAsk(id: q.id, project: String(q.project.prefix(40)), items: q.questions.prefix(4).map { item in
            QItem(header: item.header, question: item.question, options: item.options.prefix(8).map(\.label), descriptions: item.options.prefix(8).map(\.description), multi: item.multiSelect)
        })
    }

    /// Convierte los indices elegidos en el dispositivo en las respuestas de la isla (pregunta -> etiquetas). Nunca texto libre del dispositivo.
    static func answers(for q: QuestionAsk, picks: [[Int]]) -> [String: String]? {
        guard picks.count == q.questions.count else { return nil }
        var out: [String: String] = [:]
        for (item, chosen) in zip(q.questions, picks) {
            let valid = Set(chosen).filter { item.options.indices.contains($0) }.sorted()
            guard !valid.isEmpty, item.multiSelect || valid.count == 1 else { return nil }
            out[item.question] = valid.map { item.options[$0].label }.joined(separator: ", ")
        }
        return out
    }

    static func agent(_ name: String, state: PetState, project: String, since: Date, context: Int?) -> AgentInfo {
        AgentInfo(agent: name, state: state.rawValue, project: String(project.prefix(40)), since: since, contextRemaining: context)
    }

    static func step(_ s: IslandStep) -> Step {
        Step(agent: s.agent, tool: String(s.tool.prefix(30)), target: String(s.target.suffix(60)), at: s.at, delta: s.delta)
    }

    /// Los agentes tal como se muestran en Visto, a partir del estado de la mascota.
    @MainActor static func agents(from st: PetStore) -> [VistoCore.AgentInfo] {
        var list: [VistoCore.AgentInfo] = []
        if st.claudePresent || st.state != .idle { list.append(agent("claude", state: st.state, project: st.terminalProject, since: st.claudeStateSince, context: st.contextReading?.remainingPercent)) }
        if st.codexPresent || st.codexState != .idle { list.append(agent("codex", state: st.codexState, project: st.terminalProject, since: st.codexStateSince, context: st.codexContextReading?.remainingPercent)) }
        return list
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
    private var agents: [AgentInfo] = []
    private var feed: [Step] = []
    private var focus = false
    private var currentQuestions: [QuestionAsk] = []
    private var sentQuestions: Set<String> = []
    private var running = false
    private let advertise: Bool

    /// La respuesta ya paso la politica. Se llama en una cola interna.
    var onAnswer: ((String, PermissionDecision) -> Void)?
    /// «Permitir siempre» pedido desde fuera; la Mac ya comprobo que se puede.
    var onAlways: ((String) -> Void)?
    var onPeersChanged: (([String]) -> Void)?
    /// Respuesta a una pregunta de Claude, ya convertida a etiquetas.
    var onQuestionAnswer: ((String, [String: String]) -> Void)?
    var onFocus: ((Bool) -> Void)?
    /// Cambio en permisos, agentes o plan: lo usa el servidor de Meta Quest para refrescar el visor.
    var onSnapshotChange: (() -> Void)?

    /// El estado que ve el visor, en JSON plano: sin detalle de mas ni nada que no se muestre.
    func questSnapshot() -> Data {
        lock.lock(); let asks = current, ag = agents, p = plan; lock.unlock()
        func win(_ w: VistoCore.PlanWindow?) -> Any { w.map { ["remaining": $0.remaining()] } ?? NSNull() }
        let obj: [String: Any] = [
            "host": Host.current().localizedName ?? "Mac",
            "asks": asks.prefix(4).map { a -> [String: Any] in let w = RemoteWire.wire(a); return ["id": w.id, "tool": w.tool, "project": w.project, "detail": w.detail, "risk": w.risk, "canAllow": w.canAllow] },
            "agents": ag.prefix(2).map { ["agent": $0.agent, "state": $0.state, "project": $0.project, "contextRemaining": $0.contextRemaining as Any] },
            "plan": p.map { ["five": win($0.five), "week": win($0.week)] as [String: Any] } ?? NSNull(),
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }

    /// Respuesta desde el visor: mismas reglas que desde Visto (nada de riesgo alto, nada caducado). Devuelve el motivo si se rechaza.
    func answerFromQuest(_ id: String, allow: Bool) -> String? {
        lock.lock(); let ask = current.first { $0.id == id }; lock.unlock()
        if let why = RemoteWire.verdict(allow: allow, ask: ask, now: Date()) { return why }
        onAnswer?(id, allow ? .allow : .deny)
        return nil
    }

    init(codePath: String = RemoteLink.codePath, advertise: Bool = true, hostName: String = Host.current().localizedName ?? "Mac") {
        self.codePath = codePath; self.advertise = advertise
        host = VistoHost(hostName: hostName)
        host.onAnswer = { [weak self] id, allow in self?.answered(id, allow) }
        host.onAlways = { [weak self] id in self?.alwaysAnswered(id) }
        host.onPeerReady = { [weak self] id in self?.greet(id) }
        host.onPeersChanged = { [weak self] peers in self?.onPeersChanged?(peers.map(\.name)) }
        host.onReply = { [weak self] id, picks in self?.replied(id, picks) }
        host.onFocus = { [weak self] on in self?.onFocus?(on) }
    }

    var port: UInt16 { host.port }
    var hasPeers: Bool { !host.peers.isEmpty }
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
        lock.lock(); running = false; sent = []; sentQuestions = []; lock.unlock()
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
        defer { onSnapshotChange?() }
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

    func syncQuestions(_ qs: [QuestionAsk]) {
        lock.lock()
        currentQuestions = qs
        guard running else { lock.unlock(); return }
        let ids = Set(qs.map(\.id))
        let gone = sentQuestions.subtracting(ids), fresh = qs.filter { !sentQuestions.contains($0.id) }
        sentQuestions = ids
        lock.unlock()
        for id in gone { host.broadcast(.questionGone(id: id)) }
        for q in fresh { host.broadcast(.question(RemoteWire.wire(q))) }
    }

    /// Solo se envia si cambio: el resto del tiempo no cruza nada por la red.
    func sendAgents(_ a: [AgentInfo]) {
        defer { onSnapshotChange?() }
        lock.lock(); let same = agents == a; agents = a; let on = running; lock.unlock()
        if on, !same { host.broadcast(.agents(a)) }
    }

    func sendFeed(_ f: [Step]) {
        lock.lock(); let same = feed == f; feed = f; let on = running; lock.unlock()
        if on, !same { host.broadcast(.feed(f)) }
    }

    func sendFocus(_ on: Bool) {
        lock.lock(); focus = on; let run = running; lock.unlock()
        if run { host.broadcast(.focus(on)) }
    }

    func sendEvent(kind: String, agent: String, project: String, seconds: Int) {
        lock.lock(); let on = running; lock.unlock()
        if on { host.broadcast(.event(kind: kind, agent: agent, project: String(project.prefix(40)), seconds: seconds)) }
    }

    private func replied(_ id: String, _ picks: [[Int]]) {
        lock.lock(); let q = currentQuestions.first { $0.id == id }; lock.unlock()
        guard let q, let answers = RemoteWire.answers(for: q, picks: picks) else { return }
        onQuestionAnswer?(id, answers)
    }

    func sendPlan(_ p: PlanSnapshot?) {
        defer { onSnapshotChange?() }
        lock.lock(); plan = p; let on = running; lock.unlock()
        if on { host.broadcast(.plan(p)) }
    }

    /// Quien se conecta tarde ve lo que ya espera.
    private func greet(_ id: UUID) {
        lock.lock(); let asks = current, p = plan, ag = agents, fd = feed, f = focus, qs = currentQuestions; lock.unlock()
        for a in asks { host.send(.ask(RemoteWire.wire(a)), to: id) }
        for q in qs { host.send(.question(RemoteWire.wire(q)), to: id) }
        host.send(.plan(p), to: id)
        host.send(.agents(ag), to: id); host.send(.feed(fd), to: id); host.send(.focus(f), to: id)
    }

    /// Rechaza una respuesta de fuera con un motivo (lo usa la parte que conoce el perimetro).
    func refuse(_ id: String, _ why: String) { host.broadcast(.refused(id: id, why: why)) }

    private func alwaysAnswered(_ id: String) {
        lock.lock(); let ask = current.first { $0.id == id }; lock.unlock()
        if let why = RemoteWire.verdict(allow: true, ask: ask, now: Date()) { host.broadcast(.refused(id: id, why: why)); return }
        guard let ask, RemoteWire.canAlways(ask) else { host.broadcast(.refused(id: id, why: "no se puede permitir siempre: hazlo en la Mac")); return }
        onAlways?(id)
    }

    private func answered(_ id: String, _ allow: Bool) {
        lock.lock(); let ask = current.first { $0.id == id }; lock.unlock()
        if let why = RemoteWire.verdict(allow: allow, ask: ask, now: Date()) { host.broadcast(.refused(id: id, why: why)); return }
        onAnswer?(id, allow ? .allow : .deny)
    }
}
