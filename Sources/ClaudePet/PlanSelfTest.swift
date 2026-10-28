import Foundation

/// `ClaudePet --selftest-plan [usage.json]`: lectura del consumo, ventanas reiniciadas, datos viejos, avisos sin repetir y el archivo real que escribe el hook.
enum PlanSelfTest {
    @MainActor static func run(file: String?) -> Bool {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func json(_ s: String) -> PlanUsage? { PlanUsage.parse(Data(s.utf8)) }

        let u = json(#"{"five":{"p":42.5,"r":1800007200},"week":{"p":18,"r":1800400000},"at":1800000000}"#)
        check("lee las dos ventanas", u?.five?.usedPercent == 42.5 && u?.week?.usedPercent == 18)
        check("queda el 58 % (redondeado) en la ventana de 5 h", u?.five?.remainingPercent(now: now) == 58)
        check("reinicio en 2 h", u?.five?.resetText(now: now) == "2 h")
        check("reinicio semanal en dias", json(#"{"week":{"p":1,"r":1800400000}}"#)?.week?.resetText(now: now) == "4 d")
        check("reinicio en minutos", PlanWindow(usedPercent: 1, resetsAt: now.addingTimeInterval(90)).resetText(now: now) == "1 m")
        check("reinicio con horas y minutos", PlanWindow(usedPercent: 1, resetsAt: now.addingTimeInterval(3 * 3600 + 25 * 60)).resetText(now: now) == "3 h 25 m")
        check("acepta milisegundos y texto ISO", json(#"{"five":{"p":10,"r":1800007200000}}"#)?.five?.resetsAt == Date(timeIntervalSince1970: 1_800_007_200) && json(#"{"five":{"p":10,"r":"2027-01-15T08:00:00Z"}}"#)?.five?.resetsAt != nil)
        check("sin hora de reinicio es valido", json(#"{"five":{"p":10,"r":null}}"#)?.five?.resetsAt == nil)
        check("una ventana vencida cuenta como 0 %", PlanWindow(usedPercent: 99, resetsAt: now.addingTimeInterval(-5)).effectivePercent(now: now) == 0)
        check("el porcentaje se acota a 0-100", PlanWindow(usedPercent: 250, resetsAt: nil).effectivePercent(now: now) == 100 && PlanWindow(usedPercent: -4, resetsAt: nil).effectivePercent(now: now) == 0)
        check("basura se rechaza", json("no es json") == nil && json("{}") == nil && json(#"{"five":{"p":"x"}}"#) == nil && json(#"{"five":{"p":1e999}}"#) == nil)
        check("archivo enorme se rechaza", PlanUsage.parse(Data(repeating: 32, count: 5000)) == nil)

        let at = Date(timeIntervalSince1970: 1_800_000_000)
        check("datos de hace 2 h son viejos", PlanUsage(five: nil, week: nil, readAt: at.addingTimeInterval(-7200)).isStale(now: at))
        check("datos recientes no son viejos", !PlanUsage(five: nil, week: nil, readAt: at.addingTimeInterval(-60)).isStale(now: at))
        func usage(_ five: Double, _ week: Double = 0) -> PlanUsage { PlanUsage(five: PlanWindow(usedPercent: five, resetsAt: at.addingTimeInterval(7200)), week: PlanWindow(usedPercent: week, resetsAt: at.addingTimeInterval(400_000)), readAt: at) }
        check("presion normal/cuidado/critica", usage(10).pressure(now: at) == .normal && usage(85).pressure(now: at) == .caution && usage(96).pressure(now: at) == .critical && usage(10, 97).pressure(now: at) == .critical)

        var policy = PlanAlertPolicy()
        check("a 79 % no avisa", policy.alerts(for: usage(79), now: at).isEmpty)
        let a80 = policy.alerts(for: usage(81), now: at)
        check("a 81 % avisa una vez con lo que queda y el reinicio", a80.count == 1 && a80[0].contains("5 horas") && a80[0].contains("19%") && a80[0].contains("2 h"))
        check("no repite el mismo umbral", policy.alerts(for: usage(83), now: at).isEmpty)
        check("a 96 % avisa del siguiente umbral", policy.alerts(for: usage(96), now: at).count == 1)
        check("saltar directo a 97 % avisa una sola vez", { var p = PlanAlertPolicy(); return p.alerts(for: usage(97), now: at).count == 1 && p.alerts(for: usage(97), now: at).isEmpty }())
        check("avisa de la ventana semanal por separado", { var p = PlanAlertPolicy(); let r = p.alerts(for: usage(10, 90), now: at); return r.count == 1 && r[0].contains("semanal") }())
        let next = PlanUsage(five: PlanWindow(usedPercent: 85, resetsAt: at.addingTimeInterval(7200 + 18_000)), week: nil, readAt: at)
        check("al reiniciarse la ventana vuelve a avisar", policy.alerts(for: next, now: at).count == 1)

        let monitor = PlanUsageMonitor(path: nil, autostart: false)
        monitor.ingest(usage(90), now: at)
        check("el monitor publica el consumo y el aviso", monitor.usage?.five?.usedPercent == 90 && monitor.alert != nil)
        let stale = PlanUsageMonitor(path: nil, autostart: false)
        stale.ingest(PlanUsage(five: PlanWindow(usedPercent: 99, resetsAt: at.addingTimeInterval(7200)), week: nil, readAt: at.addingTimeInterval(-7200)), now: at)
        check("con datos viejos no avisa", stale.alert == nil)

        if let file {
            let data = FileManager.default.contents(atPath: file)
            let real = data.flatMap(PlanUsage.parse)
            check("el archivo que escribe el hook se lee", real?.five?.usedPercent == 42.7 && real?.week?.usedPercent == 18 && real?.five?.resetsAt != nil)
            let perms = ((try? FileManager.default.attributesOfItem(atPath: file))?[.posixPermissions] as? Int) ?? 0
            check("el archivo es solo del usuario (0600)", perms & 0o077 == 0)
        }
        print(failures == 0 ? "PLAN OK" : "PLAN \(failures) FALLOS")
        return failures == 0
    }
}
