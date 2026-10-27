import Combine
import Foundation
import SwiftUI

enum AlertDisplayMode: String, CaseIterable, Identifiable {
    case all = "todos los avisos"
    case critical = "solo críticos"
    case none = "sin avisos visuales"
    var id: String { rawValue }
    func allows(critical: Bool) -> Bool { self == .all || (self == .critical && critical) }
}

@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore()
    let mission: MissionControl
    let handoff = HandoffController()
    let relay = SessionRelayController()
    let webScout = NativeWebScoutController()
    private var handoffObserver: AnyCancellable?
    private var relayObserver: AnyCancellable?

    @Published private(set) var state: PetState = .idle
    @Published private(set) var tool: String = ""
    @Published private(set) var bridgeOK = false
    @Published private(set) var busOK = false
    @Published private(set) var peer: Peer?
    @Published private(set) var gameActive = false
    @Published private(set) var collaborationActive = false
    @Published private(set) var hugActive = false
    @Published private(set) var codexDragging = false
    @Published private(set) var codexGesture: CodexGesture?
    @Published private(set) var safetyAlert: Activity?
    @Published private(set) var alertsSnoozedUntil = Date.distantPast
    @Published private(set) var reviewReady = false
    @Published private(set) var bugBattleLevel = 0
    @Published private(set) var contextReading: ContextReading?
    @Published private(set) var diffPull: DiffPull?
    @Published private(set) var radarTarget: String?
    @Published private(set) var codexContextReading: ContextReading?
    @Published private(set) var codexChanges: [ChangedFile] = []
    @Published private(set) var codexWorktrees: [WorktreeNode] = []
    @Published private(set) var codexDiffPull: DiffPull?
    @Published private(set) var codexRadarTarget: String?
    @Published private(set) var codexWorkspace = ""
    @Published private(set) var codexTask = ""
    /// De que lado esta la ventana de Codex respecto a la de Claude (-1 izquierda, +1 derecha). Lo fija el controlador de ventanas.
    @Published private(set) var codexSide = -1
    @Published private(set) var recentIslandSteps: [IslandStep] = []
    @Published private(set) var demoMode = false
    /// Geometria del partido; `nil` si las dos mascotas no estan visibles o estan demasiado lejos.
    @Published private(set) var gameGeometry: GameGeometry?
    // Presencia: cada mascota aparece solo si su herramienta esta en uso.
    @Published private(set) var claudePresent = false
    @Published private(set) var codexPresent = false
    /// Nombre de la app al frente: solo presencia, nunca captura de pantalla ni contenido.
    @Published private(set) var foregroundAppName = ""
    /// Apagado: la mascota de Claude se ve siempre (comportamiento anterior).
    @Published var autoVisibility: Bool = UserDefaults.standard.object(forKey: "autoVisibility") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoVisibility, forKey: "autoVisibility") }
    }
    /// Ocultar todo desde el menu (no se guarda: al reabrir la app vuelve a la presencia).
    /// Flotante: dos mascotas arrastrables. Isla: una sola pieza pegada al notch o a la barra superior.
    @Published var layout: PetLayout = PetLayout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .floating {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "layout") }
    }
    @Published var islandScreenPreference: IslandScreenPreference = IslandScreenPreference(rawValue: UserDefaults.standard.string(forKey: "islandScreenPreference") ?? "") ?? .notch {
        didSet { UserDefaults.standard.set(islandScreenPreference.rawValue, forKey: "islandScreenPreference") }
    }
    /// Opt-in: con la isla activa, los permisos de Claude Code se responden desde la isla en vez de la terminal.
    @Published var islandPermissions: Bool = UserDefaults.standard.bool(forKey: "islandPermissions") {
        didSet { UserDefaults.standard.set(islandPermissions, forKey: "islandPermissions") }
    }
    @Published var globalShortcutsEnabled: Bool = UserDefaults.standard.bool(forKey: "globalShortcutsEnabled") {
        didSet { UserDefaults.standard.set(globalShortcutsEnabled, forKey: "globalShortcutsEnabled"); onGlobalShortcutsChanged?(globalShortcutsEnabled) }
    }
    var onGlobalShortcutsChanged: ((Bool) -> Void)?
    /// Permisos que esperan respuesta (solo en memoria). Los responde `AppController` por el socket.
    @Published var permissionAsks: [PermissionAsk] = []
    var answerPermission: (String, PermissionDecision) -> Void = { _, _ in }
    var dismissPermission: (String) -> Void = { _ in }
    @Published var questionAsks: [QuestionAsk] = []
    var answerQuestion: (String, [String: String]) -> Void = { _, _ in }
    var dismissQuestion: (String) -> Void = { _ in }
    @Published var userHidden = false
    /// Mantiene las mascotas visibles aunque el agente esté en reposo, sin alterar el puente.
    @Published var pinSession: Bool = UserDefaults.standard.bool(forKey: "pinSession") {
        didSet { UserDefaults.standard.set(pinSession, forKey: "pinSession") }
    }
    @Published var muteClaude: Bool = UserDefaults.standard.bool(forKey: "muteClaude") {
        didSet { UserDefaults.standard.set(muteClaude, forKey: "muteClaude") }
    }
    @Published var muteCodex: Bool = UserDefaults.standard.bool(forKey: "muteCodex") {
        didSet { UserDefaults.standard.set(muteCodex, forKey: "muteCodex") }
    }
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
    @Published var codexSkin: CodexSkin = CodexSkin(rawValue: UserDefaults.standard.string(forKey: "codexSkin") ?? "") ?? .cloud {
        didSet { UserDefaults.standard.set(codexSkin.rawValue, forKey: "codexSkin") }
    }
    @Published var codexGesturesEnabled: Bool = UserDefaults.standard.object(forKey: "codexGesturesEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(codexGesturesEnabled, forKey: "codexGesturesEnabled") }
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
    @Published var alertDisplayMode: AlertDisplayMode = AlertDisplayMode(rawValue: UserDefaults.standard.string(forKey: "alertDisplayMode") ?? "") ?? .all {
        didSet { UserDefaults.standard.set(alertDisplayMode.rawValue, forKey: "alertDisplayMode"); updateSafetyAlert(Date()); refresh() }
    }
    /// Por defecto el nombre del proyecto NO sale de la app.
    @Published var shareProject: Bool = UserDefaults.standard.bool(forKey: "shareProject") {
        didSet { UserDefaults.standard.set(shareProject, forKey: "shareProject"); publish(event: nil) }
    }

    private struct Info { var state: PetState; var tool: String; var project: String; var detail: String; var origin: String; var workspace: String; var prompt: String; var todo: String; var at: Date }
    private var sessions: [String: Info] = [:]
    private var manual: (PetState, Date)?
    private var codexManual: (PetState, Date)?
    private var project = ""
    private var timer: Timer?
    private var beat: Timer?
    private var greetUntil = Date.distantPast
    private var cheerUntil = Date.distantPast
    private var concernUntil = Date.distantPast
    private var codexGestureUntil = Date.distantPast
    private var demoTimer: Timer?
    private var stateSince = Date()
    private var collaborationSince: Date?
    var visibility: PresenceLogic.Visibility {
        PresenceLogic.visibility(Presence(claude: (claudePresent || pinSession) && !muteClaude,
                                         codex: (codexPresent || pinSession) && !muteCodex), auto: autoVisibility, userHidden: userHidden)
    }
    var terminalProject: String { mission.workspace.isEmpty ? project : URL(fileURLWithPath: mission.workspace).lastPathComponent }
    var terminalTargetAvailable: Bool { TerminalTargetResolver.current(project: terminalProject) != nil }
    var pendingAttentionCount: Int { permissionAsks.count + questionAsks.count }
    var attentionLabel: String {
        switch pendingAttentionCount {
        case 0: return "sin decisiones pendientes"
        case 1: return "1 decisión pendiente"
        default: return "\(pendingAttentionCount) decisiones pendientes"
        }
    }
    var stateDurationLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(stateSince)))
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }
    var codexStateDurationLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(peerStateSince)))
        return seconds < 60 ? "(seconds) s" : "(seconds / 60) min"
    }
    var contextLabel: String {
        guard let reading = contextReading else { return "contexto no disponible" }
        return "contexto: \(reading.remainingPercent)% restante"
    }
    var contextPressureLabel: String {
        guard let reading = contextReading else { return "sin lectura" }
        switch reading.pressure {
        case .normal: return "normal"
        case .caution: return "cuidado"
        case .critical: return "crítico"
        }
    }
    var contextModelLabel: String { contextReading?.model ?? "modelo no disponible" }
    var codexContextModelLabel: String { codexContextReading?.model ?? "modelo codex no disponible" }
    var sessionSummary: String {
        let projectName = project.isEmpty ? "sin proyecto" : project
        let toolName = tool.isEmpty ? "sin herramienta" : tool
        return "\(projectName) · \(toolName)"
    }
    var workspaceLabel: String {
        let path = mission.workspace.isEmpty ? "" : mission.workspace
        return path.isEmpty ? "workspace no disponible" : URL(fileURLWithPath: path).lastPathComponent
    }
    var codexContextLabel: String {
        guard let reading = codexContextReading else { return "contexto codex no disponible" }
        return "contexto codex: \(reading.remainingPercent)% restante"
    }
    var alertsAreSnoozed: Bool { Date() < alertsSnoozedUntil }
    func snoozeAlerts(minutes: Int = 15) {
        alertsSnoozedUntil = Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        safetyAlert = nil
        refresh()
    }
    func wakeAlerts() { alertsSnoozedUntil = .distantPast; updateSafetyAlert(Date()); refresh() }
    func refreshTelemetryNow() {
        nextContextScan = .distantPast
        nextCodexVisualScan = .distantPast
        nextCodexGitScan = .distantPast
        refresh()
    }
    func setSnapshotContext(_ reading: ContextReading?) { contextReading = reading }
    func focusTerminal() { _ = TerminalTargetResolver.focus(project: terminalProject) }
    var pairNear: Bool { gameGeometry != nil }
    var collaborationStartedAt: Date? { collaborationSince }
    /// Estado que se muestra para Codex: la prueba local tiene prioridad, luego el bus.
    var codexState: PetState { codexManual?.0 ?? peer?.state ?? .idle }
    /// Actividad que pertenece a Claude. Los avisos locales no desplazan la actividad de Codex.
    var claudeBubbleActivity: Activity? {
        if let safetyAlert { return safetyAlert }
        if let notice = handoff.notice { return notice }
        return activity
    }
    var claudeBubbleState: PetState {
        if safetyAlert != nil { return .error }
        if handoff.notice != nil { return handoff.noticeState }
        return state
    }
    /// El bus solo aporta el estado de Codex; nunca texto de su sesión o de sus herramientas.
    var codexBubbleActivity: Activity? {
        guard codexState != .idle else { return nil }
        return Activity(title: "Codex: \(codexState.label.capitalized)", subtitle: showDetail ? codexTask : "", origin: "codex")
    }
    var codexBubbleState: PetState { codexState }
    /// Compatibilidad para las pruebas de presencia existentes.
    var bubbleFollowsCodex: Bool { claudeBubbleActivity == nil && codexBubbleActivity != nil }
    /// Codex mira hacia Claude: +1 derecha, -1 izquierda.
    var codexFacing: Int { codexSide < 0 ? 1 : -1 }

    func setPair(geometry: GameGeometry?, codexSide side: Int) {
        if side != codexSide { codexSide = side }
        if geometry != gameGeometry { gameGeometry = geometry }
        if geometry == nil && game.isActive { syncGame() }
        syncCollaboration()
        syncHug()
    }

    func gameFrame(at date: Date) -> GameFrame? {
        game.elapsed(at: date).flatMap { FootballChoreography.frame(elapsed: $0, reduceMotion: reduceMotion) }
    }

    func setApps(claude: Bool, codex: Bool) {
        claudeAppOpen = claude; codexAppOpen = codex
        updatePresence()
    }

    func setForegroundApp(_ name: String) {
        if foregroundAppName != name { foregroundAppName = name; updateRadar(); updateCodexRadar() }
    }

    func pullDiff(_ file: ChangedFile) {
        if diffPull?.file == file {
            DiffOpener.openChange(workspace: mission.workspace, file: file)
            return
        }
        let workspace = mission.workspace
        Task { [weak self] in
            let pull = await Task.detached(priority: .utility) {
                DiffPullReader.read(workspace: workspace, file: file)
            }.value
            guard self?.mission.workspace == workspace else { return }
            self?.diffPull = pull
        }
    }

    func openLatestDiff() {
        guard let file = mission.changes.first else { return }
        pullDiff(file)
    }

    func activateRadarTarget() {
        guard let target = radarTarget else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let app = apps.first { item in
            let name = item.localizedName?.lowercased() ?? ""
            return target == "claude" ? item.bundleIdentifier == AppPresence.claudeBundle : name.contains("terminal") || name.contains("iterm") || name.contains("warp")
        }
        app?.activate(options: [.activateIgnoringOtherApps])
    }

    func pullCodexDiff(_ file: ChangedFile) {
        if codexDiffPull?.file == file {
            DiffOpener.openChange(workspace: codexWorkspace, file: file)
            return
        }
        let workspace = codexWorkspace
        Task { [weak self] in
            let pull = await Task.detached(priority: .utility) {
                DiffPullReader.read(workspace: workspace, file: file)
            }.value
            guard self?.codexWorkspace == workspace else { return }
            self?.codexDiffPull = pull
        }
    }

    func activateCodexRadarTarget() {
        guard codexRadarTarget != nil,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == AppPresence.codexBundle }) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func updateRadar() {
        guard state == .waiting || state == .error || safetyAlert != nil else { radarTarget = nil; return }
        let origin = (activity?.origin ?? "").lowercased()
        let target = origin == "desktop" ? "claude" : "terminal"
        let foreground = foregroundAppName.lowercased()
        let alreadyThere = target == "claude" ? foreground.contains("claude")
            : foreground.contains("terminal") || foreground.contains("iterm") || foreground.contains("warp")
        radarTarget = alreadyThere ? nil : target
    }

    private func updateCodexRadar() {
        guard codexState == .waiting || codexState == .error else { codexRadarTarget = nil; return }
        codexRadarTarget = foregroundAppName.lowercased().contains("codex") ? nil : "codex"
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
    private let contextScanner = ContextMeterScanner()
    private var contextScanTask: Task<Void, Never>?
    private var contextSession = ""
    private var nextContextScan = Date.distantPast
    private let codexVisualScanner = CodexVisualScanner()
    private var codexVisualTask: Task<Void, Never>?
    private var nextCodexVisualScan = Date.distantPast
    private var nextCodexGitScan = Date.distantPast

    init(mission: MissionControl? = nil) {
        self.mission = mission ?? MissionControl()
        handoffObserver = handoff.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        relayObserver = relay.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
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
        if let toolEvent {
            mission.recordToolEvent(toolEvent)
            let target = e.detail.isEmpty ? e.project : e.detail
            let delta = (e.tool == "Edit" || e.tool == "Write") ? (mission.changes.first { $0.name == URL(fileURLWithPath: target).lastPathComponent }.map { ($0.added, $0.deleted) } ?? (0, 0)) : (0, 0)
            recentIslandSteps = IslandSteps.append(IslandStep(agent: "claude", tool: toolEvent, target: String(target.prefix(80)), added: delta.0, deleted: delta.1, workspace: e.workspace, at: Date()), to: recentIslandSteps)
        }
    }

    /// Olvida una sesion por completo: estado, vigilancia del proyecto y marca del bloqueo.
    private func drop(_ session: String) {
        sessions[session] = nil
        monitor.forget(session: session)
        testSessions.remove(session)
        WorkspaceSafety.clearMarker(session: session)
        if session == contextSession {
            contextScanTask?.cancel()
            contextScanTask = nil
            contextSession = ""
            contextReading = nil
        }
    }

    private func contextChanged(_ session: String) {
        guard sessions[session] != nil else { monitor.forget(session: session); return }
        if blockOnChange { WorkspaceSafety.markChanged(session: session) }
        updateSafetyAlert(Date())
        refresh()
    }

    func preview(_ s: PetState) { manual = (s, Date()); refresh() }

    func previewCodex(_ s: PetState) {
        codexManual = (s, Date())
        objectWillChange.send()
    }

    /// Recorrido local para enseñar la isla sin hooks, sesiones ni escritura en disco.
    func startDemo() {
        demoTimer?.invalidate()
        demoMode = true
        claudePresent = true; codexPresent = true
        manual = (.tool, Date())
        codexManual = (.thinking, Date())
        project = "claude-pet"
        tool = "Edit"
        contextReading = ContextReading(usedTokens: 112_000, compactAtTokens: 160_000, model: "claude-sonnet")
        codexContextReading = ContextReading(usedTokens: 48_000, compactAtTokens: 128_000, model: "codex")
        recentIslandSteps = [
            IslandStep(agent: "claude", tool: "Edit", target: "Sources/ClaudePet/IslandController.swift", added: 42, deleted: 9, workspace: "claude-pet", at: Date()),
            IslandStep(agent: "claude", tool: "Bash", target: "swift test", added: 0, deleted: 0, workspace: "claude-pet", at: Date().addingTimeInterval(-18)),
            IslandStep(agent: "codex", tool: "Apply", target: "docs/ISLAND.md", added: 8, deleted: 2, workspace: "claude-pet", at: Date().addingTimeInterval(-33)
            )
        ]
        permissionAsks = [PermissionAsk(id: "demo-permission", session: "demo", tool: "Bash", project: "claude-pet", detail: "swift build", canAlways: true, at: Date())]
        questionAsks = [QuestionAsk(id: "demo-question", session: "demo", project: "claude-pet", questions: [IslandQuestion(id: "demo-q", header: "siguiente paso", question: "como quieres continuar?", options: [("rápido", "menos pasos"), ("revisar", "ver el diff")], multiSelect: false)])]
        greetUntil = Date().addingTimeInterval(3)
        objectWillChange.send()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopDemo() }
        }
    }

    func stopDemo() {
        demoTimer?.invalidate(); demoTimer = nil
        guard demoMode else { return }
        demoMode = false; permissionAsks = []; questionAsks = []; recentIslandSteps = []
        contextReading = nil; codexContextReading = nil; manual = nil; codexManual = nil; claudePresent = false; codexPresent = false
        updatePresence(); objectWillChange.send()
    }

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
        let localCodexProject = codexWorkspace.isEmpty ? nil : URL(fileURLWithPath: codexWorkspace).lastPathComponent
        let proj = m.project.map { String($0.prefix(40)) } ?? localCodexProject
        peer = Peer(id: m.id, state: st, project: proj, lastTs: m.ts, seen: now)
        mission.recordPeer(state: st, project: proj ?? "")
        if old == nil || m.event == "appeared" { greetUntil = now.addingTimeInterval(3) }
        switch m.event {
        case "appeared": triggerAutomaticCodex(.wave)
        case "finished": cheerUntil = now.addingTimeInterval(2.5); triggerAutomaticCodex(.celebrate)
        case "error": concernUntil = now.addingTimeInterval(3); triggerAutomaticCodex(.curious)
        default: break
        }
        syncGame()
        syncCollaboration()
        updateReviewReady()
        updateCodexRadar()
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

    func triggerCodex(_ gesture: CodexGesture) {
        codexGesture = gesture
        codexGestureUntil = Date().addingTimeInterval(gesture.duration)
    }

    private func triggerAutomaticCodex(_ gesture: CodexGesture) {
        guard codexGesturesEnabled else { return }
        triggerCodex(gesture)
    }

    func setCodexDragging(_ dragging: Bool) {
        guard codexDragging != dragging else { return }
        codexDragging = dragging
    }

    private func syncGame() {
        updatePresence()
        syncCollaboration()
        // sin Claude en uso (p. ej. solo Codex abierto) no hay partido automatico
        guard (claudePresent || game.forced), gameGeometry != nil else {
            game.cancel()
            if gameActive { gameActive = false }
            syncHug()
            return
        }
        guard animationsEnabled, footballEnabled || game.forced else {
            game.cancel()
            if gameActive { gameActive = false }
            syncHug()
            return
        }
        game.update(now: Date(), claude: state, peer: peerStateKnown ? peer?.state : nil)
        if game.isActive != gameActive { gameActive = game.isActive }
        syncHug()
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
        CompanionInfo(codex: codexState, claude: claudePresent ? state : .idle, codexCheer: date < cheerUntil,
                      codexConcern: date < concernUntil, claudeDone: claudePresent && date < claudeDoneUntil,
                      gesture: date < codexGestureUntil ? codexGesture : nil, dragging: codexDragging,
                      collaborating: collaborationActive)
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
        if let m = codexManual, now.timeIntervalSince(m.1) > 5 { codexManual = nil }
        if codexGesture != nil, now >= codexGestureUntil { codexGesture = nil }
        if let p = peer, now.timeIntervalSince(p.seen) > peerTTL {
            peer = nil
            peerStateKnown = false
            mission.peerLeft()
        }   // el par desaparecio sin avisar
        if bugBattleLevel > 0, now.timeIntervalSince(lastBugChange) >= 60 { bugBattleLevel -= 1; lastBugChange = now }   // la infestacion cede sola
        checkWorkspaceChanges(now)
        updateSafetyAlert(now)
        mission.tick()
        refreshContext(session: lastMissionSession, now: now)
        refreshCodexVisuals(now: now)
        refresh()
    }

    private func refreshCodexVisuals(now: Date) {
        guard codexPresent else {
            codexVisualTask?.cancel(); codexVisualTask = nil
            clearCodexVisuals()
            return
        }
        guard now >= nextCodexVisualScan, codexVisualTask == nil else { return }
        nextCodexVisualScan = now.addingTimeInterval(8)
        let shouldScanGit = now >= nextCodexGitScan
        codexVisualTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await codexVisualScanner.read(now: now)
            guard !Task.isCancelled else { codexVisualTask = nil; return }
            guard let snapshot else {
                clearCodexVisuals()
                codexVisualTask = nil
                return
            }
            let workspaceChanged = snapshot.workspace != codexWorkspace
            if workspaceChanged { codexDiffPull = nil }
            codexWorkspace = snapshot.workspace
            codexTask = snapshot.task
            codexContextReading = snapshot.context
            let project = URL(fileURLWithPath: snapshot.workspace).lastPathComponent
            if peer != nil, peer?.project != project {
                peer?.project = project
                mission.recordPeer(state: codexState, project: project)
                updateReviewReady()
            }
            if workspaceChanged || shouldScanGit {
                nextCodexGitScan = now.addingTimeInterval(15)
                let workspace = snapshot.workspace
                let result = await Task.detached(priority: .utility) {
                    (ChangeMap.scan(workspace), WorktreeMap.scan(workspace))
                }.value
                guard !Task.isCancelled, codexWorkspace == workspace else { codexVisualTask = nil; return }
                codexChanges = result.0
                codexWorktrees = result.1
            }
            codexVisualTask = nil
        }
    }

    private func clearCodexVisuals() {
        if codexContextReading != nil { codexContextReading = nil }
        if !codexChanges.isEmpty { codexChanges = [] }
        if !codexWorktrees.isEmpty { codexWorktrees = [] }
        if codexDiffPull != nil { codexDiffPull = nil }
        if !codexWorkspace.isEmpty { codexWorkspace = "" }
        if !codexTask.isEmpty { codexTask = "" }
    }

    private func refreshContext(session: String, now: Date) {
        guard !session.isEmpty else {
            if contextReading != nil { contextReading = nil }
            return
        }
        if session != contextSession {
            contextScanTask?.cancel()
            contextSession = session
            contextReading = nil
            nextContextScan = .distantPast
        }
        guard now >= nextContextScan, contextScanTask == nil else { return }
        nextContextScan = now.addingTimeInterval(3)
        let prefix = session
        contextScanTask = Task { [weak self] in
            guard let self else { return }
            let reading = await contextScanner.read(sessionPrefix: prefix)
            guard !Task.isCancelled, contextSession == prefix else { return }
            if let reading, contextReading != reading { contextReading = reading }
            contextScanTask = nil
        }
    }

    private func syncCollaboration() {
        let codexWorking = peerStateKnown && (peer?.state == .starting || peer?.state == .thinking || peer?.state == .tool)
        let claudeWorking = state == .starting || state == .thinking || state == .tool
        let shouldCollaborate = animationsEnabled && gameGeometry != nil && claudePresent && codexPresent && claudeWorking && codexWorking
        if shouldCollaborate {
            if !collaborationActive {
                collaborationActive = true
                collaborationSince = Date()
            }
        } else if collaborationActive {
            collaborationActive = false
            collaborationSince = nil
        }
    }

    /// El abrazo solo depende de la posicion real de ambas ventanas. El partido y el cable tienen prioridad visual.
    private func syncHug() {
        // solo con ambos tranquilos: el abrazo sustituye a sus sprites y no debe esconder un error, un permiso pendiente ni trabajo en curso
        let calm: (PetState) -> Bool = { $0 == .idle || $0 == .done }
        let shouldHug = animationsEnabled && gameGeometry?.hugEligible == true && !gameActive && !collaborationActive
            && calm(state) && calm(codexState)
        if hugActive != shouldHug { hugActive = shouldHug }
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
        guard alertDisplayMode.allows(critical: true), now >= alertsSnoozedUntil else { safetyAlert = nil; return }
        let changed = monitor.changed.filter { sessions[$0] != nil }
        if !changed.isEmpty {
            safetyAlert = Activity(title: "El proyecto cambio mientras claude pensaba",
                                   subtitle: blockOnChange ? "herramientas detenidas hasta nuevo mensaje" : "revisa el diff antes de seguir", origin: "")
            return
        }
        if stallWatch && alertDisplayMode.allows(critical: false) {
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
            stateSince = Date()
            if new == .done { claudeDoneUntil = Date().addingTimeInterval(2.5) }
            announce("claude pet: \(new.label.lowercased())")
        }
        let workspace = top?.workspace ?? ""
        if workspace != lastMissionWorkspace, diffPull != nil { diffPull = nil }
        if new != lastMissionState || newProject != lastMissionProject || workspace != lastMissionWorkspace || topSession != lastMissionSession {
            mission.recordLocal(state: new, project: newProject, workspace: workspace, tool: newTool, session: topSession)
            lastMissionState = new
            lastMissionProject = newProject
            lastMissionWorkspace = workspace
            lastMissionSession = topSession
        }
        refreshContext(session: topSession, now: Date())
        if changed { publish(event: eventFor(new)) }
        syncGame()
        updateReviewReady()
        updateRadar()
    }

    private func updateReviewReady() {
        guard let peer, peer.state == .done, let name = peer.project, !name.isEmpty else { reviewReady = false; return }
        reviewReady = sessions.values.contains { ($0.state == .starting || $0.state == .thinking || $0.state == .tool || $0.state == .waiting) && $0.project == name && !$0.workspace.isEmpty }
    }

    /// La tarea en curso del proyecto conocido: su lista de Claude y, si no hay, su ultimo mensaje.
    private var currentTask: String {
        let name = mission.project
        guard let info = sessions.values.filter({ $0.project == name }).max(by: { $0.at < $1.at }) else { return "" }
        return info.todo.isEmpty ? info.prompt : info.todo
    }

    func requestReview(by reviewer: Agent) {
        handoff.requestReview(reviewer: reviewer, workspace: mission.workspace, project: mission.project, task: currentTask)
    }

    func createRelay(from source: Agent) {
        relay.create(source: source, workspace: source == .claude ? mission.workspace : "",
                     task: source == .claude ? currentTask : "", state: source == .claude ? state : codexState)
    }

    /// Ante una colision: la siguiente herramienta de cada sesion de Claude en ese proyecto se deniega
    /// hasta tu proximo mensaje (el hook lee la marca "paused"). Solo la pide el usuario desde el menu.
    func pauseClaude() {
        for (session, info) in sessions where info.project == mission.project {
            WorkspaceSafety.markChanged(session: session, reason: "paused")
        }
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


enum PetLayout: String, CaseIterable {
    case floating, island
    var title: String { self == .floating ? "flotante" : "isla en el notch" }
}
