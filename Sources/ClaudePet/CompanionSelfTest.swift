import Foundation
import SwiftUI

/// `ClaudePet --selftest-companion`: caras, pose, reacciones, geometria del escenario y salida del partido.
@MainActor
enum CompanionSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }

        // 1. las caras caben en el visor y se distinguen
        let faces: [CodexAvatar.Face] = [.prompt(cursor: true), .happy, .dots(3), .typing(1), .alert(on: true), .cross]
        var signatures = Set<String>()
        var inVisor = true, inBounds = true
        /// Color final de cada celda (las posteriores tapan a las anteriores), para aislar lo que dibuja el glifo.
        func finalColors(_ cells: [(x: Int, y: Int, c: Color)]) -> [String: Color] {
            var d: [String: Color] = [:]; for c in cells { d["\(c.x),\(c.y)"] = c.c }; return d
        }
        let base = finalColors(CodexAvatar.cells(legs: .stand, face: .dots(0)))
        for f in faces {
            let cells = CodexAvatar.cells(legs: .stand, face: f)
            if cells.contains(where: { $0.x < 0 || $0.x >= CodexAvatar.width || $0.y < 0 || $0.y >= CodexAvatar.height }) { inBounds = false }
            let glyph = finalColors(cells).filter { base[$0.key] != $0.value }.map { $0.key }
            for key in glyph {
                let xy = key.split(separator: ",").compactMap { Int($0) }
                if xy[0] < 5 || xy[0] > 12 || xy[1] < 4 || xy[1] > 8 { inVisor = false }
            }
            signatures.insert(glyph.sorted().joined(separator: ";"))
        }
        check("todas las caras caben en la rejilla del avatar", inBounds)
        check("el glifo siempre queda dentro del visor", inVisor)
        check("las 6 caras son distintas entre si (y ninguna esta vacia)", signatures.count == faces.count && !signatures.contains(""))
        let emotes: [CodexAvatar.Emote] = [.dots(3), .bang, .question, .check]
        check("los emotes quedan sobre la cabeza y dentro del ancho", emotes.allSatisfy { e in
            CodexAvatar.emote(e).allSatisfy { $0.y < 0 && $0.y >= -7 && $0.x >= 0 && $0.x < CodexAvatar.width } })

        // 2. pose segun el estado real de Codex
        func info(_ codex: PetState, claude: PetState = .idle, cheer: Bool = false, done: Bool = false) -> CompanionInfo {
            CompanionInfo(codex: codex, claude: claude, codexCheer: cheer, codexConcern: false, claudeDone: done)
        }
        check("pensando: puntos en el visor", { if case .dots = CompanionPose.make(info: info(.thinking), t: 1, motion: true).face { return true }; return false }())
        check("herramienta: teclea", { if case .typing = CompanionPose.make(info: info(.tool), t: 1, motion: true).face { return true }; return false }())
        check("aprobacion: signo de exclamacion", { if case .alert = CompanionPose.make(info: info(.waiting), t: 1, motion: true).face { return true }; return false }())
        check("terminado: cara feliz", CompanionPose.make(info: info(.done), t: 1, motion: true).face == .happy)
        check("error: cruces", CompanionPose.make(info: info(.error), t: 1, motion: true).face == .cross)
        check("en reposo muestra el cursor parpadeando", CompanionPose.make(info: info(.idle), t: 0.1, motion: true).face != CompanionPose.make(info: info(.idle), t: 0.6, motion: true).face)

        // 3. reacciones mutuas
        check("Codex en reposo mira a Claude pensar (puntos)", { if case .dots? = CompanionPose.make(info: info(.idle, claude: .thinking), t: 1, motion: true).emote { return true }; return false }())
        check("Claude espera aprobacion: Codex pone '!'", CompanionPose.make(info: info(.idle, claude: .waiting), t: 1, motion: true).emote == .bang)
        check("Claude falla: Codex pone '?'", CompanionPose.make(info: info(.idle, claude: .error), t: 1, motion: true).emote == .question)
        let hi = CompanionPose.make(info: info(.idle, done: true), t: 0.1, motion: true)
        check("Claude termina: Codex aplaude (cara feliz, check y salto)", hi.face == .happy && hi.emote == .check && hi.hop > 0)
        check("Claude mira a Codex solo si este trabaja y Claude esta en reposo",
              CompanionLogic.lookX(peer: .thinking, claude: .idle, mirrored: false) == -1
              && CompanionLogic.lookX(peer: .tool, claude: .idle, mirrored: true) == 1
              && CompanionLogic.lookX(peer: .thinking, claude: .thinking, mirrored: false) == 0
              && CompanionLogic.lookX(peer: .idle, claude: .idle, mirrored: false) == 0
              && CompanionLogic.lookX(peer: nil, claude: .idle, mirrored: false) == 0)

        // 4. reducir movimiento: mismas caras, ninguna pose en movimiento
        var still = true
        for st in PetState.allCases {
            for k in 0..<40 {
                let p = CompanionPose.make(info: info(st, claude: .thinking, cheer: true), t: Double(k) * 0.13, motion: false)
                if p.hop != 0 || p.bob != 0 || p.shake != 0 || p.legs != .stand { still = false }
            }
        }
        check("sin movimiento: nada salta, vibra ni camina", still)
        check("sin movimiento la cara de pensar es estable (3 puntos)", CompanionPose.make(info: info(.thinking), t: 0.2, motion: false).face
              == CompanionPose.make(info: info(.thinking), t: 0.9, motion: false).face)

        // 4b. acciones propias de Codex y locomocion al arrastrar
        func actionInfo(_ gesture: CodexGesture? = nil, dragging: Bool = false) -> CompanionInfo {
            CompanionInfo(codex: .idle, claude: .idle, codexCheer: false, codexConcern: false, claudeDone: false,
                          gesture: gesture, dragging: dragging)
        }
        check("saludo de Codex levanta un brazo", CompanionPose.make(info: actionInfo(.wave), t: 0.2, motion: true).arms != .rest)
        check("saludo formal llega al visor", CompanionPose.make(info: actionInfo(.salute), t: 0.2, motion: true).arms == .salute)
        check("celebracion usa ambos brazos y salto", { let p = CompanionPose.make(info: actionInfo(.celebrate), t: 0, motion: true); return p.arms == .celebrate && p.hop > 0 }())
        check("patrulla alterna las patas", CompanionPose.make(info: actionInfo(.patrol), t: 0, motion: true).legs == .step)
        check("arrastrar mueve los pies y reducir movimiento los fija", CompanionPose.make(info: actionInfo(nil, dragging: true), t: 0, motion: true).legs == .step
              && CompanionPose.make(info: actionInfo(nil, dragging: true), t: 0, motion: false).legs == .stand)

        // 5. geometria del partido entre dos ventanas independientes
        let claudeF = CGRect(x: 800, y: 400, width: 128, height: 128)
        let codexLeft = CGRect(x: 560, y: 400, width: 128, height: 152)
        if let g = GameLayout.make(claude: claudeF, codex: codexLeft) {
            let inside = CGRect(origin: .zero, size: g.size)
            check("Codex a la izquierda: mira a la derecha y la pelota va de izquierda a derecha", g.facing == 1 && g.ballStart.x < g.ballEnd.x)
            check("la pelota, su sombra y el arco caben dentro de la capa del partido",
                  inside.contains(g.ballStart) && inside.contains(g.ballEnd)
                  && g.ballStart.y - StageMetrics.arcHeight >= 0 && g.ballEnd.y - StageMetrics.arcHeight >= 0
                  && g.groundStart < g.size.height && g.groundEnd < g.size.height)
            check("la capa cubre a las dos ventanas", g.stageFrame.contains(claudeF) && g.stageFrame.contains(codexLeft))
        } else { check("dos ventanas cercanas permiten el partido", false) }
        if let g = GameLayout.make(claude: claudeF, codex: CGRect(x: 1100, y: 400, width: 128, height: 152)) {
            check("Codex a la derecha: la pelota va de derecha a izquierda", g.facing == -1 && g.ballStart.x > g.ballEnd.x)
        } else { check("Codex a la derecha tambien permite el partido", false) }
        check("a mas de 640 px de distancia no hay partido", GameLayout.make(claude: claudeF, codex: CGRect(x: 100, y: 400, width: 128, height: 152)) == nil)
        check("a mas de 420 px de altura no hay partido", GameLayout.make(claude: claudeF, codex: CGRect(x: 700, y: -100, width: 128, height: 152)) == nil)
        check("a distinta altura la pelota sube o baja entre ambas", { () -> Bool in
            guard let g = GameLayout.make(claude: claudeF, codex: CGRect(x: 600, y: 520, width: 128, height: 152)) else { return false }
            return g.ballStart.y != g.ballEnd.y && g.ballStart.y - StageMetrics.arcHeight >= 0 }())
        check("las posiciones de las ventanas no cambian al calcular el partido (la capa se adapta a ellas)",
              { let a = claudeF, b = codexLeft; _ = GameLayout.make(claude: a, codex: b); return a == claudeF && b == codexLeft }())
        check("las mascotas se abrazan solo cuando quedan muy cerca y alineadas", {
            let close = GameLayout.make(claude: claudeF, codex: CGRect(x: 650, y: 400, width: 128, height: 152))?.hugEligible == true
            let far = GameLayout.make(claude: claudeF, codex: codexLeft)?.hugEligible == false
            let uneven = GameLayout.make(claude: claudeF, codex: CGRect(x: 650, y: 520, width: 128, height: 152))?.hugEligible == false
            return close && far && uneven
        }())

        // 5b. presencia: cada mascota segun la herramienta en uso
        func vis(claudeApp: Bool = false, hooks: Bool = false, codexApp: Bool = false, peer: Bool = false, auto: Bool = true, hidden: Bool = false) -> PresenceLogic.Visibility {
            PresenceLogic.visibility(PresenceLogic.presence(claudeAppOpen: claudeApp, hookSessionActive: hooks, codexAppOpen: codexApp, peerPresent: peer), auto: auto, userHidden: hidden)
        }
        check("solo Claude (app abierta): solo la mascota de Claude", vis(claudeApp: true) == .init(claudeWindow: true, codexWindow: false))
        check("solo Claude Code en terminal (hooks): solo Claude", vis(hooks: true) == .init(claudeWindow: true, codexWindow: false))
        check("solo Codex (app abierta): solo Codex", vis(codexApp: true) == .init(claudeWindow: false, codexWindow: true))
        check("solo Codex (adaptador en el bus): solo Codex", vis(peer: true) == .init(claudeWindow: false, codexWindow: true))
        check("ambos abiertos: ambos, cada uno en su ventana", vis(claudeApp: true, codexApp: true) == .init(claudeWindow: true, codexWindow: true))
        check("ninguno en uso: no se ve nada", vis() == .init(claudeWindow: false, codexWindow: false))
        check("sin modo automatico: Claude siempre, Codex si esta", vis(codexApp: true, auto: false) == .init(claudeWindow: true, codexWindow: true)
              && vis(auto: false) == .init(claudeWindow: true, codexWindow: false))
        check("ocultar desde el menu oculta todo", vis(claudeApp: true, codexApp: true, hidden: true) == .init(claudeWindow: false, codexWindow: false))

        // 5c. modo duo: ambos trabajando cerca activan la capa de paquetes, sin afectar el futbol.
        let store = PetStore()
        store.setApps(claude: true, codex: false)
        store.setPair(geometry: GameLayout.make(claude: claudeF, codex: codexLeft), codexSide: -1)
        store.apply(PetEvent(kind: .state(.thinking), session: "duo", tool: "", project: "", detail: "", origin: "terminal", workspace: "", task: ""))
        store.receive(line: "{\"v\":1,\"id\":\"codex\",\"state\":\"tool\",\"ts\":1,\"event\":\"working\"}")
        check("ambos trabajando cerca activan modo duo", store.collaborationActive && !store.gameActive)
        store.receive(line: "{\"v\":1,\"id\":\"codex\",\"state\":\"idle\",\"ts\":2}")
        check("modo duo termina cuando uno queda inactivo", !store.collaborationActive)

        // 5d. los controles generales tambien pueden probar y mostrar actividad de Codex.
        store.preview(.idle)
        store.previewCodex(.thinking)
        check("probar estado de Codex cambia solo a Codex", store.codexState == .thinking && store.bubbleFollowsCodex && store.bubbleState == .thinking)

        // 5d2. abrazo: solo con ambas mascotas tranquilas, para no esconder un estado que pide atencion.
        let hugGeo = GameLayout.make(claude: claudeF, codex: CGRect(x: 650, y: 400, width: 128, height: 152))
        let hug = PetStore()
        hug.setApps(claude: true, codex: true)
        hug.setPair(geometry: hugGeo, codexSide: -1)
        check("abrazo con ambas tranquilas, pegadas y a la misma altura", hug.hugActive)
        hug.previewCodex(.thinking)
        hug.setPair(geometry: hugGeo, codexSide: -1)
        check("el abrazo se corta si Codex trabaja (no esconde su estado)", !hug.hugActive)
        hug.previewCodex(.waiting)
        hug.setPair(geometry: hugGeo, codexSide: -1)
        check("y si Codex pide permiso", !hug.hugActive)
        hug.previewCodex(.done)
        hug.setPair(geometry: hugGeo, codexSide: -1)
        check("con Codex recien terminado vuelve a abrazar", hug.hugActive)
        hug.apply(PetEvent(kind: .state(.error), session: "hug", tool: "", project: "", detail: "", origin: "terminal", workspace: "", task: ""))
        hug.setPair(geometry: hugGeo, codexSide: -1)
        check("el abrazo se corta si Claude falla", !hug.hugActive)
        hug.setPair(geometry: GameLayout.make(claude: claudeF, codex: codexLeft), codexSide: -1)
        check("lejos no hay abrazo", !hug.hugActive)

        // 5e. el icono de la barra comunica que herramienta esta en uso.
        check("icono de barra distingue Claude, Codex y ambos", MenuIcon.mode(claude: false, codex: false) == .idle
              && MenuIcon.mode(claude: true, codex: false) == .claude
              && MenuIcon.mode(claude: false, codex: true) == .codex
              && MenuIcon.mode(claude: true, codex: true) == .both)

        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
