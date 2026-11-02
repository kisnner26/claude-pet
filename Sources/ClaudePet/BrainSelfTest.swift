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
        // el cerebro sueña
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func note(_ text: String, _ kind: BrainKind = .hecho, agent: String = "claude", daysAgo: Double = 0) -> BrainNote {
            BrainNote(id: UUID(), at: now.addingTimeInterval(-daysAgo * 86_400), agent: agent, kind: kind, text: text)
        }
        check("dos frases casi iguales son duplicados", BrainDream.areDuplicates("usamos swiftpm, no xcodeproj para compilar", "Usamos SwiftPM no xcodeproj para compilar el proyecto"))
        check("dos notas distintas no se confunden", !BrainDream.areDuplicates("usamos swiftpm, no xcodeproj", "el relay vive en un archivo de node"))
        check("una nota dentro de otra mas larga cuenta como la misma", BrainDream.areDuplicates("los hooks fallan abiertos siempre", "los hooks fallan abiertos siempre: si algo va mal claude pregunta en la terminal"))
        check("las acentos y mayusculas no importan", BrainDream.tokens("Decisión: SIN cámara") == BrainDream.tokens("decision sin camara"))
        let dupes = BrainDream.consolidate([note("usamos swiftpm no xcodeproj para compilar", daysAgo: 3), note("Usamos SwiftPM, no xcodeproj, para compilar el proyecto", daysAgo: 1), note("el relay es un archivo de node", daysAgo: 2)], now: now, exists: { _ in true })
        check("une los duplicados y se queda con tres menos una", dupes.merged == 1 && dupes.notes.count == 2)
        check("se queda con la mas nueva", dupes.notes.first?.text.hasPrefix("Usamos SwiftPM") == true)
        let mixed = BrainDream.consolidate([note("no se usa la camara jamas en las apps", .trato, agent: "tu", daysAgo: 5), note("no se usa la camara jamas en las apps de kisnner", .trato, daysAgo: 1)], now: now, exists: { _ in true })
        check("tus palabras no se pierden aunque haya una copia mas nueva", mixed.merged == 1 && mixed.notes.count == 1 && mixed.notes[0].agent == "tu" && mixed.notes[0].text.hasPrefix("no se usa la camara jamas en las apps") && mixed.notes[0].at == now.addingTimeInterval(-86_400))
        check("nunca une notas de tipos distintos", BrainDream.consolidate([note("usamos swiftpm para compilar", .decision), note("usamos swiftpm para compilar", .hecho)], now: now, exists: { _ in true }).notes.count == 2)
        check("detecta rutas y archivos en el texto", BrainDream.mentionedPaths("mira `Sources/App/Brain.swift` y config.json, no http://x.com/a.js ni a@b.com.") == ["Sources/App/Brain.swift", "config.json"])
        let gone = BrainDream.consolidate([note("el limite esta en Sources/Viejo.swift"), note("mira Brain.swift y Nuevo.swift"), note("sin archivos en esta")], now: now, exists: { $0 == "Brain.swift" })
        check("marca como obsoleta la que solo habla de archivos que no estan", gone.stale.map(\.text) == ["el limite esta en Sources/Viejo.swift"])
        check("si queda algun archivo vivo no se marca", gone.notes.first { $0.text.hasPrefix("mira Brain") }?.stale == nil)
        let lingering = BrainDream.consolidate([note("arreglar el relay", .pendiente, daysAgo: 20), note("subir la version", .pendiente, daysAgo: 2), note("un hecho viejo", .hecho, daysAgo: 90)], now: now, exists: { _ in true })
        check("senala solo los pendientes que llevan mas de 14 dias", lingering.lingering.map(\.text) == ["arreglar el relay"])
        check("no borra nada que no sea un duplicado", lingering.notes.count == 3 && lingering.merged == 0)
        var report = DreamReport(at: now); report.merged = 2; report.stale = 1; report.lingering = 3
        check("el parte de la mañana lo cuenta en español", report.lines == ["uní 2 notas casi iguales a otras", "1 nota habla de archivos que ya no existen", "3 pendientes llevan más de 14 días abiertos"])
        check("sin novedades dice que todo esta en orden", DreamReport(at: now).headline == "mientras dormías: todo en orden" && DreamReport(at: now).isQuiet)
        check("el aviso de obsoleta sobrevive a guardar y leer", { var n = note("mira Viejo.swift"); n.stale = true; let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601; return (try? dec.decode(BrainNote.self, from: enc.encode(n)))?.stale == true }())
        check("las notas guardadas antes de esto se siguen leyendo", { let old = #"{"id":"\#(UUID().uuidString)","at":"2026-10-01T10:00:00Z","agent":"claude","kind":"hecho","text":"vieja"}"#; let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601; return (try? dec.decode(BrainNote.self, from: Data(old.utf8)))?.text == "vieja" }())
        print(ok ? "CEREBRO OK" : "CEREBRO FALLO")
        return ok
    }
}
