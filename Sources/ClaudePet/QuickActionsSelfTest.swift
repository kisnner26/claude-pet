import Foundation

enum QuickActionsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        var c = QuickContext()
        check("sin nada: solo lo que siempre vale", QuickAction.allCases.filter { QuickActions.available($0, c) }.sorted { $0.rawValue < $1.rawValue } == [.mission, .pomodoro, .relay, .settings, .snooze, .summary].sorted { $0.rawValue < $1.rawValue })
        c.hasWorkspace = true; c.isRepo = true
        check("con repo: carpeta, punto de restauracion y perimetro", [.folder, .restorePoint, .perimeter].allSatisfy { QuickActions.available($0, c) } && !QuickActions.available(.commit, c))
        c.changeCount = 3; c.agentChanges = 2
        check("commitear exige commitero, repo, proyecto y cambios", !QuickActions.available(.commit, c) && { var d = c; d.commiteroAvailable = true; return QuickActions.available(.commit, d) }() && { var d = c; d.commiteroAvailable = true; d.isRepo = false; return !QuickActions.available(.commit, d) }() && { var d = c; d.commiteroAvailable = true; d.changeCount = 0; return !QuickActions.available(.commit, d) }())
        check("cambios y terminal dependen de su contexto", QuickActions.available(.changes, c) && !QuickActions.available(.terminal, c) && { var d = c; d.terminalAvailable = true; return QuickActions.available(.terminal, d) }())
        check("musica solo si hay algo que controlar", !QuickActions.available(.music, c) && { var d = c; d.musicAvailable = true; return QuickActions.available(.music, d) }())
        check("punto de restauracion no sin repo", { var d = QuickContext(); d.hasWorkspace = true; return !QuickActions.available(.restorePoint, d) }())

        // descriptores que cambian con el estado
        check("musica: icono segun suene o no", QuickActions.descriptor(.music, QuickContext(musicPlaying: true)).symbol == "pause.fill" && QuickActions.descriptor(.music, QuickContext()).symbol == "play.fill")
        check("pomodoro y avisos: cambian de icono", QuickActions.descriptor(.pomodoro, QuickContext(pomodoroRunning: true)).symbol == "stop.fill" && QuickActions.descriptor(.snooze, QuickContext(alertsSnoozed: true)).title == "reactivar avisos" && QuickActions.descriptor(.perimeter, QuickContext(hasPerimeter: false)).title == "fijar perímetro")
        check("insignia de cambios y commit destacado", QuickActions.descriptor(.changes, QuickContext(agentChanges: 7)).badge == 7 && QuickActions.descriptor(.commit, QuickContext(changeCount: 2)).prominent)
        check("todas las acciones tienen titulo, icono y cuando", QuickAction.allCases.allSatisfy { let d = QuickActions.descriptor($0, QuickContext()); return !d.title.isEmpty && !d.symbol.isEmpty && !d.when.isEmpty })

        // layout
        var full = QuickContext(hasWorkspace: true, isRepo: true, changeCount: 4, agentChanges: 3, commiteroAvailable: true, terminalAvailable: true, musicAvailable: true)
        let order = QuickActions.allOrdered
        let l = QuickActions.layout(order: order, context: full)
        check("tope de cinco visibles, el resto al menu +", l.visible.count == QuickActions.maxVisible && l.visible == [.commit, .terminal, .changes, .music, .mission] && l.overflow.first == .summary && l.overflow.count == QuickActions.allOrdered.count - 5)
        check("respeta el orden del usuario", QuickActions.layout(order: [.mission, .commit], context: full).visible == [.mission, .commit])
        full.changeCount = 0; full.agentChanges = 0; full.musicAvailable = false
        check("lo no disponible desaparece y no deja huecos", QuickActions.layout(order: QuickActions.defaultEnabled, context: full).visible == [.terminal, .mission])
        check("sin acciones activadas, dock vacio", QuickActions.layout(order: [], context: full) == (visible: [], overflow: []))
        check("nunca se repite una accion", Set(l.visible + l.overflow).count == (l.visible + l.overflow).count)

        // persistencia
        check("decode: nil usa los de fabrica", QuickActions.decode(nil) == QuickActions.defaultEnabled)
        check("decode: ordena y valida", QuickActions.decode("mission,commit,commit,raro,terminal") == [.mission, .commit, .terminal])
        check("decode: texto sin nada valido vuelve a fabrica, pero vacio significa ninguno", QuickActions.decode("raro,otro") == QuickActions.defaultEnabled && QuickActions.decode("").isEmpty)
        check("encode y decode son inversos", QuickActions.decode(QuickActions.encode(QuickActions.allOrdered)) == QuickActions.allOrdered)
        check("allOrdered contiene todas una vez", QuickActions.allOrdered.count == QuickAction.allCases.count && Set(QuickActions.allOrdered).count == QuickAction.allCases.count)

        print(failures == 0 ? "ACCESO OK" : "ACCESO \(failures) FALLOS")
        return failures == 0
    }
}
