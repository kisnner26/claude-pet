import Foundation

private final class ScanProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var completed: [String] = []
    func add(_ value: String) { lock.lock(); completed.append(value); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return completed.count }
    var last: String? { lock.lock(); defer { lock.unlock() }; return completed.last }
}

@MainActor
enum MissionSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ value: @autoclosure () -> Bool) {
            let passed = value()
            print((passed ? "PASS " : "FAIL ") + name)
            if !passed { failures += 1 }
        }

        // Porcelain v1 -z: estados separados, conflictos exactos y segunda ruta de R/C consumida.
        let raw = Data("## main...origin/main\0 M uno\0A  dos\0?? tres\0UU cuatro\0".utf8)
        let health = GitPulse.parse(raw)
        check("salud git separa estados", health.changed == 1 && health.staged == 1 && health.untracked == 1 && health.conflicts == 1 && health.affected == 4)
        check("salud git obtiene rama", health.branch == "main")
        let renamed = GitPulse.parse(Data("R  nuevo.swift\0viejo.swift\0".utf8))
        check("rename consume la ruta origen", renamed.staged == 1 && renamed.changed == 0 && renamed.conflicts == 0 && renamed.affected == 1)
        let modifiedTwice = GitPulse.parse(Data("MM archivo.swift\0".utf8))
        check("un archivo MM cuenta una vez", modifiedTwice.staged == 1 && modifiedTwice.changed == 1 && modifiedTwice.affected == 1 && modifiedTwice.label.hasPrefix("1 cambio"))

        testRealRepositories(check)
        testScanScheduling(check)
        testRadarRecoveryAndBudget(check)
        testInsights(check)
        testPrivacy(check)
        testVisualModels(check)

        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }

    private static func testVisualModels(_ check: (String, @autoclosure () -> Bool) -> Void) {
        // mapa de cambios
        let numstat = GitPulse.parseNumstat(Data("5\t2\tuno.swift\0-\t-\timg.png\0".utf8) + Data("1\t0\t\0viejo.swift\0nuevo.swift\0".utf8))
        check("numstat lee líneas, binarios y renombres", numstat["uno.swift"]?.0 == 5 && numstat["uno.swift"]?.1 == 2 && numstat["img.png"]?.0 == 0 && numstat["nuevo.swift"]?.0 == 1)
        let records = GitPulse.parseRecords(Data("## main\0 M uno\0R  nuevo\0viejo\0?? tres\0".utf8))
        check("registros de status con ruta y renombre", records.map(\.path) == ["uno", "nuevo", "tres"])
        check("rutas inseguras se rechazan", !ChangeMap.isSafe("../fuera") && !ChangeMap.isSafe("/etc/passwd") && ChangeMap.isSafe("a/b.swift"))
        let rect = CGRect(x: 0, y: 0, width: 400, height: 120)
        let cells = ChangeMap.layout([60, 20, 10, 10], in: rect)
        let area = cells.reduce(0) { $0 + $1.width * $1.height }
        check("treemap cubre el área y respeta proporciones", cells.count == 4 && abs(area - 48_000) < 1 && abs(cells[0].width * cells[0].height - 28_800) < 1)
        let inside = cells.allSatisfy { rect.insetBy(dx: -0.01, dy: -0.01).contains($0) }
        check("treemap no se sale del marco", inside)
        let base = Date(timeIntervalSince1970: 9_000)
        check("brillo baja con la antigüedad", ChangeMap.brightness(modified: base, now: base) > ChangeMap.brightness(modified: base.addingTimeInterval(-900), now: base)
              && ChangeMap.brightness(modified: base.addingTimeInterval(-9000), now: base) == 0.3)

        // estela de sesión
        func event(_ agent: String, _ state: PetState, _ sec: Double) -> MissionEvent { MissionEvent(at: base.addingTimeInterval(sec), agent: agent, state: state, project: "p") }
        let events = [event("codex", .done, 100), event("claude", .tool, 60), event("codex", .thinking, 20), event("claude", .thinking, 0)]
        let segs = SessionTrail.segments(events: events, now: base.addingTimeInterval(120))
        let summary = SessionTrail.summary(segs)
        check("estela suma el trabajo de cada agente", Int(summary.claude) == 120 && Int(summary.codex) == 80)
        check("estela detecta cuándo coincidieron", Int(summary.together) == 80)
        check("estela sin eventos no inventa tramos", SessionTrail.segments(events: [], now: base).isEmpty)

        // prioridad del tablero
        var clock = base
        let control = MissionControl(now: { clock })
        check("tablero tranquilo sin proyecto", control.brief.action == nil && control.brief.tone == .calm)
        control.recordLocal(state: .waiting, project: "demo", workspace: "", session: "s")
        check("aprobación pendiente es lo primero y no ofrece botón", control.brief.title == "claude espera tu aprobación" && control.brief.action == nil)
        clock = base.addingTimeInterval(1)

        // relevo entre agentes
        var hClock = base
        let relay = MissionControl(now: { hClock })
        relay.recordLocal(state: .thinking, project: "demo", workspace: "", session: "s")
        hClock = base.addingTimeInterval(30)
        relay.recordLocal(state: .done, project: "demo", workspace: "", session: "s")
        hClock = base.addingTimeInterval(40)
        relay.recordPeer(state: .thinking, project: "demo")
        check("relevo: claude termina y codex retoma", relay.handoff?.from == "claude" && relay.handoff?.to == "codex")
        hClock = base.addingTimeInterval(50)
        relay.tick()
        check("relevo expira solo", relay.handoff == nil)
        let late = MissionControl(now: { hClock })
        hClock = base
        late.recordPeer(state: .done, project: "demo")
        hClock = base.addingTimeInterval(120)
        late.recordLocal(state: .thinking, project: "demo", workspace: "", session: "s")
        check("sin relevo si pasó demasiado tiempo", late.handoff == nil)
        let p0 = HandoffRenderer.point(0, from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), lift: 50)
        let p1 = HandoffRenderer.point(1, from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), lift: 50)
        let pm = HandoffRenderer.point(0.5, from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), lift: 50)
        check("la chispa sale, llega y sube en medio", p0.x == 0 && p1.x == 200 && pm.y < 100)
        let aura = PetAura.style(state: .waiting, collision: false)
        check("aura: reposo sin halo, espera con borde, colisión en rojo",
              PetAura.style(state: .idle, collision: false) == nil && aura?.ring == true && PetAura.style(state: .tool, collision: true)?.tint == .alert)
    }

    private static func testInsights(_ check: (String, @autoclosure () -> Bool) -> Void) {
        var date = Date(timeIntervalSince1970: 4_000)
        let control = MissionControl(now: { date })
        control.recordLocal(state: .waiting, project: "demo", workspace: "", session: "s")
        control.recordPeer(state: .done, project: "demo")
        let ids = control.insights.map(\.id)
        check("panel operativo expone doce lecturas estables", ids.count == 12 && Set(ids).count == 12)
        check("panel operativo detecta aprobación y relevo", control.insights.first(where: { $0.id == "approval" })?.tone == .caution && control.insights.first(where: { $0.id == "handoff" })?.tone == .active)
        control.recordLocal(state: .thinking, project: "demo", workspace: "", session: "s")
        check("panel operativo activa relevo mientras Claude trabaja", control.insights.first(where: { $0.id == "handoff" })?.tone == .active)
        date.addTimeInterval(60); control.tick()
        check("panel operativo conserva el ritmo local", control.insights.first(where: { $0.id == "pace" })?.detail.contains("1 min") == true)
    }


    private static func testRealRepositories(_ check: (String, @autoclosure () -> Bool) -> Void) {
        guard let root = temporaryDirectory() else { check("crea repos temporales", false); return }
        defer { try? FileManager.default.removeItem(atPath: root) }

        let rename = root + "/rename"
        makeDirectory(rename); initRepo(rename)
        write(rename + "/Utils.swift", "let value = 1\n")
        git(rename, ["add", "Utils.swift"]); git(rename, ["commit", "-m", "base"])
        try? FileManager.default.moveItem(atPath: rename + "/Utils.swift", toPath: rename + "/Helpers.swift")
        git(rename, ["add", "-A"])
        let renameHealth = GitPulse.scan(rename)
        check("repo real: rename es un staged sin conflicto", renameHealth.staged == 1 && renameHealth.changed == 0 && renameHealth.conflicts == 0 && renameHealth.affected == 1)

        let mm = root + "/mm"
        makeDirectory(mm); initRepo(mm)
        write(mm + "/main.swift", "let value = 1\n")
        git(mm, ["add", "main.swift"]); git(mm, ["commit", "-m", "base"])
        write(mm + "/main.swift", "let value = 2\n"); git(mm, ["add", "main.swift"])
        write(mm + "/main.swift", "let value = 3\n")
        let mmHealth = GitPulse.scan(mm)
        check("repo real: MM afecta un archivo", mmHealth.staged == 1 && mmHealth.changed == 1 && mmHealth.affected == 1)

        let conflict = root + "/conflict"
        makeDirectory(conflict); initRepo(conflict)
        write(conflict + "/shared.txt", "base\n"); git(conflict, ["add", "shared.txt"]); git(conflict, ["commit", "-m", "base"])
        git(conflict, ["checkout", "-b", "other"]); write(conflict + "/shared.txt", "other\n"); git(conflict, ["add", "shared.txt"]); git(conflict, ["commit", "-m", "other"])
        git(conflict, ["checkout", "main"]); write(conflict + "/shared.txt", "main\n"); git(conflict, ["add", "shared.txt"]); git(conflict, ["commit", "-m", "main"])
        _ = run("/usr/bin/git", ["-C", conflict, "merge", "other"])
        let conflictHealth = GitPulse.scan(conflict)
        check("repo real: conflicto de merge exacto", conflictHealth.conflicts == 1 && conflictHealth.staged == 0 && conflictHealth.changed == 0 && conflictHealth.affected == 1)

        let spaces = root + "/spaces"
        makeDirectory(spaces); initRepo(spaces)
        write(spaces + "/archivo con espacios.txt", "dato\n")
        let spacesHealth = GitPulse.scan(spaces)
        check("repo real: rutas con espacios", spacesHealth.untracked == 1 && spacesHealth.affected == 1)

        let unborn = root + "/unborn"
        makeDirectory(unborn); initRepo(unborn); write(unborn + "/nuevo.txt", "dato\n")
        let unbornHealth = GitPulse.scan(unborn)
        check("repo real: repositorio sin commits", unbornHealth.available && unbornHealth.branch == "main" && unbornHealth.untracked == 1)

        let plain = root + "/plain"
        makeDirectory(plain)
        check("repo real: carpeta no git", !GitPulse.scan(plain).available)
    }

    private static func testScanScheduling(_ check: (String, @autoclosure () -> Bool) -> Void) {
        guard let workspace = temporaryDirectory() else { check("crea workspace de escaneo", false); return }
        defer { try? FileManager.default.removeItem(atPath: workspace) }

        let gate = DispatchSemaphore(value: 0)
        let control = MissionControl(scanner: { _ in gate.wait(); return GitHealth(available: true) })
        for _ in 0..<50 { control.recordLocal(state: .thinking, project: "demo", workspace: workspace, session: "s") }
        for _ in 0..<50 { control.refreshGit() }
        check("50 actualizaciones lanzan como máximo una activa y una pendiente", control.scanLaunchCount <= 1)
        gate.signal()
        _ = waitUntil(1) { control.scanLaunchCount == 2 }
        gate.signal()
        check("ráfaga queda limitada a dos procesos git", waitUntil(1) { control.scanLaunchCount == 2 })

        let slowGate = DispatchSemaphore(value: 0)
        let probe = ScanProbe()
        let coordinator = GitScanCoordinator(scanner: { path in slowGate.wait(); return GitHealth(branch: path, available: true) })
        coordinator.request(workspace: "primero") { path, _ in probe.add(path) }
        coordinator.request(workspace: "segundo") { path, _ in probe.add(path) }
        coordinator.request(workspace: "último") { path, _ in probe.add(path) }
        check("escáner lento conserva solo una pendiente", coordinator.launchCount == 1 && coordinator.hasPending)
        slowGate.signal()
        _ = waitUntil(1) { coordinator.launchCount == 2 }
        slowGate.signal()
        check("la pendiente más nueva reemplaza la anterior", waitUntil(1) { probe.count == 2 } && probe.last == "último" && coordinator.launchCount == 2)

        let started = Date()
        let hungSucceeded = GitPulse.runForTest(executable: "/bin/sh", arguments: ["-c", "exec sleep 5"], timeout: 0.1)
        check("proceso colgado termina por timeout", !hungSucceeded && Date().timeIntervalSince(started) < 1.5)
    }

    private static func testRadarRecoveryAndBudget(_ check: (String, @autoclosure () -> Bool) -> Void) {
        var date = Date(timeIntervalSince1970: 1_000)
        let control = MissionControl(now: { date })
        control.recordLocal(state: .thinking, project: "/uno/demo", workspace: "", session: "s")
        control.recordPeer(state: .thinking, project: "demo")
        check("radar aplica debounce", !control.collision)
        date.addTimeInterval(10); control.tick()
        check("radar compara solo basename", control.collision)
        control.peerLeft(); date.addTimeInterval(4); control.tick()
        check("radar conserva histéresis cinco segundos", control.collision)
        date.addTimeInterval(1); control.tick()
        check("peerLeft limpia radar tras histéresis", !control.collision)

        let waiting = MissionControl(now: { date })
        waiting.recordLocal(state: .waiting, project: "demo", workspace: "", session: "s")
        waiting.recordPeer(state: .thinking, project: "demo"); date.addTimeInterval(20); waiting.tick()
        check("waiting no activa radar", !waiting.collision)

        let generic = MissionControl(now: { date })
        generic.recordLocal(state: .thinking, project: "src", workspace: "", session: "s")
        generic.recordPeer(state: .thinking, project: "src"); date.addTimeInterval(20); generic.tick()
        check("nombre genérico no activa radar", !generic.collision)

        var storeDate = Date(timeIntervalSince1970: 2_000)
        let storeMission = MissionControl(now: { storeDate })
        let store = PetStore(mission: storeMission)
        store.apply(PetEvent(kind: .state(.thinking), session: "s", tool: "", project: "demo", detail: "", origin: "desktop", workspace: "", task: ""))
        store.receive(line: "{\"v\":1,\"id\":\"codex\",\"state\":\"thinking\",\"project\":\"demo\",\"ts\":1}")
        storeDate.addTimeInterval(10); storeMission.tick()
        check("radar nunca ocupa safetyAlert", storeMission.collision && store.safetyAlert == nil)
        store.prune(at: Date().addingTimeInterval(30))
        storeDate.addTimeInterval(5); storeMission.tick()
        check("TTL del par llama peerLeft", store.peer == nil && !storeMission.collision)

        var recoveryDate = Date(timeIntervalSince1970: 3_000)
        let recovery = MissionControl(now: { recoveryDate })
        recovery.recordLocal(state: .error, project: "demo", workspace: "", session: "s")
        recoveryDate.addTimeInterval(1); recovery.tick()
        check("error de un segundo no crea cápsula", recovery.recovery == nil)
        recoveryDate.addTimeInterval(2); recovery.tick()
        let firstDate = recovery.recovery?.createdAt
        recovery.tick()
        check("cápsula no se recrea en el mismo error", recovery.recovery?.createdAt == firstDate)
        recovery.clearRecovery(); recoveryDate.addTimeInterval(20); recovery.tick()
        check("descarte persiste durante el mismo error", recovery.recovery == nil)

        let budget = MissionControl(now: { recoveryDate })
        budget.recordLocal(state: .thinking, project: "demo", workspace: "", session: "s")
        budget.recordToolEvent("Read"); budget.recordToolEvent("Read"); budget.recordToolEvent("Edit")
        budget.recordLocal(state: .done, project: "demo", workspace: "", session: "s")
        check("presupuesto persiste al terminar", budget.focusLabel.contains("3 herramientas") && budget.focusLabel.contains("Read ×2"))

        let eventMission = MissionControl(now: { recoveryDate })
        let eventStore = PetStore(mission: eventMission)
        let toolEvent = PetEvent(kind: .state(.tool), session: "tools", tool: "Read", project: "demo", detail: "", origin: "desktop", workspace: "", task: "")
        eventStore.apply(toolEvent); eventStore.apply(toolEvent)
        check("PetStore cuenta dos PreToolUse consecutivos", eventMission.toolCalls == 2)

        for index in 0..<20 {
            let state: PetState = index.isMultiple(of: 2) ? .thinking : .done
            recoveryDate.addTimeInterval(60)
            budget.recordPeer(state: state, project: "p\(index)")
        }
        check("timeline limita a 16 y mantiene orden", budget.timeline.count == 16 && budget.timeline.first?.project == "p19" && budget.timeline.last?.project == "p4")
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        check("timeline conserva horas formateables", formatter.string(from: budget.timeline[0].at).count == 5)
    }

    private static func testPrivacy(_ check: (String, @autoclosure () -> Bool) -> Void) {
        let message = BusMessage(v: 1, id: "claude", state: "thinking", project: nil, ts: 1, event: "working")
        let encoded = PetBus.encode(message).map { String(decoding: $0, as: UTF8.self) } ?? ""
        check("pet bus no filtra datos de mission control", !encoded.contains("workspace") && !encoded.contains("branch") && !encoded.contains("staged") && !encoded.contains("affected"))
    }

    private static func temporaryDirectory() -> String? {
        let path = NSTemporaryDirectory() + "claudepet-mission-" + UUID().uuidString
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true); return path }
        catch { return nil }
    }

    private static func makeDirectory(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private static func write(_ path: String, _ text: String) {
        try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    @discardableResult private static func git(_ workspace: String, _ arguments: [String]) -> Int32 {
        run("/usr/bin/git", ["-C", workspace] + arguments)
    }

    private static func initRepo(_ workspace: String) {
        git(workspace, ["init", "-b", "main"])
        git(workspace, ["config", "user.name", "ClaudePet Tests"])
        git(workspace, ["config", "user.email", "tests@local.invalid"])
    }

    @discardableResult private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus }
        catch { return -1 }
    }

    private static func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return condition()
    }
}
