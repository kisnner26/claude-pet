import Foundation
import SwiftUI

@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore()
    let mission: MissionControl

    @Published private(set) var state: PetState = .idle
    @Published private(set) var tool: String = ""
    @Published private(set) var bridgeOK = false
    @Published private(set) var busOK = false
    @Published private(set) var peer: Peer?
    @Published private(set) var gameActive = false
    @Published private(set) var safetyAlert: Activity?
    @Published private(set) var reviewReady = false
    @Published private(set) var bugBattleLevel = 0
    /// De que lado esta la ventana de Codex respecto a la de Claude (-1 izquierda, +1 derecha). Lo fija el controlador de ventanas.
    @Published private(set) var codexSide = -1
    /// Geometria del partido; `nil` si las dos mascotas no estan visibles o estan demasiado lejos.
    @Published private(set) var gameGeometry: GameGeometry?
    // Presencia: cada mascota aparece solo si su herramienta esta en uso.
    @Published private(set) var claudePresent = false
    @Published private(set) var codexPresent = false
    /// Apagado: la mascota de Claude se ve siempre (comportamiento anterior).
    @Published var autoVisibility: Bool = UserDefaults.standard.object(forKey: "autoVisibility") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoVisibility, forKey: "autoVisibility") }
    }
    /// Ocultar todo desde el menu (no se guarda: al reabrir la app vuelve a la presencia).
    @Published var userHidden = false
    private var claudeAppOpen = false
    private var codexAppOpen = false
    private var hookPresentUntil = Date.distantPast        // hay hooks de Claude Code recientes y la sesion no se cerro
    /// Interruptor general: apagado, la mascota queda quieta y no hay partidos.
    @Published var animationsEnabled: Bool = UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(animationsEnabled, forKey: "animationsEnabled"); syncGame() }
    }
    @Published var footballEnabled: Bool = UserDefaults.standard.object(forKey: "footballEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(footballEnabled, forKey: "footballEnabled"); syncGame() }
    }
    @Published var skin: Skin = Skin(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .block {
        didSet { Sprite.skin = skin; UserDefaults.standard.set(skin.rawValue, forKey: "skin") }
    }
    @Published private(set) var activity: Activity?
    @Published var showBubble: Bool = UserDefaults.standard.object(forKey: "showBubble") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBubble, forKey: "showBubble") }
    }
    /// Archivos, descripciones y programa de un comando. Solo local: nunca sale por el pet bus.
    @Published var showDetail: Bool = UserDefaults.standard.object(forKey: "showDetail") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDetail, forKey: "showDetail"); refresh() }
    }
    /// Opt-in: el hook deniega la siguiente herramienta de una sesion cuando el proyecto cambia mientras piensa.
    @Published var blockOnChange: Bool = UserDefaults.standard.bool(forKey: "blockOnChange") {
        didSet { UserDefaults.standard.set(blockOnChange, forKey: "blockOnChange"); WorkspaceSafety.setBlocking(blockOnChange) }
    }
    @Published var stallWatch: Bool = UserDefaults.standard.object(forKey: "stallWatch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(stallWatch, forKey: "stallWatch"); updateSafetyAlert(Date()); refresh() }
    }
    /// Por defecto el nombre del proyecto NO sale de la app.
    @Published var shareProject: Bool = UserDefaults.standard.bool(forKey: "shareProject") {
        didSet { UserDefaults.standard.set(shareProject, forKey: "shareProject"); publish(event: nil) }
    }

    private struct Info { var state: PetState; var tool: String; var project: String; var detail: String; var origin: String; var workspace: String; var prompt: String; var todo: String; var at: Date }
    private var sessions: [String: Info] = [:]
    private var manual: (PetState, Date)?
    private var project = ""
    private var timer: Timer?
    private var beat: Timer?
    private var greetUntil = Date.distantPast
    private var cheerUntil = Date.distantPast
    private var concernUntil = Date.distantPast
    var visibility: PresenceLogic.Visibility {
        PresenceLogic.visibility(Presence(claude: claudePresent, codex: codexPresent), auto: autoVisibility, userHidden: userHidden)
    }
    var pairNear: Bool { gameGeometry != nil }
    /// Codex mira hacia Claude: +1 derecha, -1 izquierda.
    var codexFacing: Int { codexSide < 0 ? 1 : -1 }

    func setPair(geometry: GameGeometry?, codexSide side: Int) {
        if side != codexSide { codexSide = side }
        if geometry != gameGeometry { gameGeometry = geometry }
        if geometry == nil && game.isActive { syncGame() }
    }

    func gameFrame(at date: Date) -> GameFrame? {
        game.elapsed(at: date).flatMap { FootballChoreography.frame(elapsed: $0, reduceMotion: reduceMotion) }
    }

    func setApps(claude: Bool, codex: Bool) {
        claudeAppOpen = claude; codexAppOpen = codex
        updatePresence()
    }

    private func updatePresence() {
        let p = PresenceLogic.presence(claudeAppOpen: claudeAppOpen, hookSessionActive: Date() < hookPresentUntil,
                                       codexAppOpen: codexAppOpen, peerPresent: peer != nil)
        if p.claude != claudePresent { claudePresent = p.claude }
        if p.codex != codexPresent { codexPresent = p.codex }
    }

    private var claudeDoneUntil = Date.distantPast       // Claude acaba de terminar: Codex aplaude
    private let peerTTL: TimeInterval = 25
    /// Partido de futbol entre Claude y el mini del par (solo visual, deducido de presencia y estado).
    private let game = FootballGame(config: .fromEnvironment())
    private var peerStateKnown = false
    private var peerStateSince = Date()
    private var lastPeerState: PetState?
    private let monitor = WorkspaceMonitor()
    private var testSessions = Set<String>()
    private var nextWorkspaceScan = Date.distantPast
    private var lastBugChange = Date.distantPast
    private var lastMissionState: PetState?
    private var lastMissionProject = ""
    private var lastMissionWorkspace = ""
    private var lastMissionSession = ""

    init(mission: MissionControl? = nil) {
        self.mission = mission ?? MissionControl()
        Sprite.skin = skin
        WorkspaceSafety.setBlocking(blockOnChange)          // la bandera del hook refleja siempre la opcion guardada
        monitor.onChange = { [weak self] session in Task { @MainActor in self?.contextChanged(session) } }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
        beat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish(event: nil) }
        }
    }

    func setBridge(_ ok: Bool) { bridgeOK = ok }
    func setBus(_ ok: Bool) { busOK = ok; if ok { publish(event: "appeared") } }
    func shutdownBus() { publish(event: "left", wait: true) }

    // MARK: hooks de Claude Code

    func apply(_ e: PetEvent) {
        var toolEvent: String?
        switch e.kind {
        case .end:
            drop(e.session)
            if sessions.isEmpty { hookPresentUntil = .distantPast }
        case .state(let s):
            hookPresentUntil = Date().addingTimeInterval(2 * 3600)      // sesion abierta: Claude Code esta en uso
            if s == .tool { toolEvent = e.tool }
            // la tarea persiste durante la sesion: tu ultimo mensaje y la tarea en curso de la lista
            var prompt = sessions[e.session]?.prompt ?? "", todo = sessions[e.session]?.todo ?? ""
            if e.task.hasPrefix("p:") { prompt = String(e.task.dropFirst(2)); todo = "" }
            if e.task.hasPrefix("t:") { todo = String(e.task.dropFirst(2)) }
            let prior = sessions[e.session]
            sessions[e.session] = Info(state: s, tool: (s == .tool || s == .waiting) ? e.tool : "", project: e.project,
                                       detail: e.detail, origin: e.origin, workspace: e.workspace, prompt: prompt, todo: todo, at: Date())
            // linea base al empezar a pensar o al volver de una herramienta (los cambios de la propia sesion no cuentan)
            if s == .thinking, prior?.state != .thinking, !e.workspace.isEmpty { monitor.arm(session: e.session, workspace: e.workspace) }
            if s == .tool && e.tool == "test" { testSessions.insert(e.session) }
            if s == .error { bugBattleLevel = min(3, bugBattleLevel + 1); lastBugChange = Date() }
            if s == .done && testSessions.remove(e.session) != nil, bugBattleLevel > 0 { bugBattleLevel -= 1; lastBugChange = Date() }
        }
        refresh()
        if let toolEvent { mission.recordToolEvent(toolEvent) }
    }

    /// Olvida una sesion por completo: estado, vigilancia del proyecto y marca del bloqueo.
    private func drop(_ session: String) {
        sessions[session] = nil
        monitor.forget(session: session)
        testSessions.remove(session)
        WorkspaceSafety.clearMarker(session: session)
    }

    private func contextChanged(_ session: String) {
        guard sessions[session] != nil else { monitor.forget(session: session); return }
        if blockOnChange { WorkspaceSafety.markChanged(session: session) }
        updateSafetyAlert(Date())
        refresh()
    }

    func preview(_ s: PetState) { manual = (s, Date()); refresh() }

    // MARK: pet bus

    func receive(line: String) {
        guard let m = PetBus.decode(line) else { return }
        let now = Date()
        let old = peer
        if let o = old, o.id == m.id, m.ts < o.lastTs { return }   // mensaje viejo fuera de orden
        if m.event == "left" {
            if peer?.id == m.id {
                peer = nil
                peerStateKnown = false
                mission.peerLeft()
                syncGame()
                updateReviewReady()
            }
            return
        }
        let known = PetState(rawValue: m.state)
        peerStateKnown = known != nil                              // desconocido: hay presencia, pero no cuenta como idle para el partido
        let st = known ?? .idle
        if lastPeerState != st { lastPeerState = st; peerStateSince = now }
        let proj = m.project.map { String($0.prefix(40)) }
        peer = Peer(id: m.id, state: st, project: proj, lastTs: m.ts, seen: now)
        mission.recordPeer(state: st, project: proj ?? "")
        if old == nil || m.event == "appeared" { greetUntil = now.addingTimeInterval(3) }
        switch m.event {
        case "finished": cheerUntil = now.addingTimeInterval(2.5)
        case "error": concernUntil = now.addingTimeInterval(3)
        default: break
        }
        syncGame()
        updateReviewReady()
    }

    /// Reduce movimiento del sistema (o forzado con CLAUDE_PET_REDUCE_MOTION=1 para pruebas).
    var gameStart: Date? { game.startedAt }
    var reduceMotion: Bool {
        ProcessInfo.processInfo.environment["CLAUDE_PET_REDUCE_MOTION"] == "1"
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: disparadores manuales (menu y `ClaudePet --trigger <nombre>`)

    static let triggerNames = ["football", "greet", "cheer", "concern"]
    private var demoUntil = Date.distantPast

    /// Lanza una animacion al instante, sin esperar ni exigir a Codex.
    func trigger(_ name: String) {
        guard animationsEnabled else { return }
        let now = Date()
        switch name {
        case "football":
            guard gameGeometry != nil else { return }       // las dos mascotas deben verse y estar cerca
            game.forceStart(now: now)
            if game.isActive != gameActive { gameActive = game.isActive }
            return
        case "greet": greetUntil = now.addingTimeInterval(3)
        case "cheer": cheerUntil = now.addingTimeInterval(2.5)
        case "concern": concernUntil = now.addingTimeInterval(3)
        default: return
        }
        demoUntil = now.addingTimeInterval(3)       // muestra al companero aunque Codex no este
        objectWillChange.send()
    }

    private func syncGame() {
        updatePresence()
        // sin Claude en uso (p. ej. solo Codex abierto) no hay partido automatico
        guard (claudePresent || game.forced), gameGeometry != nil else {
            game.cancel()
            if gameActive { gameActive = false }
            return
        }
        guard animationsEnabled, footballEnabled || game.forced else {
            game.cancel()
            if gameActive { gameActive = false }
            return
        }
        game.update(now: Date(), claude: state, peer: peerStateKnown ? peer?.state : nil)
        if game.isActive != gameActive { gameActive = game.isActive }
    }

    func cue(at date: Date) -> PeerCue? {
        guard peer != nil || date < demoUntil || game.isActive else { return nil }
        let p = peer ?? Peer(id: "demo", state: .idle, project: nil, lastTs: 0, seen: date)
        let frame = game.elapsed(at: date).flatMap { FootballChoreography.frame(elapsed: $0, reduceMotion: reduceMotion) }
        // greet tambien al terminar Codex: Claude levanta el brazo (choque de manos)
        return PeerCue(state: p.state, greet: date < greetUntil || date < cheerUntil, cheer: date < cheerUntil, concern: date < concernUntil, game: frame,
                       companion: visibility.codexWindow,
                       lookX: CompanionLogic.lookX(peer: peer?.state, claude: state, mirrored: codexSide > 0))
    }

    /// Lo que el escenario necesita para dibujar a Codex junto a Claude. Solo estados y marcas de tiempo: nada del chat.
    func companionInfo(at date: Date) -> CompanionInfo {
        CompanionInfo(codex: peer?.state ?? .idle, claude: claudePresent ? state : .idle, codexCheer: date < cheerUntil,
                      codexConcern: date < concernUntil, claudeDone: claudePresent && date < claudeDoneUntil)
    }

    private var lastPublished: (PetState, String)?

    private func publish(event: String?, wait: Bool = false) {
        guard busOK || event == "left" else { return }
        let proj = shareProject && !project.isEmpty ? project : nil
        let msg = BusMessage(v: PetBus.version, id: PetBus.selfID, state: state.rawValue,
                             project: proj, ts: Date().timeIntervalSince1970, event: event)
        PetBus.publish(msg, wait: wait)
        lastPublished = (state, project)
    }

    /// Titulo = lo que hace ahora, lo mas exacto posible. Subtitulo = la tarea de fondo.
    static func describe(_ s: PetState, tool: String, detail: String, task: String) -> (String, String) {
        func action() -> String {
            let d = detail
            switch tool {
            case "Bash":
                if d.hasPrefix("$ ") { return "Ejecutando " + d.dropFirst(2) }
                return d.isEmpty ? "Ejecutando un comando" : d
            case "test":
                if d.hasPrefix("$ ") { return "Ejecutando pruebas (" + d.dropFirst(2) + ")" }
                return d.isEmpty ? "Ejecutando pruebas" : d
            case "Read": return d.isEmpty ? "Leyendo un archivo" : "Leyendo " + d
            case "Edit", "MultiEdit": return d.isEmpty ? "Editando un archivo" : "Editando " + d
            case "Write": return d.isEmpty ? "Escribiendo un archivo" : "Escribiendo " + d
            case "NotebookEdit": return d.isEmpty ? "Editando un notebook" : "Editando " + d
            case "Grep": return d.isEmpty ? "Buscando en el codigo" : "Buscando \u{AB}\(d)\u{BB}"
            case "Glob": return d.isEmpty ? "Buscando archivos" : "Buscando archivos \u{AB}\(d)\u{BB}"
            case "WebFetch": return d.isEmpty ? "Consultando una pagina" : "Consultando " + d
            case "WebSearch": return d.isEmpty ? "Buscando en la web" : "Buscando en la web: " + d
            case "Task", "Agent": return d.isEmpty ? "Delegando a un subagente" : "Subagente: " + d
            case "TodoWrite", "TaskUpdate", "TaskCreate": return task.isEmpty ? "Actualizando tareas" : task
            case "": return task.isEmpty ? "Trabajando" : task
            default:
                if tool.hasPrefix("mcp__") {
                    let parts = tool.components(separatedBy: "__")
                    let name = parts.count > 2 ? parts[2] : tool
                    return d.isEmpty ? "Usando " + name : "\(name): \(d)"
                }
                return d.isEmpty ? tool : "\(tool): \(d)"
            }
        }
        switch s {
        case .starting: return ("Iniciando sesion", "")
        case .thinking: return (task.isEmpty ? "Pensando" : task, task.isEmpty ? "" : "Pensando")
        case .tool: return (action(), task)
        case .waiting: return (action(), "Esperando tu aprobacion")
        case .done: return (task.isEmpty ? "Termino" : task, "Termino")
        case .error: return (task.isEmpty ? "Algo fallo" : task, "Algo fallo")
        case .idle: return ("", "")
        }
    }

    private func eventFor(_ s: PetState) -> String? {
        switch s {
        case .starting, .thinking, .tool: return "working"
        case .waiting: return "waiting"
        case .done: return "finished"
        case .error: return "error"
        case .idle: return nil
        }
    }

    // MARK: ciclo

    private func prune() {
        prune(at: Date())
    }

    func prune(at now: Date) {
        for (k, v) in sessions {
            let age = now.timeIntervalSince(v.at)
            if (v.state == .done && age > 5) || (v.state == .error && age > 8) || age > 900 { drop(k) }
        }
        if let m = manual, now.timeIntervalSince(m.1) > 5 { manual = nil }
        if let p = peer, now.timeIntervalSince(p.seen) > peerTTL {
            peer = nil
            peerStateKnown = false
            mission.peerLeft()
        }   // el par desaparecio sin avisar
        if bugBattleLevel > 0, now.timeIntervalSince(lastBugChange) >= 60 { bugBattleLevel -= 1; lastBugChange = now }   // la infestacion cede sola
        checkWorkspaceChanges(now)
        updateSafetyAlert(now)
        mission.tick()
        refresh()
    }

    /// Pide los escaneos (asincronos, fuera del hilo principal) cada 3 s a las sesiones que estan pensando.
    private func checkWorkspaceChanges(_ now: Date) {
        guard now >= nextWorkspaceScan else { return }
        nextWorkspaceScan = now.addingTimeInterval(3)
        for (session, info) in sessions where info.state == .thinking && !info.workspace.isEmpty {
            monitor.check(session: session, workspace: info.workspace)
        }
    }

    private func updateSafetyAlert(_ now: Date) {
        let changed = monitor.changed.filter { sessions[$0] != nil }
        if !changed.isEmpty {
            safetyAlert = Activity(title: "El proyecto cambio mientras claude pensaba",
                                   subtitle: blockOnChange ? "herramientas detenidas hasta nuevo mensaje" : "revisa el diff antes de seguir", origin: "")
            return
        }
        if stallWatch {
            if let s = sessions.values.first(where: { stalled($0.state, since: $0.at, now) }) {
                safetyAlert = Activity(title: "claude parece bloqueado", subtitle: "sin actividad desde hace \(Int(now.timeIntervalSince(s.at) / 60)) min", origin: s.origin)
                return
            }
            if let p = peer, stalled(p.state, since: peerStateSince, now) {
                safetyAlert = Activity(title: "\(p.id) parece bloqueado", subtitle: "sin cambios desde hace \(Int(now.timeIntervalSince(peerStateSince) / 60)) min", origin: "")
                return
            }
        }
        safetyAlert = nil
    }

    private func stalled(_ st: PetState, since: Date, _ now: Date) -> Bool {
        switch st {
        case .thinking: return now.timeIntervalSince(since) >= WorkspaceSafety.thinkingStall
        case .tool: return now.timeIntervalSince(since) >= WorkspaceSafety.toolStall
        default: return false
        }
    }

    private func refresh() {
        if let m = manual {
            state = m.0; tool = ""
            activity = m.0 == .idle ? nil : Activity(title: "Prueba de estado", subtitle: m.0.label.capitalized, origin: "")
            syncGame()
            return
        }
        let topPair = sessions.max { a, b in
            a.value.state.priority != b.value.state.priority ? a.value.state.priority < b.value.state.priority : a.value.at < b.value.at
        }
        let top = topPair?.value
        let topSession = topPair?.key ?? ""
        let new = top?.state ?? .idle
        let newTool = top?.tool ?? ""
        let newProject = top?.project ?? ""
        if newTool != tool { tool = newTool }
        let act: Activity? = {
            guard let t = top, new != .idle else { return nil }
            let task = showDetail ? (t.todo.isEmpty ? t.prompt : t.todo) : ""
            let d = Self.describe(new, tool: t.tool, detail: showDetail ? t.detail : "", task: task)
            return Activity(title: d.0, subtitle: d.1, origin: t.origin)
        }()
        let shown = safetyAlert ?? act            // una alerta de seguridad siempre se ve en la burbuja
        if shown != activity { activity = shown }
        let changed = new != state || newProject != project
        project = newProject
        if new != state {
            state = new
            if new == .done { claudeDoneUntil = Date().addingTimeInterval(2.5) }
            announce("claude pet: \(new.label.lowercased())")
        }
        let workspace = top?.workspace ?? ""
        if new != lastMissionState || newProject != lastMissionProject || workspace != lastMissionWorkspace || topSession != lastMissionSession {
            mission.recordLocal(state: new, project: newProject, workspace: workspace, tool: newTool, session: topSession)
            lastMissionState = new
            lastMissionProject = newProject
            lastMissionWorkspace = workspace
            lastMissionSession = topSession
        }
        if changed { publish(event: eventFor(new)) }
        syncGame()
        updateReviewReady()
    }

    private func updateReviewReady() {
        guard let peer, peer.state == .done, let name = peer.project, !name.isEmpty else { reviewReady = false; return }
        reviewReady = sessions.values.contains { ($0.state == .starting || $0.state == .thinking || $0.state == .tool || $0.state == .waiting) && $0.project == name && !$0.workspace.isEmpty }
    }

    func openReview() {
        guard let name = peer?.project, let info = sessions.values.first(where: { $0.project == name && !$0.workspace.isEmpty }) else { return }
        DiffOpener.open(workspace: info.workspace)
    }

    private func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
