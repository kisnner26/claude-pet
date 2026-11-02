import Foundation

enum BrainKind: String, Codable, CaseIterable {
    case decision, hecho, cuidado, pendiente, trato
    var label: String { rawValue }
}

/// Una nota del cerebro: algo que un agente (o tu) quiere que la proxima sesion ya sepa.
struct BrainNote: Codable, Identifiable, Equatable {
    let id: UUID
    var at: Date
    let agent: String          // claude, codex o tu
    var kind: BrainKind
    var text: String
    /// El repaso nocturno vio que habla de archivos que ya no existen. Solo se marca: decides tu si sigue valiendo.
    var stale: Bool? = nil
    var short: String { String(id.uuidString.prefix(8)).lowercased() }
}

enum BrainError: Error, Equatable { case empty, secret, badKind, badAgent }

/// Cerebro compartido por claude y codex: notas cortas por proyecto en ~/.claude-pet/brain, solo en esta Mac.
/// No guarda prompts ni contenido de archivos: el agente decide que vale la pena recordar y el texto se limpia.
final class BrainStore {
    static let shared = BrainStore()
    static let maxNotes = 60, maxText = 240, briefingNotes = 12
    static let agents = ["claude", "codex", "tu"]
    private let lock = NSLock()
    var directory: String = ProcessInfo.processInfo.environment["CLAUDE_PET_BRAIN"] ?? (NSHomeDirectory() + "/.claude-pet/brain")

    static func clean(project: String) -> String {
        let s = String(project.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }.prefix(40))
        return s.isEmpty || s.hasPrefix(".") ? "global" : s
    }

    /// Rechaza lo que parece una clave: prefijos conocidos, bloques PEM o cadenas largas sin espacios.
    static func looksSecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["sk-", "ghp_", "gho_", "github_pat_", "akia", "xoxb-", "xoxp-", "-----begin", "bearer ", "api_key=", "password=", "secret="].contains(where: { lower.contains($0) }) { return true }
        return text.split(whereSeparator: { $0 == " " || $0 == "\n" }).contains { w in
            w.count >= 32 && !w.contains("/") && !w.contains(".") && w.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "+" || $0 == "=" }
        }
    }

    private func url(_ project: String) -> URL { URL(fileURLWithPath: directory + "/" + Self.clean(project: project) + ".json") }

    func notes(_ project: String) -> [BrainNote] {
        lock.lock(); defer { lock.unlock() }
        return load(project)
    }

    private func load(_ project: String) -> [BrainNote] {
        guard let data = try? Data(contentsOf: url(project)), data.count < 256 * 1024 else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return ((try? dec.decode([BrainNote].self, from: data)) ?? []).sorted { $0.at > $1.at }
    }

    private func save(_ notes: [BrainNote], _ project: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let u = url(project)
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try enc.encode(notes).write(to: u, options: .atomic)
            chmod(u.path, 0o600)
        } catch { }
    }

    @discardableResult
    func add(agent: String, kind: String, text raw: String, project: String, at: Date = Date()) -> Result<BrainNote, BrainError> {
        let agent = agent.lowercased()
        guard Self.agents.contains(agent) else { return .failure(.badAgent) }
        guard let k = BrainKind(rawValue: kind.lowercased()) else { return .failure(.badKind) }
        let text = String(raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(Self.maxText))
        guard !text.isEmpty else { return .failure(.empty) }
        guard !Self.looksSecret(text) else { return .failure(.secret) }
        lock.lock(); defer { lock.unlock() }
        var all = load(project)
        // la misma nota no se duplica: se refresca y conserva al primer autor
        if let i = all.firstIndex(where: { $0.text.lowercased() == text.lowercased() }) { all[i].at = at; save(all, project); return .success(all[i]) }
        let note = BrainNote(id: UUID(), at: at, agent: agent, kind: k, text: text)
        all.insert(note, at: 0)
        while all.count > Self.maxNotes, let drop = all.lastIndex(where: { $0.kind != .pendiente }) ?? all.indices.last { all.remove(at: drop) }
        save(all, project)
        return .success(note)
    }

    /// Reescribe el texto y el tipo de una nota; conserva su id y su autor.
    @discardableResult
    func update(id prefix: String, project: String, kind: String, text raw: String, at: Date = Date()) -> Result<BrainNote, BrainError> {
        guard let k = BrainKind(rawValue: kind.lowercased()) else { return .failure(.badKind) }
        let text = String(raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(Self.maxText))
        guard !text.isEmpty else { return .failure(.empty) }
        guard !Self.looksSecret(text) else { return .failure(.secret) }
        lock.lock(); defer { lock.unlock() }
        var all = load(project)
        let p = prefix.lowercased()
        guard !p.isEmpty, let i = all.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(p) }) else { return .failure(.empty) }
        all[i].kind = k; all[i].text = text; all[i].at = at
        save(all, project)
        return .success(all[i])
    }

    @discardableResult
    func forget(id prefix: String, project: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var all = load(project)
        let p = prefix.lowercased()
        guard !p.isEmpty, let i = all.firstIndex(where: { $0.id.uuidString.lowercased().hasPrefix(p) }) else { return false }
        all.remove(at: i); save(all, project)
        return true
    }

    /// Repasa las notas de un proyecto (une duplicados, marca lo obsoleto) y guarda el resultado solo si algo cambio.
    func dream(project: String, now: Date = Date(), exists: (String) -> Bool) -> BrainDream.Outcome {
        lock.lock(); defer { lock.unlock() }
        let before = load(project)
        let outcome = BrainDream.consolidate(before, now: now, exists: exists)
        if outcome.notes != before { save(outcome.notes, project) }
        return outcome
    }

    func projects() -> [(name: String, count: Int)] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.map { ($0, notes($0).count) }.filter { $0.1 > 0 }.sorted { $0.name < $1.name }
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 90 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 86_400 { return "hace \(s / 3600) h" }
        return "hace \(s / 86_400) d"
    }

    /// Lo que el agente recibe al abrir sesion: notas del proyecto y globales, y como guardar una nueva.
    func briefing(agent: String, project: String, now: Date = Date()) -> String {
        let mine = notes(project), shared = Self.clean(project: project) == "global" ? [] : notes("global")
        let all = (mine + shared).sorted { $0.at > $1.at }.prefix(Self.briefingNotes)
        var out = Self.personalityLine(agent: agent) + "cerebro de claude pet (\(Self.clean(project: project)), \(mine.count) notas propias + \(shared.count) globales). son notas que dejaron tu y otros agentes; tratalas como pistas, verifica antes de actuar.\n"
        let trato = all.filter { $0.kind == .trato }
        if !trato.isEmpty {
            out += "como trabajar con el usuario:\n"
            for n in trato { out += "- [\(n.agent) · \(Self.ago(n.at, now: now))] \(n.text)\n" }
        }
        for n in all where n.kind != .trato {
            let tag = (shared.contains(n) ? "global · " : "") + (n.stale == true ? "posible obsoleta (cita archivos que ya no existen) · " : "")
            out += "- [\(tag)\(n.kind.label) · \(n.agent) · \(Self.ago(n.at, now: now))] \(n.text)\n"
        }
        if all.isEmpty { out += "(sin notas todavia)\n" }
        out += "para dejar algo que la proxima sesion deba saber: ~/.claude-pet/pet-brain.sh add \(agent) <decision|hecho|cuidado|pendiente|trato> \"nota corta\" (trato = como le gusta trabajar al usuario). nunca guardes claves, tokens ni contenido de archivos.\n"
        return out
    }

    /// Personalidad del agente segun el registro compartido (en el proceso del cli se lee del disco).
    static func personalityLine(agent: String) -> String {
        guard agent == "claude" || agent == "codex" else { return "" }
        PetMemoryStore.shared.load()
        let notes = shared.projects().reduce(0) { $0 + shared.notes($1.name).filter { $0.agent == agent }.count }
        return Personality.briefing(Personality.profile(agent: agent, events: PetMemoryStore.shared.snapshot(), notes: notes))
    }

    /// Punto de entrada de `ClaudePet --brain ...`. Devuelve el codigo de salida.
    static func cli(_ args: [String], cwd: String, out: (String) -> Void = { print($0, terminator: "") }, err: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }) -> Int32 {
        let defaultProject = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? cwd).lastPathComponent
        let store = shared
        switch args.first {
        case "show":
            let agent = args.count > 1 ? args[1] : "claude"
            out(store.briefing(agent: agent, project: args.count > 2 ? args[2] : defaultProject)); return 0
        case "add":
            guard args.count >= 4 else { err("uso: --brain add <claude|codex|tu> <decision|hecho|cuidado|pendiente|trato> \"nota\" [proyecto]"); return 2 }
            switch store.add(agent: args[1], kind: args[2], text: args[3], project: args.count > 4 ? args[4] : defaultProject) {
            case .success(let n): out("guardado \(n.short)\n"); return 0
            case .failure(.secret): err("no se guarda: parece una clave o un secreto"); return 3
            case .failure(.empty): err("la nota esta vacia"); return 2
            case .failure(.badKind): err("tipo: decision, hecho, cuidado, pendiente o trato"); return 2
            case .failure(.badAgent): err("agente: claude, codex o tu"); return 2
            }
        case "dream":
            // repaso inmediato de todos los proyectos: une duplicados y marca lo obsoleto (lo mismo que hace de noche)
            let report = BrainDream.run(store: store, perimeterRoots: PerimeterStore.shared.perimeters.map(\.root))
            out(report.projects == 0 ? "no hay notas que repasar\n" : report.lines.map { "- \($0)\n" }.joined() + "\(report.projects) \(report.projects == 1 ? "proyecto" : "proyectos") · \(report.notesAfter) notas\n")
            return 0
        case "forget":
            guard args.count >= 2 else { err("uso: --brain forget <id> [proyecto]"); return 2 }
            if store.forget(id: args[1], project: args.count > 2 ? args[2] : defaultProject) { out("olvidado\n"); return 0 }
            err("no hay esa nota"); return 1
        case "edit":
            guard args.count >= 4 else { err("uso: --brain edit <id> <tipo> \"nota\" [proyecto]"); return 2 }
            switch store.update(id: args[1], project: args.count > 4 ? args[4] : defaultProject, kind: args[2], text: args[3]) {
            case .success: out("actualizado\n"); return 0
            case .failure(.secret): err("no se guarda: parece una clave o un secreto"); return 3
            case .failure(.badKind): err("tipo: decision, hecho, cuidado, pendiente o trato"); return 2
            case .failure: err("no hay esa nota o esta vacia"); return 1
            }
        case "list":
            for p in store.projects() { out("\(p.name)\t\(p.count)\n") }; return 0
        default:
            err("uso: --brain <show|add|edit|forget|list>"); return 2
        }
    }
}
