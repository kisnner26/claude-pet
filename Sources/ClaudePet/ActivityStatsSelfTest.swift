import Foundation

/// `ClaudePet --selftest-stats`: contadores diarios, resumen semanal, racha y nivel.
enum ActivityStatsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let dir = NSTemporaryDirectory() + "claudepet-stats-\(getpid())"
        setenv("CLAUDE_PET_STATS", dir, 1)
        defer { try? FileManager.default.removeItem(atPath: dir); unsetenv("CLAUDE_PET_STATS") }

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func day(_ d: Int, hour: Int = 12) -> Date { cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: 10, day: d, hour: hour))! }
        let s = ActivityStats(); s.calendar = cal

        check("sin datos el resumen esta vacio", s.recap(endingAt: day(27)) == WeeklyRecap(level: 1) && s.streak(asOf: day(27)) == 0)
        for _ in 0..<5 { s.recordTool(agent: "claude", project: "demo", at: day(27)) }
        s.recordFinished(agent: "claude", project: "demo", at: day(27)); s.recordFinished(agent: "codex", project: "otro", at: day(27))
        s.recordPermission(at: day(27)); s.recordError(at: day(27))
        for _ in 0..<2 { s.recordTool(agent: "codex", project: "otro", at: day(25)) }
        let r = s.recap(endingAt: day(27))
        check("suma sesiones, herramientas, permisos y errores", r.sessions == 2 && r.tools == 7 && r.permissions == 1 && r.errors == 1)
        check("cuenta los dias con actividad", r.activeDays == 2)
        check("el dia mas activo es el de mas movimiento", r.busiestDay?.lowercased().contains("martes") == true)
        check("agente y proyecto mas usados", r.topAgent == "claude" && r.topProject == "demo")
        check("un dia fuera de la ventana de 7 no cuenta", { s.recordTool(agent: "claude", project: "viejo", at: day(10)); return s.recap(endingAt: day(27)).tools == 7 }())

        // racha
        check("la racha se corta si falta un dia", s.streak(asOf: day(27)) == 1)
        s.recordTool(agent: "claude", project: "demo", at: day(26))
        check("la racha crece con dias seguidos", s.streak(asOf: day(27)) == 3)
        check("si hoy aun no hay actividad cuenta desde ayer", s.streak(asOf: day(28)) == 3)
        check("dos dias vacios rompen la racha", s.streak(asOf: day(29)) == 0)

        // nivel solo por actividad real
        check("el nivel sube con sesiones y dias activos", ActivityStats.level(sessions: 0, activeDays: 0) == 1 && ActivityStats.level(sessions: 20, activeDays: 10) > ActivityStats.level(sessions: 2, activeDays: 1))
        let spam = ActivityStats(); spam.calendar = cal
        for _ in 0..<500 { spam.recordTool(agent: "claude", project: "demo", at: day(27)) }
        check("miles de herramientas en un dia no inflan el nivel", spam.recap(endingAt: day(27)).level == 1)

        // texto y privacidad
        let md = r.markdown(showProject: false)
        check("el resumen compartible oculta el proyecto por defecto", !md.contains("demo") && md.contains("sesiones terminadas: 2"))
        check("el resumen propio puede mostrar el proyecto", r.markdown(showProject: true).contains("proyecto mas usado: demo"))
        s.recordTool(agent: "claude", project: "/Users/x/secreto con espacios;rm", at: day(27))
        check("los nombres se limpian y no guardan rutas ni espacios", s.days[s.key(day(27))]?.projects.keys.allSatisfy { !$0.contains("/") && !$0.contains(" ") && !$0.contains(";") } == true)

        // persistencia
        s.save()
        let perms = (try? FileManager.default.attributesOfItem(atPath: ActivityStats.path)[.posixPermissions] as? Int) ?? 0
        check("el archivo de estadisticas es 0600", perms == 0o600)
        let again = ActivityStats(); again.calendar = cal; again.load()
        check("los contadores se recuperan al reiniciar", again.recap(endingAt: day(27)).sessions == 2)
        let old = ActivityStats(); old.calendar = cal
        for i in 0..<(ActivityStats.keepDays + 30) { old.recordTool(agent: "claude", project: "", at: cal.date(byAdding: .day, value: -i, to: day(27))!) }
        old.save()
        let pruned = ActivityStats(); pruned.load()
        check("solo se guardan los ultimos 120 dias", pruned.days.count == ActivityStats.keepDays)
        let content = (try? String(contentsOfFile: ActivityStats.path, encoding: .utf8)) ?? ""
        check("el archivo no guarda comandos ni rutas", !content.contains("rm -rf") && !content.contains("/Users"))
        try? "{rota".write(toFile: ActivityStats.path, atomically: true, encoding: .utf8)
        let broken = ActivityStats(); broken.load()
        check("un archivo corrupto no rompe nada", broken.days.isEmpty)

        check("un turno de 5 s no es una tarea y uno de 20 s si", !ActivityStats.countsAsTask(duration: 5) && !ActivityStats.countsAsTask(duration: 19.9) && ActivityStats.countsAsTask(duration: 20) && ActivityStats.countsAsTask(duration: 600))

        print(failures == 0 ? "ESTADISTICAS OK" : "ESTADISTICAS FALLOS: \(failures)")
        return failures == 0
    }
}
