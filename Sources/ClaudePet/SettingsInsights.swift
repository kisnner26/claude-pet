import Foundation

/// Un dia de la grafica semanal, ya resumido. Sale de `ActivityStats` (contadores locales): no hay datos nuevos.
struct ActivityDay: Equatable {
    let key: String
    let label: String
    let sessions: Int
    let tools: Int
    let permissions: Int
    let errors: Int
    let claude: Int
    let codex: Int
    let isToday: Bool
    var activity: Int { sessions + tools + permissions }
}

enum ActivityTrend {
    /// Los ultimos `count` dias terminando en `date`, del mas antiguo al de hoy. Los dias sin datos salen a cero.
    static func days(_ data: [String: DayStats], endingAt date: Date, count: Int = 7, calendar: Calendar = Calendar(identifier: .gregorian)) -> [ActivityDay] {
        guard count > 0 else { return [] }
        var out: [ActivityDay] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: date) else { continue }
            let key = ActivityStats.dayKey(day, calendar: calendar)
            let d = data[key] ?? DayStats()
            out.append(ActivityDay(key: key, label: initial(of: day, calendar: calendar), sessions: d.sessions, tools: d.tools, permissions: d.permissions, errors: d.errors,
                                   claude: d.agents["claude"] ?? 0, codex: d.agents["codex"] ?? 0, isToday: back == 0))
        }
        return out
    }

    /// Inicial del dia de la semana en el idioma elegido: L M X J V S D, o M T W T F S S.
    static func initial(of date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)   // 1 = domingo
        let es = ["D", "L", "M", "X", "J", "V", "S"], en = ["S", "M", "T", "W", "T", "F", "S"]
        return (L.current == .en ? en : es)[(weekday - 1) % 7]
    }

    static func total(_ days: [ActivityDay]) -> Int { days.reduce(0) { $0 + $1.activity } }

    /// Cambio porcentual frente al periodo anterior. nil si no hay con que comparar.
    static func change(current: Int, previous: Int) -> Int? {
        guard previous > 0 else { return nil }
        return Int((Double(current - previous) / Double(previous) * 100).rounded())
    }

    /// Texto corto para el cambio: "+25 %", "-10 %", "igual", o nil.
    static func changeLabel(_ percent: Int?) -> String? {
        guard let p = percent else { return nil }
        return p == 0 ? "igual que la semana pasada" : (p > 0 ? "+\(p) % sobre la semana pasada" : "\(p) % sobre la semana pasada")
    }

    /// Indice del dia mas activo (el ultimo si hay empate), nil si toda la semana esta en cero.
    static func busiestIndex(_ days: [ActivityDay]) -> Int? {
        guard let best = days.map(\.activity).max(), best > 0 else { return nil }
        return days.lastIndex { $0.activity == best }
    }

    /// Los siete dias en forma de puntos: encendido si hubo actividad.
    static func activeFlags(_ days: [ActivityDay]) -> [Bool] { days.map { $0.activity > 0 } }
}

/// Tono de un medidor: normal, cuidado o critico.
enum GaugeTone: Equatable { case normal, caution, critical }

/// Lo que queda de una ventana del plan, listo para pintar.
struct PlanGauge: Equatable {
    let title: String
    let remaining: Double       // 0...1
    let tone: GaugeTone
    let resetText: String?

    static func make(_ title: String, _ window: PlanWindow?, now: Date) -> PlanGauge? {
        guard let w = window else { return nil }
        let used = w.effectivePercent(now: now)
        let tone: GaugeTone = used >= 95 ? .critical : used >= 80 ? .caution : .normal
        return PlanGauge(title: title, remaining: max(0, min(1, (100 - used) / 100)), tone: tone, resetText: w.resetText(now: now))
    }

    static func all(_ usage: PlanUsage?, now: Date) -> [PlanGauge] {
        guard let usage else { return [] }
        return [make("5 h", usage.five, now: now), make("7 d", usage.week, now: now)].compactMap { $0 }
    }
}

extension ContextPressure {
    var gaugeTone: GaugeTone { self == .critical ? .critical : self == .caution ? .caution : .normal }
}

/// Reparto de lo de hoy en barras proporcionales: la mas larga ocupa todo el ancho.
enum TodayBars {
    static func fractions(_ values: [Int]) -> [Double] {
        let top = max(values.max() ?? 0, 1)
        return values.map { Double($0) / Double(top) }
    }
}
