import Foundation

/// `ClaudePet --selftest-advice`: las reglas de consejos, un solo consejo a la vez y su enfriamiento.
enum SavingsAdviceSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let saved = L.current
        defer { L.current = saved }
        L.current = .es
        func kinds(_ i: AdviceInput) -> [AdviceKind] { SavingsAdvisor.current(i).map(\.kind) }

        check("sin datos no hay consejos", kinds(AdviceInput()).isEmpty)
        check("contexto holgado: nada", kinds(AdviceInput(contextRemainingFraction: 0.6)).isEmpty)
        check("contexto al limite pide rotar y ofrece llevarse las notas", SavingsAdvisor.current(AdviceInput(contextRemainingFraction: 0.25)).first.map { $0.kind == .rotateContext && $0.offersCapsule } == true)
        check("justo en el umbral ya avisa", kinds(AdviceInput(contextRemainingFraction: SavingsAdvisor.rotateAt)) == [.rotateContext])
        check("sesion de tres horas", kinds(AdviceInput(sessionAge: 3 * 3600 + 5)) == [.longSession])
        check("sesion de dos horas: nada", kinds(AdviceInput(sessionAge: 2 * 3600)).isEmpty)
        check("sesion larga con contexto critico: solo uno, el de rotar", kinds(AdviceInput(contextRemainingFraction: 0.1, sessionAge: 5 * 3600)) == [.rotateContext])
        check("pdf leido", kinds(AdviceInput(lastFileExtension: "PDF")) == [.heavyFile])
        check("docx, pptx y xlsx tambien", ["docx", "pptx", "xlsx"].allSatisfy { kinds(AdviceInput(lastFileExtension: $0)) == [.heavyFile] })
        check("markdown o swift no", kinds(AdviceInput(lastFileExtension: "md")).isEmpty && kinds(AdviceInput(lastFileExtension: "swift")).isEmpty)
        check("cache baja con muestra suficiente", kinds(AdviceInput(cacheHitRate: 0.3, promptTokensMeasured: 80_000)) == [.lowCache])
        check("cache baja con muestra pequena: callada", kinds(AdviceInput(cacheHitRate: 0.1, promptTokensMeasured: 500)).isEmpty)
        check("cache buena: nada", kinds(AdviceInput(cacheHitRate: 0.9, promptTokensMeasured: 80_000)).isEmpty)

        check("prompt general detectado", PromptShape.analyze("arregla todo").generic && PromptShape.analyze("Mejora el código").generic && PromptShape.analyze("fix it").generic)
        check("prompt concreto no es general", !PromptShape.analyze("arregla el error de login en Sources/Auth/Login.swift porque devuelve 401").generic)
        check("una palabra suelta no es general", !PromptShape.analyze("continúa").generic)
        check("la frase general dentro de un prompt largo y concreto no cuenta", !PromptShape.analyze("revisa todo el modulo de pagos y dime si el calculo del iva en Totales.swift esta bien redondeado").generic)
        check("prompt general aconseja", kinds(AdviceInput(promptIsGeneric: true)) == [.vaguePrompt])

        // orden: rotar primero, luego archivo, luego prompt
        let everything = AdviceInput(contextRemainingFraction: 0.2, sessionAge: 4 * 3600, cacheHitRate: 0.2, promptTokensMeasured: 90_000, promptIsGeneric: true, lastFileExtension: "pdf")
        check("orden de prioridad", kinds(everything) == [.rotateContext, .heavyFile, .vaguePrompt, .lowCache])

        // enfriamiento
        var t = SavingsAdvisor.Throttle()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        check("el primero sale", SavingsAdvisor.next(everything, throttle: &t, now: t0)?.kind == .rotateContext)
        check("no salen dos seguidos", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(60)) == nil)
        check("pasado el hueco global sale el siguiente, no el repetido", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(6 * 60))?.kind == .heavyFile)
        check("y luego el siguiente", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(12 * 60))?.kind == .vaguePrompt)
        check("y luego el de cache", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(18 * 60))?.kind == .lowCache)
        check("con todos en enfriamiento calla", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(24 * 60)) == nil)
        check("pasada media hora vuelve el primero", SavingsAdvisor.next(everything, throttle: &t, now: t0.addingTimeInterval(31 * 60))?.kind == .rotateContext)
        var quiet = SavingsAdvisor.Throttle()
        check("sin nada que decir no anota ni gasta el enfriamiento", SavingsAdvisor.next(AdviceInput(), throttle: &quiet, now: t0) == nil && quiet.lastAny == nil)

        // textos
        check("mensajes en espanol y sin emojis", SavingsAdvisor.current(everything).allSatisfy { !$0.message.isEmpty && $0.message.unicodeScalars.allSatisfy { $0.value < 0x1F000 } })
        L.current = .en
        check("mensajes en ingles", SavingsAdvisor.current(AdviceInput(contextRemainingFraction: 0.2)).first?.message.hasPrefix("context is at 80%") == true)
        L.current = .es

        print(failures == 0 ? "CONSEJOS OK" : "CONSEJOS \(failures) FALLOS")
        return failures == 0
    }
}
