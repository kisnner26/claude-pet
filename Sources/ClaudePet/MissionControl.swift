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

    init(now: @escaping () -> Date = Date.init,
         scanner: @escaping GitScanCoordinator.Scanner = { GitPulse.scan($0) }) {
        self.now = now
        self.scanner = GitScanCoordinator(scanner: scanner)
    }

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

    func recordLocal(state: PetState, project: String, workspace: String, tool: String = "", session: String = "") {
        let date = now()
        let stateChanged = state != localState
        let projectChanged = project != localProject
        let workspaceChanged = !workspace.isEmpty && workspace != localWorkspace

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
                if scannedWorkspace == self.localWorkspace { self.git = result }
                if let capsule = self.recovery, capsule.workspace == scannedWorkspace {
                    self.recovery = RecoveryCapsule(createdAt: capsule.createdAt, project: capsule.project,
                                                    workspace: capsule.workspace, health: result, session: capsule.session)
                }
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
