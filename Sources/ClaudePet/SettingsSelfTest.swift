import Foundation

enum SettingsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        // buscador
        check("search-empty", SettingsPage.matching("").count == SettingsPage.allCases.count)
        check("search-title", SettingsPage.matching("sonid") == [.sonidos])
        check("search-accents", SettingsPage.matching("restauracion").contains(.copia) && SettingsPage.matching("RESTAURACIÓN").contains(.copia))
        check("search-keyword", SettingsPage.matching("pomodoro") == [.foco])
        check("search-none", SettingsPage.matching("zzzz").isEmpty)
        check("pages-grouped", Set(SettingsPage.allCases.map(\.group)) == Set(SettingsGroup.allCases))

        // atajos
        var map = ShortcutMap.standard
        check("shortcut-default", map.shortcut(for: "a") == .allow && map.key(for: .pin) == "p")
        check("shortcut-set", map.set(.allow, to: "Z") == nil && map.shortcut(for: "z") == .allow && map.shortcut(for: "a") == nil)
        check("shortcut-taken", map.set(.deny, to: "z") == .taken(by: .allow))
        check("shortcut-bad", map.set(.deny, to: "ab") == .notAKey && map.set(.deny, to: "ñ") == .notAKey && map.set(.deny, to: " ") == .notAKey)
        check("shortcut-same-key", map.set(.allow, to: "z") == nil)
        let round = ShortcutMap.decode(map.encode())
        check("shortcut-roundtrip", round == map)
        check("shortcut-decode-garbage", { let m = ShortcutMap.decode("allow=d,deny=d,xx=1,island,pin=="); return m.key(for: .allow) == "a" && m.key(for: .deny) == "d" && m.key(for: .pin) == "p" }())
        check("shortcut-decode-dup", { let m = ShortcutMap.decode("allow=q,deny=q"); return m.key(for: .allow) == "q" && m.key(for: .deny) == "d" }())

        // volumen por categoria
        let v = SoundCategoryVolumes.decode("interfaz=0.5,alertas=9,mascota=-1,otra=1,interfaz2=x")
        check("catvol-clamp", v[.interface] == 0.5 && v[.alert] == 1 && v[.pet] == 0 && v.count == 3)
        check("catvol-roundtrip", SoundCategoryVolumes.decode(SoundCategoryVolumes.encode(v)) == v)
        check("catvol-garbage", SoundCategoryVolumes.decode("=,=,,nan").isEmpty && SoundCategoryVolumes.decode("interfaz=nan").isEmpty)

        // copia de ajustes
        let suiteName = "claudepet.selftest.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        defer { d.removePersistentDomain(forName: suiteName) }
        d.set(true, forKey: "islandShowClock"); d.set(0.6, forKey: "soundVolume"); d.set("abajo", forKey: "islandPlacement")
        d.set(7, forKey: "focusStart"); d.set("ruido", forKey: "notInSchema")
        let data = SettingsBackup.export(from: d)
        let text = String(decoding: data, as: UTF8.self)
        check("backup-format", text.contains("claude-pet-settings") && !text.contains("notInSchema") && text.contains("islandPlacement"))
        let target = UserDefaults(suiteName: suiteName + ".b")!
        defer { target.removePersistentDomain(forName: suiteName + ".b") }
        let rep = try? SettingsBackup.importing(data, into: target)
        check("backup-roundtrip", rep?.applied == 4 && rep?.skipped.isEmpty == true && target.bool(forKey: "islandShowClock") && target.double(forKey: "soundVolume") == 0.6 && target.string(forKey: "islandPlacement") == "abajo" && target.integer(forKey: "focusStart") == 7)

        func doc(_ s: String) -> Data { Data("{\"format\":\"claude-pet-settings\",\"version\":1,\"settings\":\(s)}".utf8) }
        let hostile = doc("{\"soundVolume\":42,\"islandPlacement\":\"debajo del mar\",\"islandShowClock\":1,\"focusStart\":99,\"focusEnd\":3.5,\"layout\":[1],\"wardrobe\":\"a\\nb\",\"evil\":true,\"autoVisibility\":false}")
        let t2 = UserDefaults(suiteName: suiteName + ".c")!
        defer { t2.removePersistentDomain(forName: suiteName + ".c") }
        let r2 = try? SettingsBackup.importing(hostile, into: t2)
        check("backup-hostile", r2?.applied == 1 && (r2?.skipped.count ?? 0) == 8 && t2.object(forKey: "soundVolume") == nil && t2.object(forKey: "autoVisibility") as? Bool == false)
        check("backup-wrong-format", { do { _ = try SettingsBackup.importing(Data("{\"settings\":{}}".utf8), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .notSettings } }())
        check("backup-not-json", { do { _ = try SettingsBackup.importing(Data("nope".utf8), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .invalidJSON } }())
        check("backup-too-large", { do { _ = try SettingsBackup.importing(Data(repeating: 32, count: SettingsBackup.maxBytes + 1), into: t2); return false } catch { return (error as? SettingsBackup.Failure) == .tooLarge } }())
        SettingsBackup.reset(in: t2)
        check("backup-reset", t2.object(forKey: "autoVisibility") == nil)

        // registro de paginas: cada pagina tiene titulo, simbolo y subtitulo propios
        check("registry-complete", SettingsPage.allCases.allSatisfy { SettingsPage.registry[$0] != nil && !$0.title.isEmpty && !$0.symbol.isEmpty && !$0.subtitle.isEmpty })
        check("registry-experimental", SettingsPage.allCases.filter(\.isExperimental) == [.comportamiento, .trackpad])

        // filtros del buscador (el estado "encendido" se inyecta: aqui solo hay logica)
        let onSet: Set<SettingsPage> = [.apariencia, .sonidos, .plugins]
        let isOn: (SettingsPage) -> Bool? = { p in [.resumen, .privacidad, .copia, .acerca, .guardarropa].contains(p) ? nil : onSet.contains(p) }
        var f = SettingsFilter()
        check("filter-default", !f.isActive && SettingsPage.filtered(f, isOn: isOn).count == SettingsPage.allCases.count)
        f.group = .mascota
        check("filter-group", SettingsPage.filtered(f, isOn: isOn).allSatisfy { $0.group == .mascota } && SettingsPage.filtered(f, isOn: isOn).contains(.sonidos))
        f.onlyEnabled = true
        check("filter-enabled", SettingsPage.filtered(f, isOn: isOn) == [.sonidos])
        f.group = nil
        check("filter-enabled-all", Set(SettingsPage.filtered(f, isOn: isOn)) == onSet)
        f.onlyEnabled = false; f.onlyExperimental = true
        check("filter-experimental", SettingsPage.filtered(f, isOn: isOn) == [.comportamiento, .trackpad])
        f.query = "cursor"
        check("filter-query-and-flag", Set(SettingsPage.filtered(f, isOn: isOn)) == [.comportamiento, .trackpad])
        f.query = "sonid"
        check("filter-combined-empty", SettingsPage.filtered(f, isOn: isOn).isEmpty)
        f.clear()
        check("filter-clear", !f.isActive)
        let counts = SettingsPage.counts(SettingsFilter(), isOn: isOn)
        check("filter-counts", counts[.isla] == 2 && counts[.sistema] == 5 && counts.values.reduce(0, +) == SettingsPage.allCases.count)
        check("filter-categories", SettingsFilter.categories == [.isla, .agentes, .seguridad, .mascota, .sistema])
        let act = SettingsPage.activity(in: .mascota, isOn: isOn)
        check("activity-group", act?.on == 1 && act?.of == 3 && SettingsPage.activity(in: .inicio, isOn: isOn) == nil)

        // densidad
        check("density-decode", SettingsDensity.decode("compacta") == .compact && SettingsDensity.decode("nope") == .comfortable && SettingsDensity.decode(nil) == .comfortable)
        check("density-compact-smaller", SettingsDensity.compact.rowV < SettingsDensity.comfortable.rowV && SettingsDensity.compact.pageSpacing < SettingsDensity.comfortable.pageSpacing)
        check("density-backup-key", SettingsBackup.schema.contains { $0.key == SettingsDensity.storageKey })

        // tablero de inicio: tendencia, cambio y medidores
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        var days: [String: DayStats] = [:]
        func put(_ back: Int, _ s: Int, _ t: Int) { days[ActivityStats.dayKey(cal.date(byAdding: .day, value: -back, to: today)!, calendar: cal)] = DayStats(sessions: s, tools: t, permissions: 0, errors: 0, agents: ["claude": s + t], projects: [:]) }
        put(0, 2, 8); put(2, 1, 4); put(8, 1, 1)
        let week = ActivityTrend.days(days, endingAt: today, count: 7, calendar: cal)
        check("trend-seven", week.count == 7 && week.last?.isToday == true && week.last?.activity == 10 && week[4].activity == 5 && week[3].activity == 0)
        check("trend-total", ActivityTrend.total(week) == 15 && ActivityTrend.busiestIndex(week) == 6)
        check("trend-flags", ActivityTrend.activeFlags(week) == [false, false, false, false, true, false, true])
        check("trend-empty", ActivityTrend.busiestIndex(ActivityTrend.days([:], endingAt: today, count: 7, calendar: cal)) == nil && ActivityTrend.days(days, endingAt: today, count: 0, calendar: cal).isEmpty)
        check("trend-change", ActivityTrend.change(current: 15, previous: 12) == 25 && ActivityTrend.change(current: 9, previous: 10) == -10 && ActivityTrend.change(current: 3, previous: 0) == nil)
        check("trend-change-label", ActivityTrend.changeLabel(25) == "+25 % sobre la semana pasada" && ActivityTrend.changeLabel(-10) == "-10 % sobre la semana pasada" && ActivityTrend.changeLabel(0) == "igual que la semana pasada" && ActivityTrend.changeLabel(nil) == nil)
        let tNow = Date()
        let g5 = PlanGauge.make("5 h", PlanWindow(usedPercent: 38, resetsAt: tNow.addingTimeInterval(7_200)), now: tNow)
        let g7 = PlanGauge.make("7 d", PlanWindow(usedPercent: 83, resetsAt: nil), now: tNow)
        let gx = PlanGauge.make("x", PlanWindow(usedPercent: 97, resetsAt: nil), now: tNow)
        let gr = PlanGauge.make("r", PlanWindow(usedPercent: 99, resetsAt: tNow.addingTimeInterval(-5)), now: tNow)
        check("gauge-tones", g5?.tone == .normal && g7?.tone == .caution && gx?.tone == .critical && g5?.remaining == 0.62)
        check("gauge-reset-window", gr?.tone == .normal && gr?.remaining == 1 && PlanGauge.make("n", nil, now: tNow) == nil && PlanGauge.all(nil, now: tNow).isEmpty)
        check("today-bars", TodayBars.fractions([10, 5, 0]) == [1, 0.5, 0] && TodayBars.fractions([0, 0]) == [0, 0])

        // traducciones de lo nuevo: cada etiqueta fija tiene su version en ingles
        let labels = SettingsGroup.allCases.map(\.title) + SettingsDensity.allCases.map(\.title) + ["solo activados", "solo experimentales", "quitar filtros", "categoría", "mostrar", "todo"]
            + SettingsPage.allCases.map(\.title) + SettingsPage.allCases.map(\.subtitle)
        let missing = labels.filter { L10nEN.table[$0] == nil }
        check("lang-settings-labels \(missing)", missing.isEmpty)
        let saved = L.current; L.current = .en
        check("lang-chart-phrases", L.tr("+25 % sobre la semana pasada") == "+25 % over last week" && L.tr("reinicia en 2 h 19 m") == "resets in 2 h 19 m" && L.tr("3 activas") == "3 on" && L.tr("nivel 4") == "level 4")
        L.current = saved

        print(failures == 0 ? "AJUSTES OK" : "AJUSTES \(failures) FALLOS")
        return failures == 0
    }
}
