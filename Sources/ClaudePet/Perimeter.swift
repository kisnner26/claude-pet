import Foundation

/// Patrones tipo gitignore: `*` no cruza carpetas, `**` si, `?` es un caracter. Sin barra el patron vale en cualquier carpeta
/// (`.env*` protege `.env` y `app/.env.local`). No distingue mayusculas, como el disco de macOS.
enum Glob {
    static func matches(_ pattern: String, _ path: String) -> Bool {
        var p = pattern.lowercased().trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        if p.hasPrefix("./") { p.removeFirst(2) }
        if p.hasSuffix("/") { p += "**" }
        if !p.contains("/") { p = "**/" + p }
        let pat = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let parts = path.lowercased().split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return match(pat[...], parts[...])
    }

    private static func match(_ pat: ArraySlice<String>, _ parts: ArraySlice<String>) -> Bool {
        guard let head = pat.first else { return parts.isEmpty }
        if head == "**" {
            let rest = pat.dropFirst()
            if rest.isEmpty { return true }
            var i = parts.startIndex
            while true {
                if match(rest, parts[i...]) { return true }
                if i == parts.endIndex { return false }
                i += 1
            }
        }
        guard let first = parts.first, segment(Array(head.unicodeScalars), Array(first.unicodeScalars)) else { return false }
        return match(pat.dropFirst(), parts.dropFirst())
    }

    private static func segment(_ p: [Unicode.Scalar], _ s: [Unicode.Scalar]) -> Bool {
        var pi = 0, si = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "*" { star = pi; mark = si; pi += 1 }
            else if pi < p.count, p[pi] == "?" || p[pi] == s[si] { pi += 1; si += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; si = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

enum PerimeterVerdict: Equatable {
    case none                      // ningun perimetro cubre este archivo, o no es una edicion
    case inside
    case outside(String)           // el perimetro tiene una lista de permitidos y el archivo no esta en ella
    case protected(String)         // coincide con un patron protegido

    var isViolation: Bool { switch self { case .outside, .protected: return true; default: return false } }
    var reason: String {
        switch self {
        case .outside(let p): return "fuera del perímetro: \(p)"
        case .protected(let g): return "archivo protegido (\(g))"
        default: return ""
        }
    }
}

/// Por donde puede moverse un agente dentro de un proyecto. Se comprueba en el permiso, antes de que el cambio ocurra.
struct Perimeter: Codable, Equatable, Identifiable {
    enum Mode: String, Codable, CaseIterable {
        case ask = "avisar"       // el permiso se muestra en rojo y nunca se aprueba solo
        case block = "bloquear"   // se deniega sin preguntar
    }
    var root: String
    /// Rutas relativas al proyecto donde si puede editar. Vacio = todo el proyecto.
    var allow: [String] = []
    /// Patrones que siempre cuentan como violacion, aunque esten dentro de `allow`.
    var protect: [String] = Perimeter.defaultProtect
    var mode: Mode = .ask
    var id: String { root }

    static let defaultProtect = [".env*", "**/*.pem", "**/*.key", "**/id_rsa*", ".git/**", ".github/**"]
    static let maxGlobs = 30, maxGlobLength = 120
    static let editTools: Set<String> = ["edit", "write", "multiedit", "notebookedit"]

    /// Quita `.` y `..` y enlaces simbolicos para que `proyecto/../otro` no pase por dentro.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func evaluate(tool: String, path: String) -> PerimeterVerdict {
        guard Self.editTools.contains(tool.lowercased()), path.hasPrefix("/") else { return .none }
        let r = Self.canonical(root), f = Self.canonical(path)
        guard f.hasPrefix(r.hasSuffix("/") ? r : r + "/") else { return .none }
        let rel = String(f.dropFirst(r.hasSuffix("/") ? r.count : r.count + 1))
        if let hit = protect.first(where: { Glob.matches($0, rel) }) { return .protected(hit) }
        if !allow.isEmpty, !allow.contains(where: { Glob.matches($0, rel) || Glob.matches($0 + "/**", rel) }) { return .outside(rel) }
        return .inside
    }

    var isValid: Bool {
        root.hasPrefix("/") && root.count < 500 && allow.count <= Self.maxGlobs && protect.count <= Self.maxGlobs
            && (allow + protect).allSatisfy { !$0.isEmpty && $0.count <= Self.maxGlobLength && !$0.contains(where: \.isNewline) }
    }
}

/// Perimetros guardados en ~/.claude-pet/perimeters.json (permisos 0600).
final class PerimeterStore {
    static let shared = PerimeterStore(path: PerimeterStore.path)
    static let maxPerimeters = 20
    static var path: String { ProcessInfo.processInfo.environment["CLAUDE_PET_PERIMETERS"] ?? (NSHomeDirectory() + "/.claude-pet/perimeters.json") }

    private(set) var perimeters: [Perimeter] = []
    private let lock = NSLock()
    var onChange: (() -> Void)?
    /// Donde se guarda. nil = solo en memoria (las pruebas no deben tocar el archivo real del usuario).
    var storagePath: String?

    init(path: String? = PerimeterStore.path) { storagePath = path }

    func all() -> [Perimeter] { lock.lock(); defer { lock.unlock() }; return perimeters }

    func perimeter(covering path: String) -> Perimeter? {
        let f = Perimeter.canonical(path)
        return all().filter { let r = Perimeter.canonical($0.root); return f == r || f.hasPrefix(r.hasSuffix("/") ? r : r + "/") }
            .max { $0.root.count < $1.root.count }
    }

    /// El perimetro mas especifico que cubre el archivo decide.
    func verdict(tool: String, detail: String) -> PerimeterVerdict {
        guard Perimeter.editTools.contains(tool.lowercased()), detail.hasPrefix("/"), let p = perimeter(covering: detail) else { return .none }
        return p.evaluate(tool: tool, path: detail)
    }
    func verdict(for ask: PermissionAsk) -> PerimeterVerdict { verdict(tool: ask.tool, detail: ask.detail) }

    @discardableResult
    func upsert(_ p: Perimeter) -> Bool {
        guard p.isValid else { return false }
        lock.lock()
        if let i = perimeters.firstIndex(where: { $0.root == p.root }) { perimeters[i] = p }
        else { guard perimeters.count < Self.maxPerimeters else { lock.unlock(); return false }; perimeters.append(p) }
        lock.unlock(); save(); onChange?(); return true
    }

    func remove(root: String) {
        lock.lock(); perimeters.removeAll { $0.root == root }; lock.unlock(); save(); onChange?()
    }

    func load(path: String? = nil) {
        guard let path = path ?? storagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 256 * 1024,
              let decoded = try? JSONDecoder().decode([Perimeter].self, from: data) else { return }
        lock.lock(); perimeters = Array(decoded.filter(\.isValid).prefix(Self.maxPerimeters)); lock.unlock()
    }

    func save(path: String? = nil) {
        guard let path = path ?? storagePath else { return }
        lock.lock(); let snapshot = perimeters; lock.unlock()
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder.pretty.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        chmod(path, 0o600)
    }
}

extension PerimeterStore {
    /// Veredicto y modo del perimetro que cubre el permiso; nil si ninguno lo cubre.
    func check(_ ask: PermissionAsk) -> (verdict: PerimeterVerdict, mode: Perimeter.Mode)? {
        guard let p = perimeter(covering: ask.detail), case let v = p.evaluate(tool: ask.tool, path: ask.detail), v != .none else { return nil }
        return (v, p.mode)
    }
}

/// Que hacer con los permisos que acaban de llegar: el perimetro manda sobre las reglas de aprobacion.
enum PermissionGate {
    enum Action: Equatable {
        case deny(id: String, reason: String)
        case allowByRule(id: String)
        case none
    }

    static func decide(asks: [PermissionAsk], check: (PermissionAsk) -> (verdict: PerimeterVerdict, mode: Perimeter.Mode)?, ruleMatches: (PermissionAsk) -> Bool) -> Action {
        for ask in asks {
            if let c = check(ask), c.verdict.isViolation, c.mode == .block { return .deny(id: ask.id, reason: c.verdict.reason) }
        }
        // una regla vigente responde sola, salvo que el archivo rompa el perimetro: ahi siempre decide una persona
        if let ask = asks.first(where: { a in !(check(a)?.verdict.isViolation ?? false) && ruleMatches(a) }) { return .allowByRule(id: ask.id) }
        return .none
    }
}
