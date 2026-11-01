import Foundation

enum MemorySelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }
        let now = Date()
        func ev(_ k: PetMemoryEvent.Kind, ago: TimeInterval, agent: String = "claude", project: String = "app") -> PetMemoryEvent {
            PetMemoryEvent(id: UUID(), at: now.addingTimeInterval(-ago), kind: k, agent: agent, project: project)
        }
        let events = [ev(.tool, ago: 60), ev(.tool, ago: 3_600 * 5), ev(.error, ago: 120, agent: "codex"), ev(.session, ago: 3_600 * 30, project: "viejo"), ev(.permission, ago: 86_400 * 3)]
        let day = MemoryStats.window(events, range: .day, now: now), week = MemoryStats.window(events, range: .week, now: now)
        check("24 h deja fuera lo mas viejo", day.count == 3)
        check("7 dias incluye todo", week.count == 5)
        let b = MemoryStats.buckets(day, range: .day, now: now)
        check("hay un cubo por hora", b.count == 24)
        check("la suma de los cubos es el total", b.map(\.total).reduce(0, +) == day.count)
        check("lo mas reciente cae en el ultimo cubo", b.last?.total == 2)
        check("tasa sin fallos", abs(MemoryStats.successRate(day) - 2.0 / 3.0) < 0.001)
        check("sin eventos la tasa es 0", MemoryStats.successRate([]) == 0)
        check("reparto por agente", MemoryStats.share(day, agent: "codex") == 1 && MemoryStats.share(day, agent: "claude") == 2)
        check("proyecto principal", MemoryStats.topProject(week)?.name == "app" && MemoryStats.topProject(week)?.count == 4)
        print(ok ? "MEMORIA OK" : "MEMORIA FALLO")
        return ok
    }
}
