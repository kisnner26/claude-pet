import Foundation
import SwiftUI

final class GitScanCoordinator: @unchecked Sendable {
    typealias Scanner = @Sendable (String) -> GitHealth
    private struct Request { let workspace: String; let completion: @Sendable (String, GitHealth) -> Void }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "claudepet.mission.git", qos: .utility)
    private let scanner: Scanner
    private var running = false
    private var pending: Request?
    private var starts = 0

    init(scanner: @escaping Scanner = { GitPulse.scan($0) }) { self.scanner = scanner }

    func request(workspace: String, completion: @escaping @Sendable (String, GitHealth) -> Void) {
        let request = Request(workspace: workspace, completion: completion)
        lock.lock()
        if running {
            pending = request // una sola pendiente; la más nueva sustituye a la anterior
            lock.unlock()
            return
        }
        running = true
        starts += 1
        lock.unlock()
        launch(request)
    }

    var launchCount: Int { lock.withLock { starts } }
    var hasPending: Bool { lock.withLock { pending != nil } }

    private func launch(_ request: Request) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.scanner(request.workspace)
            request.completion(request.workspace, result)

            self.lock.lock()
            let next = self.pending
            self.pending = nil
            if next == nil { self.running = false }
            else { self.starts += 1 }
            self.lock.unlock()
            if let next { self.launch(next) }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}

@MainActor
final class MissionControl: ObservableObject {
    @Published private(set) var timeline: [MissionEvent] = []
    @Published private(set) var git = GitHealth()
    @Published private(set) var changes: [ChangedFile] = []
    @Published private(set) var relay: Relay?
    @Published private(set) var collision = false
    @Published private(set) var recovery: RecoveryCapsule?
    @Published private(set) var toolCalls = 0
    @Published private(set) var activeSince: Date?

    private struct PendingError: Equatable {
        let session: String
        let startedAt: Date
        let project: String
        let workspace: String
    }

    private let now: () -> Date
    private let scanner: GitScanCoordinator
    private var localProject = ""
    private var localWorkspace = ""
    private var localSession = ""
    private var localState: PetState = .idle
    private var peerProject = ""
    private var peerState: PetState = .idle
    private var collisionCandidateSince: Date?
    private var collisionClearSince: Date?
    private var lastActiveScan = Date.distantPast
    private var lastManualScan = Date.distantPast
    private var workspaceHealth: [String: GitHealth] = [:]
    private var pendingError: PendingError?
    private var dismissedError: PendingError?
    private var handledError: PendingError?
    private var toolFrequency: [String: Int] = [:]
    private var lastSummary: String?
    private var lastDone: [String: Date] = [:]

    init(now: @escaping () -> Date = Date.init,
         scanner: @escaping GitScanCoordinator.Scanner = { GitPulse.scan($0) }) {
        self.now = now
        self.scanner = GitScanCoordinator(scanner: scanner)
    }

    var workspace: String { localWorkspace }
    var elapsed: TimeInterval { activeSince.map { max(0, now().timeIntervalSince($0)) } ?? 0 }
    var topTools: [(name: String, count: Int)] {
        let pairs: [(name: String, count: Int)] = toolFrequency.map { (name: $0.key, count: $0.value) }
        let ordered = pairs.sorted { left, right in
            left.count == right.count ? left.name < right.name : left.count > right.count
        }
        return Array(ordered.prefix(3))
    }
    var focusLabel: String {
        if activeSince != nil { return summary(elapsed: elapsed) }
        return lastSummary ?? "sin sesión activa"
    }
    var scanLaunchCount: Int { scanner.launchCount }
    /// Ultimo proyecto conocido de Claude (persiste aunque la sesion este en reposo).
    var project: String { localProject }

    /// Doce lecturas locales de la sesión. Son deliberadamente derivadas de estado, tiempos y
    /// `git status`: no añaden contenido de prompts, comandos ni archivos al pet bus.
    var insights: [MissionInsight] {
        let elapsedMinutes = Int(elapsed / 60)
        let peerWorking = peerState.isActive
        let localWorking = localState.isActive
        let toolName = topTools.first?.name ?? ""
        let checkpoint = git.available && git.affected == 0
        return [
            .init(id: "radar", title: "radar de coordinación", detail: collision ? "dos agentes trabajan sobre el mismo proyecto" : "sin zona compartida detectada", tone: collision ? .caution : .calm),
            .init(id: "approval", title: "decisión pendiente", detail: localState == .waiting ? "claude espera tu aprobación" : "no hay decisiones bloqueando el flujo", tone: localState == .waiting ? .caution : .calm),
            .init(id: "recovery", title: "recuperación", detail: recovery == nil ? "sin fallos que recuperar" : "hay un punto seguro para revisar", tone: recovery == nil ? .calm : .danger),
            .init(id: "conflicts", title: "integridad git", detail: git.conflicts > 0 ? "\(git.conflicts) conflictos requieren intervención" : (git.available ? "sin conflictos de merge" : "sin repositorio activo"), tone: git.conflicts > 0 ? .danger : (git.available ? .calm : .active)),
            .init(id: "checkpoint", title: "punto de control", detail: checkpoint ? "árbol limpio: listo para cambiar de contexto" : (git.available ? "\(git.affected) cambios antes del próximo corte" : "esperando proyecto"), tone: checkpoint ? .calm : .active),
            .init(id: "staging", title: "preparación", detail: git.staged > 0 ? "\(git.staged) cambios preparados para commit" : "todavía no hay cambios staged", tone: git.staged > 0 ? .active : .calm),
            .init(id: "untracked", title: "material nuevo", detail: git.untracked > 0 ? "\(git.untracked) archivos aún sin seguimiento" : "no hay archivos sueltos", tone: git.untracked > 0 ? .caution : .calm),
            .init(id: "pace", title: "ritmo", detail: localWorking ? "sesión activa · \(elapsedMinutes) min" : focusLabel, tone: localWorking ? .active : .calm),
            .init(id: "tools", title: "patrón de herramientas", detail: toolName.isEmpty ? "aún no hay patrón suficiente" : "predomina \(toolName) · \(toolCalls) usos", tone: toolCalls >= 12 ? .caution : .calm),
            .init(id: "handoff", title: "relevo", detail: peerState == .done && localWorking ? "codex terminó: revisa el resultado antes de continuar" : (peerWorking ? "codex sigue trabajando" : "sin relevo pendiente"), tone: peerState == .done && localWorking ? .active : .calm),
            .init(id: "focus", title: "foco", detail: localWorking && peerWorking ? "los dos agentes están activos" : (localWorking ? "claude concentra la sesión" : (peerWorking ? "codex concentra la sesión" : "sin agentes activos")), tone: localWorking && peerWorking ? .active : .calm),
            .init(id: "boundary", title: "límite de datos", detail: "los detalles y rutas siguen solo en esta mac", tone: .calm)
        ]
    }

    func perform(_ action: MissionAction) {
        switch action {
        case .refreshGit: refreshGit()
        case .openDiff: DiffOpener.open(workspace: recovery?.workspace ?? localWorkspace)
        case .clearRecovery: clearRecovery()
        }
    }

    func recordLocal(state: PetState, project: String, workspace: String, tool: String = "", session: String = "") {
        let date = now()
        let stateChanged = state != localState
        let projectChanged = project != localProject
        let workspaceChanged = !workspace.isEmpty && workspace != localWorkspace

        noteTransition(agent: "claude", from: localState, to: state, at: date)
        if stateChanged || projectChanged {
            append(agent: "claude", state: state, project: project, at: date)
        }

        if state.isActive, !localState.isActive {
            activeSince = date
            toolCalls = 0
            toolFrequency = [:]
            lastSummary = nil
        } else if !state.isActive, localState.isActive {
            lastSummary = summary(elapsed: activeSince.map { date.timeIntervalSince($0) } ?? 0)
            activeSince = nil
        }

        if state == .error, localState != .error || session != localSession {
            pendingError = PendingError(session: session, startedAt: date, project: project, workspace: workspace.isEmpty ? localWorkspace : workspace)
        } else if state != .error {
            pendingError = nil
            dismissedError = nil
            handledError = nil
        }

        localState = state
        localProject = project
        localSession = session
        if !workspace.isEmpty { localWorkspace = workspace }

        if workspaceChanged || (stateChanged && (state == .done || state == .error || state == .idle)) {
            requestScan(workspace: localWorkspace)
        }
        updateCollision(at: date)
    }

    func recordToolEvent(_ tool: String) {
        toolCalls += 1
        let name = tool.isEmpty ? "herramienta" : tool
        toolFrequency[name, default: 0] += 1
    }

    func recordPeer(state: PetState, project: String) {
        let date = now()
        noteTransition(agent: "codex", from: peerState, to: state, at: date)
        if state != peerState || project != peerProject { append(agent: "codex", state: state, project: project, at: date) }
        peerState = state
        peerProject = project
        updateCollision(at: date)
    }

    func peerLeft() {
        peerProject = ""
        peerState = .idle
        updateCollision(at: now())
    }

    func tick() {
        let date = now()
        if let relay, date.timeIntervalSince(relay.at) > Relay.duration + 0.4 { self.relay = nil }
        updateCollision(at: date)
        updateRecovery(at: date)
        if localState.isActive, date.timeIntervalSince(lastActiveScan) >= 15 {
            requestScan(workspace: localWorkspace)
        }
    }

    func clearRecovery() {
        if let pendingError { dismissedError = pendingError }
        recovery = nil
    }

    func refreshGit() {
        let date = now()
        guard date.timeIntervalSince(lastManualScan) >= 2 else { return }
        lastManualScan = date
        requestScan(workspace: localWorkspace)
    }

    /// Un agente termina y el otro empieza a trabajar poco después: es un relevo.
    private func noteTransition(agent: String, from old: PetState, to new: PetState, at date: Date) {
        if new == .done && old != .done { lastDone[agent] = date }
        guard SessionTrail.isWorking(new), !SessionTrail.isWorking(old) else { return }
        let other = agent == "claude" ? "codex" : "claude"
        if let done = lastDone[other], date.timeIntervalSince(done) <= Relay.window {
            relay = Relay(from: other, to: agent, at: date)
            lastDone[other] = nil
        }
    }

    private func summary(elapsed: TimeInterval) -> String {
        let base = "\(Int(max(0, elapsed) / 60)) min · \(toolCalls) herramientas"
        let names = topTools.map { "\($0.name) ×\($0.count)" }.joined(separator: ", ")
        return names.isEmpty ? base : base + " · " + names
    }

    private func append(agent: String, state: PetState, project: String, at: Date) {
        timeline.insert(MissionEvent(at: at, agent: agent, state: state, project: project), at: 0)
        if timeline.count > 16 { timeline.removeLast(timeline.count - 16) }
    }

    private func updateCollision(at date: Date) {
        let local = normalizedProject(localProject)
        let peer = normalizedProject(peerProject)
        let candidate = localState.isCollisionWork && peerState.isCollisionWork && !local.isEmpty && local == peer && !Self.genericProjects.contains(local)

        if candidate {
            collisionClearSince = nil
            if collisionCandidateSince == nil { collisionCandidateSince = date }
            if !collision, date.timeIntervalSince(collisionCandidateSince ?? date) >= 10 { collision = true }
        } else {
            collisionCandidateSince = nil
            if collision {
                if collisionClearSince == nil { collisionClearSince = date }
                if date.timeIntervalSince(collisionClearSince ?? date) >= 5 { collision = false; collisionClearSince = nil }
            } else {
                collisionClearSince = nil
            }
        }
    }

    private func updateRecovery(at date: Date) {
        guard let pending = pendingError, localState == .error,
              date.timeIntervalSince(pending.startedAt) >= 3,
              dismissedError != pending, handledError != pending else { return }
        if let current = recovery, current.session == pending.session, date.timeIntervalSince(current.createdAt) < 60 {
            handledError = pending
            return
        }
        let health = workspaceHealth[pending.workspace] ?? (pending.workspace == localWorkspace ? git : GitHealth())
        recovery = RecoveryCapsule(createdAt: date, project: pending.project, workspace: pending.workspace, health: health, session: pending.session)
        handledError = pending
    }

    private func requestScan(workspace: String) {
        var isDirectory: ObjCBool = false
        guard workspace.hasPrefix("/"),
              FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        lastActiveScan = now()
        scanner.request(workspace: workspace) { [weak self] scannedWorkspace, result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.workspaceHealth[scannedWorkspace] = result
                if scannedWorkspace == self.localWorkspace {
                    self.git = result
                    self.loadChanges(workspace: scannedWorkspace, affected: result.affected)
                }
                if let capsule = self.recovery, capsule.workspace == scannedWorkspace {
                    self.recovery = RecoveryCapsule(createdAt: capsule.createdAt, project: capsule.project,
                                                    workspace: capsule.workspace, health: result, session: capsule.session)
                }
            }
        }
    }

    private var changeScanRunning = false

    /// El mapa de cambios se calcula fuera del hilo principal y solo si hay algo que mostrar.
    private func loadChanges(workspace: String, affected: Int) {
        guard affected > 0 else { if !changes.isEmpty { changes = [] }; return }
        guard !changeScanRunning else { return }
        changeScanRunning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let files = ChangeMap.scan(workspace)
            DispatchQueue.main.async {
                guard let self else { return }
                self.changeScanRunning = false
                if workspace == self.localWorkspace, self.changes != files { self.changes = files }
            }
        }
    }

    private func normalizedProject(_ value: String) -> String {
        (value as NSString).lastPathComponent.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let genericProjects: Set<String> = [
        "app", "src", "web", "api", "backend", "frontend", "test", "tests", "docs", "lib", "core", "main"
    ]
}
