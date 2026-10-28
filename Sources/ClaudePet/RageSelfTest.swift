import Foundation
import CoreGraphics

/// `ClaudePet --selftest-rage`: cuando se enfada, la coreografia y la eleccion de ventana. Nada de esto toca ventanas reales.
enum RageSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        let now = 100.0
        check("un solo toque no enfada", !RageTrigger.shouldRage(pokes: [99.9], now: now, roll: 0, lastRage: nil))
        check("dos toques seguidos y suerte: se enfada", RageTrigger.shouldRage(pokes: [99.2, 99.9], now: now, roll: 0.1, lastRage: nil))
        check("dos toques sin suerte: no", !RageTrigger.shouldRage(pokes: [99.2, 99.9], now: now, roll: 0.9, lastRage: nil))
        check("dos toques muy separados: no", !RageTrigger.shouldRage(pokes: [96, 99.9], now: now, roll: 0, lastRage: nil))
        check("tres toques marean, no enfadan", !RageTrigger.shouldRage(pokes: [99.0, 99.4, 99.9], now: now, roll: 0, lastRage: nil))
        check("se calma un minuto", !RageTrigger.shouldRage(pokes: [99.2, 99.9], now: now, roll: 0, lastRage: 60) && RageTrigger.shouldRage(pokes: [99.2, 99.9], now: now, roll: 0, lastRage: 30))

        check("con el modo foco no se enfada", !RageTrigger.allowed(focus: true, pomodoroWorking: false))
        check("en mitad de un pomodoro de trabajo no se enfada", !RageTrigger.allowed(focus: false, pomodoroWorking: true))
        check("sin foco ni pomodoro si puede enfadarse", RageTrigger.allowed(focus: false, pomodoroWorking: false))

        let first = RageChoreography.frame(at: 0), last = RageChoreography.frame(at: RageChoreography.duration)
        check("empieza pequena y sin brillo", abs(first.size - RageChoreography.small) < 0.001 && first.walk == 0 && first.glow == 0)
        check("termina pequena, en casa y sin brillo", abs(last.size - RageChoreography.small) < 0.001 && last.walk == 0 && last.glow == 0)
        check("se hace gigante", RageChoreography.frame(at: 1.2).size == 1 && RageChoreography.frame(at: 0.7).size > 0.8)
        check("camina hasta la ventana", RageChoreography.frame(at: 1.4).walk > 0.2 && RageChoreography.frame(at: 2.0).walk == 1)
        check("la patada ocurre antes del golpe y el golpe despues", RageChoreography.frame(at: RageChoreography.windupEnd + 0.05).kicking && !RageChoreography.frame(at: 1.0).kicking && !RageChoreography.frame(at: 3.0).kicking)
        check("el golpe dura menos de medio segundo", RageChoreography.frame(at: RageChoreography.impactAt - 0.01).impact == nil && RageChoreography.frame(at: RageChoreography.impactAt + 0.1).impact != nil && RageChoreography.frame(at: RageChoreography.impactAt + 0.5).impact == nil)
        check("el golpe cae dentro de la patada", RageChoreography.impactAt > RageChoreography.windupEnd && RageChoreography.impactAt < RageChoreography.kickEnd)
        var smooth = true, prev = RageChoreography.frame(at: 0)
        for i in 1...400 { let f = RageChoreography.frame(at: Double(i) * 0.01); if abs(f.size - prev.size) > 0.12 || abs(f.walk - prev.walk) > 0.12 { smooth = false }; prev = f }
        check("sin saltos bruscos de tamano ni de paseo", smooth)

        func win(_ pid: Int, _ owner: String, _ layer: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double, alpha: Double = 1) -> [String: Any] {
            [kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowOwnerName as String: owner, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h]]
        }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let list = [win(1, "claude pet", 0, 0, 0, 800, 600), win(2, "Dock", 0, 0, 800, 1440, 100), win(3, "Menu", 25, 0, 0, 1440, 30), win(4, "Pequena", 0, 10, 10, 100, 80),
                    win(5, "Pantalla completa", 0, 0, 0, 1440, 900), win(6, "Invisible", 0, 100, 100, 600, 400, alpha: 0), win(7, "Safari", 0, 120, 90, 900, 600), win(8, "Notas", 0, 300, 200, 500, 400)]
        let hit = WindowKick.pick(from: list, ownPID: 1, screen: screen, screenGlobal: screen)
        check("elige la ventana de arriba que no es nuestra ni del sistema", hit?.owner == "Safari" && hit?.pid == 7)
        check("las coordenadas son locales a la pantalla", hit?.frame == CGRect(x: 120, y: 90, width: 900, height: 600))
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let other = WindowKick.pick(from: [win(9, "Terminal", 0, 1600, 100, 700, 500)], ownPID: 1, screen: second, screenGlobal: second)
        check("con varias pantallas, la ventana se pasa a coordenadas de esa pantalla", other?.frame == CGRect(x: 160, y: 300, width: 700, height: 500))
        check("sin ventanas elegibles no hace nada", WindowKick.pick(from: [win(1, "claude pet", 0, 0, 0, 800, 600)], ownPID: 1, screen: screen, screenGlobal: screen) == nil)
        check("ignora ventanas de otra pantalla", WindowKick.pick(from: [win(9, "Terminal", 0, 5000, 100, 700, 500)], ownPID: 1, screen: screen, screenGlobal: screen) == nil)

        print(failures == 0 ? "ENFADO OK" : "ENFADO \(failures) FALLOS")
        return failures == 0
    }
}
