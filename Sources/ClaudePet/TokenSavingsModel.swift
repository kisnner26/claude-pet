import SwiftUI
import AppKit

enum TokenFormat {
    /// 1 234 -> "1,2 k"; 3 400 000 -> "3,4 M". Cifras cortas para tarjetas.
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return trim(Double(n) / 1_000_000) + " M" }
        if n >= 10_000 { return "\(Int((Double(n) / 1_000).rounded())) k" }
        if n >= 1_000 { return trim(Double(n) / 1_000) + " k" }
        return "\(n)"
    }
    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s).replacingOccurrences(of: ".", with: ",")
    }
}

struct ProjectAudit: Identifiable, Equatable {
    let name: String
    let folder: String          // en memoria; nunca se registra
    let audit: ClaudeMdAudit
    var id: String { folder }
}

/// Estado de la pagina «ahorro». La lectura de los transcripts se hace fuera del hilo principal y solo cuando se abre la pagina
/// o se pulsa «actualizar»: no hay temporizador.
@MainActor
final class TokenSavingsModel: ObservableObject {
    static let shared = TokenSavingsModel()

    @Published private(set) var snapshot = TokenSnapshot()
    @Published private(set) var audits: [ProjectAudit] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published var notice: String?

    private let ledger = TokenLedger()
    private var task: Task<Void, Never>?
    /// Capturas de documentacion: datos de ejemplo en lugar de leer los transcripts de quien las hace.
    static let preview = CommandLine.arguments.contains("--snapshot-settings")

    func refresh() {
        guard task == nil else { return }
        if Self.preview { loadPreview(); return }
        loading = true
        let ledger = ledger
        task = Task { [weak self] in
            let snap = await ledger.refresh()
            let audits = await Task.detached(priority: .utility) { Self.audit(snap) }.value
            guard let self else { return }
            self.snapshot = snap
            self.audits = audits
            self.loading = false
            self.loaded = true
            self.task = nil
            SavingsHub.shared.updateMeasurements(snap)
        }
    }

    nonisolated static func audit(_ snap: TokenSnapshot, limit: Int = 8) -> [ProjectAudit] {
        var out: [ProjectAudit] = []
        var isDir: ObjCBool = false
        for p in snap.projects {
            guard out.count < limit, let folder = p.workspace,
                  FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { continue }
            out.append(ProjectAudit(name: p.name, folder: folder, audit: ClaudeMdAudit.audit(folder: URL(fileURLWithPath: folder))))
        }
        return out
    }

    /// Genera el borrador en un archivo nuevo junto al proyecto, tras confirmar. No toca un CLAUDE.md existente.
    func generateDraft(for item: ProjectAudit) {
        let alert = NSAlert()
        alert.messageText = L.t("¿generar un borrador de CLAUDE.md?", "Generate a CLAUDE.md draft?")
        alert.informativeText = L.t("Se creará «\(ProjectSummary.draftName)» dentro de \(item.name), a partir de sus archivos y sin modelo. Si ya existe un CLAUDE.md no se toca.",
                                    "A \"\(ProjectSummary.draftName)\" file will be created inside \(item.name), built from its files with no model. An existing CLAUDE.md is not touched.")
        alert.addButton(withTitle: L.t("generar", "generate"))
        alert.addButton(withTitle: L.t("cancelar", "cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let folder = URL(fileURLWithPath: item.folder)
        let text = ProjectSummary.generate(folder: folder)
        do {
            let url = try ProjectSummary.writeDraft(text, in: folder)
            notice = L.t("borrador escrito en \(url.lastPathComponent) (unos \(TokenEstimate.tokens(text)) tokens) dentro de \(item.name)",
                         "draft written to \(url.lastPathComponent) (about \(TokenEstimate.tokens(text)) tokens) inside \(item.name)")
        } catch {
            notice = L.t("no se pudo escribir el borrador", "could not write the draft")
            Diag.savings.error("borrador: no se pudo escribir \(Diag.code(error), privacy: .public)")
        }
    }

    private func loadPreview() {
        let now = Date()
        func u(_ i: Int, _ r: Int, _ c: Int, _ o: Int) -> TokenUsage { TokenUsage(input: i, cacheRead: r, cacheCreate: c, output: o, messages: 40) }
        let sessions = [
            SessionTokens(id: "a41c9e02", project: "mi-app", usage: u(18_000, 2_940_000, 310_000, 96_000), modified: now, workspace: "/demo/mi-app", started: now.addingTimeInterval(-9_000), partial: false),
            SessionTokens(id: "7be310d5", project: "mi-app", usage: u(9_500, 1_120_000, 150_000, 41_000), modified: now.addingTimeInterval(-86_400), workspace: "/demo/mi-app", started: nil, partial: false),
            SessionTokens(id: "c0d2f7aa", project: "api-pagos", usage: u(220_000, 410_000, 520_000, 63_000), modified: now.addingTimeInterval(-2 * 86_400), workspace: "/demo/api-pagos", started: nil, partial: false),
            SessionTokens(id: "5f19bb73", project: "sitio-web", usage: u(31_000, 760_000, 95_000, 22_000), modified: now.addingTimeInterval(-3 * 86_400), workspace: "/demo/sitio-web", started: nil, partial: true),
        ]
        snapshot = .build(sessions)
        audits = [
            ProjectAudit(name: "mi-app", folder: "/demo/mi-app", audit: ClaudeMdAudit(exists: true, tokens: 5_200, findings: [.veryLong(tokens: 5_200), .agingSection(heading: "Pendientes")])),
            ProjectAudit(name: "api-pagos", folder: "/demo/api-pagos", audit: ClaudeMdAudit(exists: false, tokens: 0, findings: [.missing])),
            ProjectAudit(name: "sitio-web", folder: "/demo/sitio-web", audit: ClaudeMdAudit(exists: true, tokens: 900, findings: [])),
        ]
        loaded = true
    }
}

/// Une las mediciones con el estado en vivo para decidir consejos. Vive en memoria: nada de esto se guarda en disco.
@MainActor
final class SavingsHub {
    static let shared = SavingsHub()
    private var throttle = SavingsAdvisor.Throttle()
    private var firstSeen: [String: Date] = [:]
    private var cacheHit: Double?
    private var cacheSample = 0
    private var clearTask: Task<Void, Never>?

    func updateMeasurements(_ snap: TokenSnapshot) {
        let newest = snap.sessions.first?.usage
        cacheHit = newest?.cacheHitRate
        cacheSample = newest?.promptTotal ?? 0
    }

    /// Entrada para las reglas desde el estado actual (la pagina de ajustes la usa para listar todo lo vigente).
    func input(context: ContextReading?, session: String?, now: Date = Date()) -> AdviceInput {
        var i = AdviceInput()
        i.contextRemainingFraction = context?.remainingFraction
        if let session, let first = firstSeen[session] { i.sessionAge = now.timeIntervalSince(first) }
        i.cacheHitRate = cacheHit
        i.promptTokensMeasured = cacheSample
        return i
    }

    /// Se llama con cada evento de Claude Code. Solo hace algo si el usuario activo «consejos de ahorro».
    /// El texto del prompt se reduce a su forma al instante y no se guarda; del archivo leido solo se mira la extension.
    func observe(session: String, task: String, tool: String, detail: String, context: ContextReading?, publish: @escaping (Advice?) -> Void, now: Date = Date()) {
        if firstSeen[session] == nil {
            if firstSeen.count > 50 { firstSeen.removeAll() }
            firstSeen[session] = now
        }
        guard SavingsPreferences.advice else { return }
        var i = input(context: context, session: session, now: now)
        if task.hasPrefix("p:") {
            let shape = PromptShape.analyze(String(task.dropFirst(2)))
            i.promptWordCount = shape.words
            i.promptIsGeneric = shape.generic
        }
        if tool == "Read", !detail.isEmpty { i.lastFileExtension = (detail as NSString).pathExtension }
        guard let advice = SavingsAdvisor.next(i, throttle: &throttle, now: now) else { return }
        publish(advice)
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
            if !Task.isCancelled { publish(nil) }
        }
    }
}
