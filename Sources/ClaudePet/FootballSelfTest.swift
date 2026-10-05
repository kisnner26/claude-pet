import Foundation

/// `ClaudePet --selftest-football`: verifica la logica del partido con un reloj falso.
/// Imprime PASS/FAIL por caso y sale con codigo 0 solo si todo pasa.
enum FootballSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failures += 1 }
        }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
        let cfg = FootballConfig()   // 8 s de espera, 300 s de cooldown (valores de producto)

        // 1. espera de inactividad compartida
        do {
            let g = FootballGame(config: cfg)
            g.update(now: at(0), claude: .idle, peer: .idle)
            g.update(now: at(7.9), claude: .idle, peer: .idle)
            check("no empieza antes de 8 s de inactividad compartida", !g.isActive)
            g.update(now: at(8.0), claude: .idle, peer: .idle)
            check("empieza a los 8 s", g.isActive)
        }
        // 2. requisitos de presencia
        do {
            let g = FootballGame(config: cfg)
            for s in stride(from: 0.0, through: 30, by: 1) { g.update(now: at(s), claude: .idle, peer: nil) }
            check("sin par (o con estado desconocido) no empieza", !g.isActive)
            let h = FootballGame(config: cfg)
            for s in stride(from: 0.0, through: 30, by: 1) { h.update(now: at(s), claude: .thinking, peer: .idle) }
            check("si Claude trabaja no empieza", !h.isActive)
            let k = FootballGame(config: cfg)
            for s in stride(from: 0.0, through: 30, by: 1) { k.update(now: at(s), claude: .idle, peer: .done) }
            check("si el par no esta idle no empieza", !k.isActive)
        }
        // 3. cancelacion inmediata por cualquier estado, de cualquiera de los dos
        for st in [PetState.starting, .thinking, .tool, .waiting, .error, .done] {
            let a = FootballGame(config: cfg)
            a.update(now: at(0), claude: .idle, peer: .idle); a.update(now: at(8), claude: .idle, peer: .idle)
            let was = a.isActive
            a.update(now: at(8.1), claude: st, peer: .idle)
            check("Claude -> \(st.rawValue) cancela al instante", was && !a.isActive)
            let b = FootballGame(config: cfg)
            b.update(now: at(0), claude: .idle, peer: .idle); b.update(now: at(8), claude: .idle, peer: .idle)
            b.update(now: at(8.1), claude: .idle, peer: st)
            check("par -> \(st.rawValue) cancela al instante", b.isActive == false)
        }
        do {
            let g = FootballGame(config: cfg)
            g.update(now: at(0), claude: .idle, peer: .idle); g.update(now: at(8), claude: .idle, peer: .idle)
            g.update(now: at(9), claude: .idle, peer: nil)
            check("el par desaparece -> cancela", !g.isActive)
        }
        // 4. termina solo y no se repite dentro de 5 minutos
        do {
            let g = FootballGame(config: cfg)
            g.update(now: at(0), claude: .idle, peer: .idle); g.update(now: at(8), claude: .idle, peer: .idle)
            g.update(now: at(8 + FootballChoreography.duration + 0.1), claude: .idle, peer: .idle)
            check("termina solo al acabar la coreografia", !g.isActive)
            var restarted = false
            for s in stride(from: 20.0, to: 307.9, by: 1) {          // 8 s .. justo antes de 300 s desde el inicio
                g.update(now: at(s), claude: .idle, peer: .idle); if g.isActive { restarted = true }
            }
            check("no reinicia antes de 5 minutos", !restarted)
            g.update(now: at(308.0), claude: .idle, peer: .idle)
            g.update(now: at(316.1), claude: .idle, peer: .idle)
            check("reinicia pasados 5 minutos y 8 s de inactividad", g.isActive)
        }
        do {
            let g = FootballGame(config: cfg)
            g.update(now: at(0), claude: .idle, peer: .idle); g.update(now: at(8), claude: .idle, peer: .idle)
            g.update(now: at(9), claude: .thinking, peer: .idle)                  // cancelado
            for s in stride(from: 10.0, to: 307.0, by: 1) { g.update(now: at(s), claude: .idle, peer: .idle) }
            check("un partido cancelado tambien cuenta para los 5 minutos", !g.isActive)
        }
        // 4b. disparador manual
        do {
            let g = FootballGame(config: cfg)
            g.forceStart(now: at(0))
            check("el disparador manual empieza al instante", g.isActive)
            g.update(now: at(1), claude: .thinking, peer: nil)
            check("y no lo cancelan ni el trabajo de Claude ni la ausencia del par", g.isActive)
            g.update(now: at(FootballChoreography.duration + 0.1), claude: .thinking, peer: nil)
            check("termina solo al acabar la coreografia", !g.isActive)
            let h = FootballGame(config: cfg)
            h.forceStart(now: at(0)); h.cancel()
            check("cancel() (animaciones apagadas) lo detiene", !h.isActive)
            let k = FootballGame(config: cfg)
            k.forceStart(now: at(0))
            k.update(now: at(13), claude: .idle, peer: .idle)
            var again = false
            for s in stride(from: 14.0, to: 290, by: 1) { k.update(now: at(s), claude: .idle, peer: .idle); again = again || k.isActive }
            check("un disparo manual cuenta para el cooldown automatico", !again)
        }
        // 5. coreografia
        do {
            var minT = 9.0, maxT = -1.0, ok = true, hop = false, kick = false, celebrate = false, header = false, kickP = false
            var prevIn = -1.0, monotonic = true
            for i in 0..<Int(FootballChoreography.duration * 20) {
                guard let f = FootballChoreography.frame(elapsed: Double(i) / 20, reduceMotion: false) else { ok = false; continue }
                minT = min(minT, f.ballT); maxT = max(maxT, f.ballT)
                if f.ballT < 0 || f.ballT > 1 || f.arc < 0 || f.arc > 1 || f.ballOpacity < 0 || f.ballOpacity > 1 { ok = false }
                if f.avatarIn < prevIn { monotonic = false }; prevIn = f.avatarIn
                hop = hop || f.claudeHop; kick = kick || f.kickFoot; celebrate = celebrate || f.celebrateMoving
                header = header || f.headerPulse > 0.5; kickP = kickP || f.kickPulse > 0.5
            }
            check("la pelota recorre todo el trayecto entre Codex (0) y Claude (1) dentro de limites", ok && minT == 0 && maxT == 1)
            check("hay patada, polvo, cabeceo, destello y celebracion", kick && kickP && hop && header && celebrate)
            check("el avatar de Codex entra sin retroceder y termina en su sitio", monotonic && prevIn == 1)
            check("fuera de la duracion no hay fotograma", FootballChoreography.frame(elapsed: -0.1, reduceMotion: false) == nil
                  && FootballChoreography.frame(elapsed: FootballChoreography.duration, reduceMotion: false) == nil)
        }
        do {
            var still = true, faded = false
            for i in 0..<Int(FootballChoreography.duration * 20) {
                guard let f = FootballChoreography.frame(elapsed: Double(i) / 20, reduceMotion: true) else { still = false; continue }
                if f.ballT != FootballChoreography.reducedBallT || f.arc != 0 || f.avatarIn != 1 || f.kickFoot || f.kickPulse != 0
                    || f.headerPulse != 0 || f.claudeHop || f.avatarHop || f.celebrateMoving || !f.reduced { still = false }
                if f.ballOpacity > 0 && f.ballOpacity < 1 { faded = true }
            }
            check("reducir movimiento: nada se desplaza (pelota y avatar fijos, sin saltos ni patada)", still)
            check("reducir movimiento: la transicion es un fundido suave", faded)
        }
        print(failures == 0 ? "TODO OK" : "\(failures) FALLOS")
        return failures == 0
    }
}
