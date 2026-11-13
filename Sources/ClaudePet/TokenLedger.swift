import Foundation

struct SessionTokens: Equatable, Identifiable {
    let id: String            // primeros 8 caracteres del nombre del transcript
    let project: String       // ultimo componente de la carpeta de trabajo
    let usage: TokenUsage
    let modified: Date
    let workspace: String?    // carpeta completa, solo en memoria (para auditar su CLAUDE.md)
    let started: Date?
    let partial: Bool         // el transcript era mayor que el tope y se leyo solo la parte final
}

struct ProjectTokens: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let usage: TokenUsage
    let sessions: Int
    let workspace: String?
}

struct TokenSnapshot: Equatable {
    var sessions: [SessionTokens] = []
    var projects: [ProjectTokens] = []
    var total: TokenUsage { sessions.reduce(TokenUsage()) { $0 + $1.usage } }
    var isEmpty: Bool { sessions.isEmpty }

    static func build(_ sessions: [SessionTokens]) -> TokenSnapshot {
        let ordered = sessions.sorted { $0.modified > $1.modified }
        var byProject: [String: (TokenUsage, Int, String?)] = [:]
        for s in ordered { let old = byProject[s.project] ?? (TokenUsage(), 0, nil); byProject[s.project] = (old.0 + s.usage, old.1 + 1, old.2 ?? s.workspace) }
        let projects = byProject.map { ProjectTokens(name: $0.key, usage: $0.value.0, sessions: $0.value.1, workspace: $0.value.2) }
            .sorted { ($0.usage.total, $1.name) > ($1.usage.total, $0.name) }
        return TokenSnapshot(sessions: ordered, projects: projects)
    }
}

/// Mide el gasto leyendo los transcripts locales de forma incremental: de cada archivo recuerda hasta donde leyo y la
/// siguiente pasada solo lee lo nuevo. Se llama a peticion (al abrir la pagina o con el boton), nunca en bucle.
/// Solo se queda con contadores; no guarda mensajes, comandos ni rutas completas, y no escribe nada a disco.
actor TokenLedger {
    struct Limits {
        var maxFiles = 40
        var maxAge: TimeInterval = 14 * 86_400
        var maxBytesPerFile = 48 * 1024 * 1024
        var chunk = 4 * 1024 * 1024
    }

    private struct FileState {
        var offset: UInt64 = 0
        var acc = TokenUsageParser.Accumulator()
        var partial = false
        var modified = Date.distantPast
        var started: Date?
    }

    private let root: URL
    private let limits: Limits
    private var files: [String: FileState] = [:]

    init(root: URL = LocalAgentSessionReader.claudeRoot, limits: Limits = Limits()) {
        self.root = root
        self.limits = limits
    }

    func refresh(now: Date = Date()) -> TokenSnapshot {
        let candidates = recentTranscripts(now: now)
        var live = Set<String>()
        var out: [SessionTokens] = []
        for (url, modified, folder) in candidates {
            if Task.isCancelled { break }
            let key = url.path
            live.insert(key)
            var state = files[key] ?? FileState()
            state.modified = modified
            if state.started == nil { state.started = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate }
            advance(&state, url: url)
            files[key] = state
            let name = state.acc.project ?? folder
            out.append(SessionTokens(id: String(url.deletingPathExtension().lastPathComponent.prefix(8)), project: name,
                                     usage: state.acc.usage, modified: modified, workspace: state.acc.workspace, started: state.started, partial: state.partial))
        }
        for key in files.keys where !live.contains(key) { files[key] = nil }
        return .build(out.filter { $0.usage.total > 0 })
    }

    private func recentTranscripts(now: Date) -> [(URL, Date, String)] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var found: [(URL, Date, String)] = []
        for case let url as URL in walker {
            if Task.isCancelled { break }
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let date = values.contentModificationDate,
                  now.timeIntervalSince(date) <= limits.maxAge else { continue }
            let folder = url.deletingLastPathComponent().lastPathComponent.split(separator: "-").last.map(String.init) ?? "proyecto"
            found.append((url, date, folder))
        }
        return Array(found.sorted { $0.1 > $1.1 }.prefix(limits.maxFiles))
    }

    /// Lee desde el desplazamiento guardado solo lineas completas.
    private func advance(_ state: inout FileState, url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url), let end = try? handle.seekToEnd() else { return }
        defer { try? handle.close() }
        if end < state.offset { state = FileState(modified: state.modified) }   // el archivo se rehizo
        var position = state.offset
        if position == 0, end > UInt64(limits.maxBytesPerFile) {
            position = end - UInt64(limits.maxBytesPerFile)
            state.partial = true
            skipToLineStart(handle, &position, end)
        }
        var consumedBudget = 0
        while position < end, consumedBudget < limits.maxBytesPerFile {
            if Task.isCancelled { break }
            guard (try? handle.seek(toOffset: position)) != nil,
                  let data = try? handle.read(upToCount: limits.chunk), !data.isEmpty else { break }
            consumedBudget += data.count
            // solo hasta la ultima linea completa
            guard let lastNewline = data.lastIndex(of: 10) else {
                if position + UInt64(data.count) >= end { break }          // linea a medio escribir: la siguiente pasada
                position += UInt64(data.count); continue                    // linea gigante sin salto: se salta
            }
            let usable = data[data.startIndex...lastNewline]
            for line in usable.split(separator: 10) where Self.mentionsUsage(line) {
                if let row = SessionJSONLines.object(Data(line)), let parsed = TokenUsageParser.parse(row) { state.acc.add(parsed) }
            }
            position += UInt64(usable.count)
        }
        state.offset = position
    }

    private func skipToLineStart(_ handle: FileHandle, _ position: inout UInt64, _ end: UInt64) {
        guard (try? handle.seek(toOffset: position)) != nil, let data = try? handle.read(upToCount: 1 << 20),
              let nl = data.firstIndex(of: 10) else { return }
        position += UInt64(nl - data.startIndex + 1)
    }

    private static let needle = Array("\"usage\"".utf8)
    static func mentionsUsage(_ line: Data) -> Bool {
        line.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return false }
            return needle.withUnsafeBytes { memmem(base, buf.count, $0.baseAddress!, needle.count) != nil }
        }
    }
}
