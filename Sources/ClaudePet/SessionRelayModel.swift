import Foundation

@MainActor
final class SessionRelayModel: ObservableObject {
    @Published var source: Agent = .codex {
        didSet { if oldValue != source { selectedID = ""; query = ""; error = nil } }
    }
    @Published var selectedID = "" {
        didSet { if oldValue != selectedID { workspace = ""; error = nil } }
    }
    @Published var query = ""
    @Published var workspace = ""
    @Published var context = ""
    @Published var prompt = ""
    @Published var manual = false
    @Published private(set) var sessions: [LocalAgentSession] = []
    @Published private(set) var busy = false
    @Published private(set) var capsule: SessionCapsule?
    @Published private(set) var summary = ""
    @Published private(set) var savedURL: URL?
    @Published private(set) var error: String?
    @Published private(set) var status: String?
    private let relay: SessionRelayController
    private var generation = UUID()

    init(relay: SessionRelayController) { self.relay = relay }
    var selected: LocalAgentSession? { sessions.first { $0.id == selectedID && $0.agent == source } }
    var projectPath: String { workspace.isEmpty ? selected?.workspace ?? "" : workspace }
    var visibleSessions: [LocalAgentSession] {
        sessions.filter { $0.agent == source && (query.isEmpty || "\($0.title) \($0.workspace)".localizedStandardContains(query)) }
    }
    var canPrepare: Bool {
        !busy && (manual ? !workspace.isEmpty && !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selected != nil)
    }

    func reload() async {
        guard !busy, capsule == nil else { return }
        busy = true
        error = nil
        let token = UUID(); generation = token
        let worker = Task.detached(priority: .userInitiated) {
            LocalAgentSessionReader.recent(for: .claude) + LocalAgentSessionReader.recent(for: .codex)
        }
        let found = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard token == generation else { return }
        sessions = found
        if selected == nil { selectedID = "" }
        busy = false
    }

    func chooseProject() {
        guard let path = relay.chooseProject(suggested: projectPath) else { return }
        workspace = path
        error = nil
    }

    func enterManual() {
        let path = projectPath
        selectedID = ""
        workspace = path
        manual = true
        error = nil
    }

    func prepare() async {
        guard canPrepare else { return }
        busy = true; error = nil; status = nil
        let source = source, path = projectPath, session = selected, manual = manual, context = context
        let worker = Task.detached(priority: .userInitiated) { () throws -> (SessionCapsule, String, String) in
            let excerpt: SessionExcerpt?
            if manual { excerpt = nil }
            else {
                guard let session else { throw LocalAgentSessionError.noMessages }
                excerpt = try LocalAgentSessionReader.excerpt(session)
            }
            let capsule = try SessionCapsuleFactory.make(source: source, workspace: path, project: "", task: excerpt?.text ?? context, state: .idle, health: GitPulse.scan(path))
            return (capsule, SessionCapsulePrompt.build(capsule, destination: source.other), excerpt?.description ?? "contexto manual")
        }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            capsule = result.0; prompt = result.1; summary = result.2; savedURL = nil
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
        busy = false
    }

    func back() { capsule = nil; savedURL = nil; error = nil; status = nil }

    func useLatest() {
        do {
            let item = try SessionCapsuleStore.latest()
            source = item.capsule.source
            selectedID = ""
            workspace = item.capsule.workspace
            context = item.capsule.task
            manual = true
            capsule = item.capsule
            prompt = SessionCapsulePrompt.build(item.capsule, destination: item.capsule.source.other)
            savedURL = item.url
            summary = "relevo guardado · \(item.capsule.project)"
            error = nil; status = nil
        } catch { self.error = error.localizedDescription }
    }

    func complete(open: Bool) async {
        guard let capsule, !busy, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; error = nil; status = nil
        do {
            savedURL = try relay.saveAndCopy(capsule, prompt: prompt)
            status = "contexto copiado. pégalo con cmd+v en \(capsule.source.other.rawValue)."
            if open { try await relay.launch(capsule.source.other) }
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    func reveal() { relay.revealLatest() }
}
