import Foundation

/// Consumo del plan de Claude: ventana de 5 horas y semanal. Los datos los entrega Claude Code a su statusline
/// (`rate_limits`); `hooks/pet-statusline.sh` los copia a `~/.claude-pet/usage.json` y aqui solo se leen.
struct PlanWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?

    /// Si la ventana ya se reinicio, el porcentaje guardado es de la anterior.
    func effectivePercent(now: Date) -> Double {
        if let r = resetsAt, r <= now { return 0 }
        return min(100, max(0, usedPercent))
    }
    func remainingPercent(now: Date) -> Int { Int((100 - effectivePercent(now: now)).rounded()) }
    func resetText(now: Date) -> String? {
        guard let r = resetsAt, r > now else { return nil }
        let m = Int(r.timeIntervalSince(now) / 60)
        if m >= 2880 { return "\(m / 1440) d" }
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m" }
        return "\(max(1, m)) m"
    }
}

enum PlanPressure: Equatable { case normal, caution, critical }

struct PlanUsage: Equatable {
    var five: PlanWindow?
    var week: PlanWindow?
    var readAt: Date

    /// Claude Code solo refresca el statusline mientras trabaja: pasada una hora sin datos se avisa de que la cifra puede estar vieja.
    static let staleAfter: TimeInterval = 3600
    func isStale(now: Date) -> Bool { now.timeIntervalSince(readAt) > Self.staleAfter }

    func pressure(now: Date, caution: Double = 80, critical: Double = 95) -> PlanPressure {
        let worst = [five, week].compactMap { $0?.effectivePercent(now: now) }.max() ?? 0
        return worst >= critical ? .critical : worst >= caution ? .caution : .normal
    }

    /// Entradas: el JSON que escribe el script. Devuelve nil si no hay ninguna ventana valida.
    static func parse(_ data: Data) -> PlanUsage? {
        guard data.count < 4096, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> PlanWindow? {
            guard let w = o[key] as? [String: Any], let p = (w["p"] as? NSNumber)?.doubleValue, p.isFinite else { return nil }
            var date: Date?
            if let r = w["r"] as? NSNumber { let v = r.doubleValue; date = Date(timeIntervalSince1970: v > 1e12 ? v / 1000 : v) }
            else if let s = w["r"] as? String { date = ISO8601DateFormatter().date(from: s) ?? Double(s).map { Date(timeIntervalSince1970: $0) } }
            return PlanWindow(usedPercent: p, resetsAt: date)
        }
        let five = window("five"), week = window("week")
        guard five != nil || week != nil else { return nil }
        let at = (o["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        return PlanUsage(five: five, week: week, readAt: at)
    }
}

/// Avisa una sola vez por umbral y ventana: al cruzar el 80 % y el 95 %, y vuelve a avisar cuando la ventana se reinicia.
struct PlanAlertPolicy {
    var thresholds: [Int] = [80, 95]
    private var sent: Set<String> = []

    mutating func alerts(for usage: PlanUsage, now: Date) -> [String] {
        var out: [String] = []
        for (name, w) in [("5 horas", usage.five), ("semanal", usage.week)] {
            guard let w else { continue }
            let key = name + String(Int(w.resetsAt?.timeIntervalSince1970 ?? 0))
            let pct = w.effectivePercent(now: now)
            for t in thresholds.sorted(by: >) where pct >= Double(t) {
                let id = "\(key)-\(t)"
                if sent.contains(id) { break }
                // si ya se envio uno mayor no se repite uno menor
                for lower in thresholds where lower <= t { sent.insert("\(key)-\(lower)") }
                let left = w.remainingPercent(now: now)
                out.append("límite \(name): queda el \(left)%" + (w.resetText(now: now).map { " · se reinicia en \($0)" } ?? ""))
                break
            }
        }
        if sent.count > 64 { sent.removeAll() }
        return out
    }
}

@MainActor
final class PlanUsageMonitor: ObservableObject {
    @Published private(set) var usage: PlanUsage?
    @Published private(set) var alert: String?
    /// Cada aviso nuevo del plan (80 % y 95 %): lo usa claude pet para avisar tambien al telefono.
    var onAlert: ((String) -> Void)?
    private var policy = PlanAlertPolicy()
    private var timer: Timer?
    private var lastModified: Date?
    private var alertTask: Task<Void, Never>?
    private let path: String?

    nonisolated static var defaultPath: String { ProcessInfo.processInfo.environment["CLAUDE_PET_USAGE"] ?? (NSHomeDirectory() + "/.claude-pet/usage.json") }

    init(path: String? = PlanUsageMonitor.defaultPath, autostart: Bool = true) {
        self.path = path
        if autostart { start() }
    }

    func start() {
        guard timer == nil, path != nil else { return }
        poll()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        guard let path, let attrs = try? FileManager.default.attributesOfItem(atPath: path), let m = attrs[.modificationDate] as? Date else {
            if usage != nil { usage = nil }; lastModified = nil; return
        }
        guard m != lastModified else { return }
        lastModified = m
        guard let data = FileManager.default.contents(atPath: path) else { return }
        ingest(PlanUsage.parse(data))
    }

    func ingest(_ u: PlanUsage?, now: Date = Date()) {
        if usage != u { usage = u }
        guard let u, !u.isStale(now: now) else { return }
        if let first = policy.alerts(for: u, now: now).first {
            alert = first
            onAlert?(first)
            alertTask?.cancel()
            alertTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { self?.alert = nil } }
        }
    }
}
