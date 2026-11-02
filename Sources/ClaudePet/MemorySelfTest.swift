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
        // cronotipo
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int) -> Date { utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 30))! }
        var rhythm = Chronotype()
        check("sin datos no hay conclusiones", rhythm.insight() == nil)
        for d in 1...3 {
            for _ in 0..<12 { rhythm.add(.tool, at: at(d, 15), calendar: utc) }                       // la tarde: mucha actividad y sin fallos
            for _ in 0..<5 { rhythm.add(.tool, at: at(d, 23), calendar: utc) }; for _ in 0..<5 { rhythm.add(.error, at: at(d, 23), calendar: utc) }   // la noche: la mitad falla
        }
        check("cuenta por hora y por tipo", rhythm.hours[15].tools == 36 && rhythm.hours[23].errors == 15 && rhythm.hours[0].activity == 0)
        check("recuerda los dias distintos", rhythm.days == ["2026-10-01", "2026-10-02", "2026-10-03"])
        check("las franjas son de tres horas y suman todo", rhythm.blocks.count == 8 && rhythm.blocks.map(\.bucket.activity).reduce(0, +) == rhythm.totalEvents)
        let insight = rhythm.insight()
        check("la franja de mas actividad es la de la tarde", insight?.peak?.label == "15–18 h")
        check("detecta la franja en la que mas fallas y cuanto", insight?.hard?.label == "21–24 h" && abs((insight?.hardRatio ?? 0) - 2.0) < 0.3)
        check("detecta la mejor franja", insight?.best?.label == "15–18 h")
        check("las frases salen en español claro", insight?.lines.contains { $0.hasPrefix("en 21–24 h fallas ") && $0.contains("× más que de media") } == true && insight?.lines.contains("trabajas más entre las 15–18 h") == true)
        var steady = Chronotype()
        for d in 1...2 { for h in [9, 14, 20] { for _ in 0..<10 { steady.add(.tool, at: at(d, h), calendar: utc) }; steady.add(.error, at: at(d, h), calendar: utc) } }
        check("con un ritmo parejo no inventa una franja mala", steady.insight()?.hard == nil && steady.insight()?.lines.last == "sin una franja claramente peor: tu ritmo es parejo")
        var oneDay = Chronotype()
        for _ in 0..<60 { oneDay.add(.tool, at: at(1, 10), calendar: utc) }
        check("con un solo dia no se atreve a opinar", oneDay.insight() == nil)
        var capped = Chronotype()
        for d in 1...28 { capped.add(.tool, at: at(d, 10), calendar: utc) }
        check("el historial de dias tiene tope", capped.days.count == 28 && Chronotype.maxDays == 60)
        check("se guarda y se lee igual", (try? JSONDecoder().decode(Chronotype.self, from: JSONEncoder().encode(rhythm))) == rhythm)
        // persistencia del cronotipo (en una carpeta temporal, nunca en la tuya)
        let tmpMemory = NSTemporaryDirectory() + "claudepet-hours-\(UUID().uuidString)"
        setenv("CLAUDE_PET_MEMORY", tmpMemory, 1)
        defer { try? FileManager.default.removeItem(atPath: tmpMemory); unsetenv("CLAUDE_PET_MEMORY") }
        let seed = (0..<30).map { ev(.tool, ago: Double($0) * 600) }
        let store = ChronotypeStore()
        store.load(seed: seed)
        check("la primera vez se siembra con los eventos que habia", store.current.totalEvents == 30 && FileManager.default.fileExists(atPath: ChronotypeStore.path))
        store.add(.error, at: now)
        let again = ChronotypeStore()
        again.load()
        check("lo registrado sobrevive a un reinicio", again.current.totalEvents == 31 && again.current == store.current)
        check("el archivo solo lo lee el usuario", ((try? FileManager.default.attributesOfItem(atPath: ChronotypeStore.path)[.posixPermissions]) as? NSNumber)?.intValue == 0o600)
        try? Data("no es json".utf8).write(to: URL(fileURLWithPath: ChronotypeStore.path))
        let broken = ChronotypeStore()
        broken.load(seed: [])
        check("un archivo estropeado no rompe nada", broken.current.totalEvents == 0)
        print(ok ? "MEMORIA OK" : "MEMORIA FALLO")
        return ok
    }
}
