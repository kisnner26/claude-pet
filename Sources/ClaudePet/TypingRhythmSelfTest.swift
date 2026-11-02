import Foundation

enum TypingRhythmSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }

        check("retroceso y suprimir borran; una letra no", TypingRhythm.erases(keyCode: 51) && TypingRhythm.erases(keyCode: 117) && !TypingRhythm.erases(keyCode: 0))
        var r = TypingRhythm()
        check("sin teclas no hay aviso", r.note(at: 100) == nil && r.streakMinutes(at: 100) == nil)
        for i in 0..<60 { r.record(erase: false, at: 100 + Double(i) * 0.4) }
        check("teclear mucho sin borrar no es esfuerzo", !r.isStrained(at: 124) && r.note(at: 124) == nil)
        check("las teclas por minuto salen de la ventana de 30 s", abs(r.keysPerMinute(at: 124) - 120) < 1)

        var s = TypingRhythm()
        for i in 0..<70 { s.record(erase: i % 3 == 0, at: 200 + Double(i) * 0.4) }
        check("mucho tecleo y mucho borrado es esfuerzo", s.isStrained(at: 228) && s.note(at: 228) == "respira un momento")
        check("el esfuerzo se pasa cuando dejas de teclear", !s.isStrained(at: 300))
        var few = TypingRhythm()
        for i in 0..<20 { few.record(erase: true, at: 10 + Double(i)) }
        check("borrar mucho pero con pocas teclas no es esfuerzo", !few.isStrained(at: 30))

        var long = TypingRhythm()
        var t = 1000.0
        for _ in 0..<(52 * 6) { long.record(erase: false, at: t); t += 10 }
        check("52 min seguidos piden descanso", long.needsBreak(at: t) && (long.note(at: t) ?? "").hasPrefix("llevas 5"))
        var shortRun = TypingRhythm()
        t = 1000
        for _ in 0..<(20 * 6) { shortRun.record(erase: false, at: t); t += 10 }
        check("20 min no piden nada", !shortRun.needsBreak(at: t) && shortRun.note(at: t) == nil)
        // una pausa de seis minutos cierra la racha
        var rested = TypingRhythm()
        t = 1000
        for _ in 0..<(40 * 6) { rested.record(erase: false, at: t); t += 10 }
        t += 6 * 60
        for _ in 0..<(20 * 6) { rested.record(erase: false, at: t); t += 10 }
        check("tras una pausa de cinco minutos la racha empieza de nuevo", (rested.streakMinutes(at: t) ?? 99) < 25 && !rested.needsBreak(at: t))
        check("sin teclas desde hace rato la racha ya no vive", long.streakMinutes(at: t + 10_000) == nil)

        // el cronotipo cuenta pulsaciones sin tocar sus umbrales y lee archivos viejos
        var c = Chronotype()
        let date = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        c.addTyped(600, at: date)
        check("las pulsaciones se suman en su hora", c.hours[14].typed == 600 && c.totalTyped == 600)
        check("teclear no cuenta como actividad del agente", c.totalEvents == 0)
        let old = #"{"tools":3,"errors":1,"sessions":0,"permissions":0}"#
        let decoded = try? JSONDecoder().decode(HourBucket.self, from: Data(old.utf8))
        check("un archivo anterior sin pulsaciones se lee igual", decoded?.tools == 3 && decoded?.typed == 0)
        let round = try? JSONDecoder().decode(Chronotype.self, from: JSONEncoder().encode(c))
        check("ida y vuelta por JSON conserva las pulsaciones", round == c)
        for h in 0..<24 where h != 14 { c.hours[h].tools = 3 }
        c.hours[14].tools = 3
        c.days = ["2026-10-30", "2026-10-31"]
        check("el pico de escritura sale en el resumen", c.insight()?.typingPeak?.start == 12 && (c.insight()?.lines.contains("tecleas más entre las 12–15 h") ?? false))
        var few2 = Chronotype()
        few2.addTyped(100, at: date)
        few2.days = ["2026-10-30", "2026-10-31"]
        for h in 0..<24 { few2.hours[h].tools = 3 }
        check("con pocas pulsaciones no se dice nada del teclado", few2.insight()?.typingPeak == nil)
        return ok
    }
}
