import Foundation

enum BrainSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }
        let dir = NSTemporaryDirectory() + "brain-test-\(UUID().uuidString)"
        let s = BrainStore(); s.directory = dir
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        check("guarda una nota", { if case .success = s.add(agent: "claude", kind: "decision", text: "usamos swiftpm, no xcodeproj", project: "app", at: t0) { return true }; return false }())
        check("la lee de vuelta", s.notes("app").count == 1 && s.notes("app").first?.agent == "claude")
        s.add(agent: "codex", kind: "hecho", text: "  usamos   SwiftPM, no xcodeproj ", project: "app", at: t0.addingTimeInterval(60))
        check("no duplica la misma nota y conserva al primer autor", s.notes("app").count == 1 && s.notes("app").first?.agent == "claude")
        check("rechaza claves", { if case .failure(.secret) = s.add(agent: "codex", kind: "hecho", text: "token ghp_abcdefghijklmnopqrstuvwxyz0123456789", project: "app") { return true }; return false }())
        check("rechaza cadenas largas opacas", BrainStore.looksSecret("clave A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7"))
        check("no confunde rutas ni frases con secretos", !BrainStore.looksSecret("el build vive en .build/release/ClaudePet y tarda dos minutos"))
        check("rechaza tipo y agente invalidos", { if case .failure(.badKind) = s.add(agent: "claude", kind: "chisme", text: "x", project: "app") { return true }; return false }() && { if case .failure(.badAgent) = s.add(agent: "gpt", kind: "hecho", text: "x", project: "app") { return true }; return false }())
        check("rechaza vacias", { if case .failure(.empty) = s.add(agent: "tu", kind: "hecho", text: "   ", project: "app") { return true }; return false }())
        check("recorta a 240", { if case .success(let n) = s.add(agent: "tu", kind: "hecho", text: String(repeating: "palabra ", count: 80), project: "app") { return n.text.count <= BrainStore.maxText }; return false }())

        for i in 0..<80 { s.add(agent: "claude", kind: "hecho", text: "hecho numero \(i)", project: "lleno", at: t0.addingTimeInterval(Double(i))) }
        s.add(agent: "tu", kind: "pendiente", text: "migrar la base", project: "lleno", at: t0.addingTimeInterval(-1000))
        check("limita a 60 notas", s.notes("lleno").count == BrainStore.maxNotes)
        check("los pendientes no se descartan", s.notes("lleno").contains { $0.kind == .pendiente })

        s.add(agent: "tu", kind: "cuidado", text: "no tocar la rama main sin avisar", project: "global", at: t0.addingTimeInterval(5))
        let b = s.briefing(agent: "codex", project: "app", now: t0.addingTimeInterval(3_600 * 3))
        check("el resumen incluye notas del proyecto y globales", b.contains("swiftpm") && b.contains("global · cuidado"))
        check("el resumen explica como guardar", b.contains("pet-brain.sh add codex"))
        check("el resumen muestra la edad", b.contains("hace 3 h") || b.contains("hace 2 h"))
        let vacio = BrainStore(); vacio.directory = dir + "-vacio"
        check("el proyecto vacio lo dice", vacio.briefing(agent: "claude", project: "nuevo").contains("sin notas todavia"))
        check("los nombres con puntos iniciales caen en global", BrainStore.clean(project: "../etc/passwd") == "global")
        check("un nombre que empieza con punto cae en global", BrainStore.clean(project: "..") == "global")

        let first = s.notes("app").first!
        let edited = s.update(id: first.short, project: "app", kind: "cuidado", text: "mejor usar swiftpm con cuidado", at: t0.addingTimeInterval(500))
        check("edita texto y tipo y conserva autor e id", { if case .success(let n) = edited { return n.id == first.id && n.agent == first.agent && n.kind == .cuidado && n.text.hasPrefix("mejor") }; return false }())
        check("editar a un secreto se rechaza y no cambia nada", { if case .failure(.secret) = s.update(id: first.short, project: "app", kind: "hecho", text: "ghp_abcdefghijklmnopqrstuvwxyz0123456789") { return s.notes("app").contains { $0.text.hasPrefix("mejor") } }; return false }())
        check("editar una nota inexistente falla", { if case .failure = s.update(id: "zzzz", project: "app", kind: "hecho", text: "x") { return true }; return false }())
        let id = s.notes("app").first!.short
        check("olvida por prefijo de id", s.forget(id: id, project: "app") && s.notes("app").allSatisfy { $0.short != id })
        check("olvidar algo inexistente falla", !s.forget(id: "zzzz", project: "app"))
        var printed = ""
        BrainStore.shared.directory = dir
        let code = BrainStore.cli(["add", "claude", "hecho", "nota por cli", "cli"], cwd: "/tmp/x", out: { printed += $0 }, err: { _ in })
        check("el cli guarda y responde", code == 0 && printed.hasPrefix("guardado ") && BrainStore.shared.notes("cli").count == 1)
        check("el cli rechaza secretos con codigo 3", BrainStore.cli(["add", "claude", "hecho", "sk-live-abcdef", "cli"], cwd: "/tmp/x", out: { _ in }, err: { _ in }) == 3)
        _ = BrainStore.cli(["add", "tu", "hecho", "desde cwd"], cwd: "/tmp/miproj", out: { _ in }, err: { _ in })
        check("sin proyecto, el cli usa la carpeta actual", ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] != nil || BrainStore.shared.notes("miproj").count == 1)
        // personalidad
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day0: TimeInterval = 1_800_000_000 - TimeInterval(1_800_000_000 % 86_400)
        let noon = Date(timeIntervalSince1970: day0 + 12 * 3600)
        func e(_ k: PetMemoryEvent.Kind, daysAgo: Int, hour: Int, agent: String, project: String = "app") -> PetMemoryEvent {
            PetMemoryEvent(id: UUID(), at: noon.addingTimeInterval(-Double(daysAgo) * 86_400 + Double(hour - 12) * 3600), kind: k, agent: agent, project: project)
        }
        let few = Personality.profile(agent: "codex", events: [e(.tool, daysAgo: 0, hour: 10, agent: "codex")], notes: 0, now: noon, calendar: cal)
        check("con pocos recuerdos aun se esta formando", !few.formed && few.summary == "todavía formándose" && few.stage == "recién conocidos")
        var lots: [PetMemoryEvent] = []
        for d in 0..<14 { for _ in 0..<3 { lots.append(e(.tool, daysAgo: d, hour: 23, agent: "claude", project: "p\(d % 3)")) } }
        let rich = Personality.profile(agent: "claude", events: lots, notes: 12, now: noon, calendar: cal)
        check("14 dias seguidos dan constancia total", rich.traits.first { $0.key == "constancia" }?.value == 1)
        check("todo de noche da nocturnidad total", rich.traits.first { $0.key == "noche" }?.value == 1)
        check("sin errores la precision es total", rich.traits.first { $0.key == "precision" }?.value == 1)
        check("el resumen nombra los rasgos fuertes", rich.summary.contains("constante") && rich.summary.contains("nocturno") || rich.summary.contains("preciso"))
        check("la etapa sube con los recuerdos", Personality.stage(events: 0) == "recién conocidos" && Personality.stage(events: 250) == "compañeros" && Personality.stage(events: 5000) == "cómplices")
        check("los recuerdos sin autor son de claude", Personality.belongs(e(.tool, daysAgo: 0, hour: 9, agent: ""), to: "claude") && !Personality.belongs(e(.tool, daysAgo: 0, hour: 9, agent: ""), to: "codex"))
        check("cada agente tiene su propio carácter", Personality.profile(agent: "codex", events: lots, notes: 0, now: noon, calendar: cal).events == 0)
        check("el resumen del agente trae tono y limite", Personality.briefing(rich).contains("nunca a costa de la precisión") && Personality.briefing(few).contains("trato"))
        s.add(agent: "claude", kind: "trato", text: "prefiere respuestas cortas y en español", project: "trato")
        check("las notas de trato van primero en el resumen", s.briefing(agent: "claude", project: "trato").contains("como trabajar con el usuario"))
        print(ok ? "CEREBRO OK" : "CEREBRO FALLO")
        return ok
    }
}
