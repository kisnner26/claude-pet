import Foundation

struct DayStats: Codable, Equatable {
    var sessions = 0
    var tools = 0
    var permissions = 0
    var errors = 0
    var agents: [String: Int] = [:]
    var projects: [String: Int] = [:]
    var activity: Int { sessions + tools + permissions }
}

struct WeeklyRecap: Equatable {
    var sessions = 0, tools = 0, permissions = 0, errors = 0
    var activeDays = 0
    var busiestDay: String?
    var topAgent: String?
    var topProject: String?
    var streak = 0
    var level = 1

    /// Texto para pegar en cualquier sitio. `showProject` apaga el nombre del proyecto al compartir.
    func markdown(showProject: Bool) -> String {
        var lines = ["# resumen de la semana", "",
                     "- sesiones terminadas: \(sessions)", "- herramientas usadas: \(tools)", "- permisos respondidos: \(permissions)", "- errores: \(errors)",
                     "- dias con actividad: \(activeDays) de 7", "- racha: \(streak) \(streak == 1 ? "dia" : "dias")", "- nivel: \(level)"]
        if let d = busiestDay { lines.append("- dia mas activo: \(d)") }
        if let a = topAgent { lines.append("- agente mas usado: \(a)") }
        if showProject, let p = topProject { lines.append("- proyecto mas usado: \(p)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Contadores diarios locales. Guardan numeros y nombres de agente y proyecto, nunca contenido, comandos ni rutas.
final class ActivityStats {
    static let shared = ActivityStats()
    static let keepDays = 120
    private(set) var days: [String: DayStats] = [:]
    private let lock = NSLock()
    var calendar = Calendar(identifier: .gregorian)

    static var path: String { (ProcessInfo.processInfo.environment["CLAUDE_PET_STATS"] ?? (NSHomeDirectory() + "/.claude-pet/stats")) + "/days.json" }

    func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func mutate(_ date: Date, _ body: (inout DayStats) -> Void) {
        lock.lock(); var d = days[key(date)] ?? DayStats(); body(&d); days[key(date)] = d; lock.unlock()
    }

    private static func clean(_ name: String) -> String { String(name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }.prefix(40)) }

    func recordTool(agent: String, project: String, at date: Date = Date()) {
        mutate(date) { $0.tools += 1; $0.agents[Self.clean(agent), default: 0] += 1; if !project.isEmpty { $0.projects[Self.clean(project), default: 0] += 1 } }
    }
    func recordFinished(agent: String, project: String, at date: Date = Date()) {
        mutate(date) { $0.sessions += 1; $0.agents[Self.clean(agent), default: 0] += 1; if !project.isEmpty { $0.projects[Self.clean(project), default: 0] += 1 } }
    }
    func recordPermission(at date: Date = Date()) { mutate(date) { $0.permissions += 1 } }
    func recordError(at date: Date = Date()) { mutate(date) { $0.errors += 1 } }

    /// Dias consecutivos con actividad que terminan hoy (o ayer, si hoy aun no hubo).
    func streak(asOf date: Date = Date()) -> Int {
        lock.lock(); defer { lock.unlock() }
        var day = date, count = 0
        if (days[key(day)]?.activity ?? 0) == 0 { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        while (days[key(day)]?.activity ?? 0) > 0 { count += 1; day = calendar.date(byAdding: .day, value: -1, to: day) ?? day; if count > 4000 { break } }
        return count
    }

    /// Nivel por actividad real: cada sesion terminada vale 10 y cada dia activo 5. Nunca sube por tiempo inactivo ni por clics.
    static func level(sessions: Int, activeDays: Int) -> Int { Int(Double((sessions * 10 + activeDays * 5) / 20).squareRoot()) + 1 }

    func recap(endingAt date: Date = Date()) -> WeeklyRecap {
        lock.lock(); let snapshot = days; lock.unlock()
        var r = WeeklyRecap(), agents: [String: Int] = [:], projects: [String: Int] = [:], best = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date), let d = snapshot[key(day)] else { continue }
            r.sessions += d.sessions; r.tools += d.tools; r.permissions += d.permissions; r.errors += d.errors
            if d.activity > 0 { r.activeDays += 1 }
            if d.activity > best { best = d.activity; r.busiestDay = day.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "es"))) }
            for (k, v) in d.agents { agents[k, default: 0] += v }
            for (k, v) in d.projects { projects[k, default: 0] += v }
        }
        r.topAgent = agents.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
        r.topProject = projects.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
        r.streak = streak(asOf: date)
        let total = snapshot.values.reduce(0) { $0 + $1.sessions }, active = snapshot.values.filter { $0.activity > 0 }.count
        r.level = Self.level(sessions: total, activeDays: active)
        return r
    }

    func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)), data.count < 2 * 1024 * 1024,
              let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data) else { return }
        lock.lock(); days = decoded; lock.unlock()
    }

    func save(now: Date = Date()) {
        lock.lock()
        if days.count > Self.keepDays { for k in days.keys.sorted().dropLast(Self.keepDays) { days[k] = nil } }
        let snapshot = days
        lock.unlock()
        let url = URL(fileURLWithPath: Self.path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            chmod(Self.path, 0o600)
        } catch { }
    }

    func reset() { lock.lock(); days = [:]; lock.unlock(); save() }
}
