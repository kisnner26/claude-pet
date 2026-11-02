import Foundation

enum KeyboardWaveSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }
        let base: Float = 0.7

        check("en calma no toca el teclado", KeyboardWave.level(state: .idle, age: 5, time: 5, base: base) == nil)
        check("con la luz apagada no se enciende nada", PetState.allCases.allSatisfy { KeyboardWave.level(state: $0, age: 0.1, time: 0.1, base: 0.02) == nil })
        let thinking = stride(from: 0.0, to: 9.0, by: 0.05).compactMap { KeyboardWave.level(state: .thinking, age: 0, time: $0, base: base) }
        check("pensando respira entre el 30 % y el 100 % de tu brillo", (thinking.min() ?? 0) >= base * 0.29 && (thinking.max() ?? 0) <= base * 1.001 && (thinking.max() ?? 0) - (thinking.min() ?? 0) > base * 0.6)
        check("pensando nunca pasa de tu brillo", thinking.allSatisfy { $0 <= base + 0.0001 })
        let tool = stride(from: 0.0, to: 4.0, by: 0.02).compactMap { KeyboardWave.level(state: .tool, age: 0, time: $0, base: base) }
        check("trabajando es mas rapido: sube y baja varias veces en 4 s", tool.indices.dropFirst().filter { tool[$0] > tool[$0 - 1] && tool[$0 - 1] <= (tool[max(0, $0 - 2)]) }.count >= 2)
        let waiting = stride(from: 0.0, to: 3.9, by: 0.02).compactMap { KeyboardWave.level(state: .waiting, age: 0, time: $0, base: base) }
        check("un permiso pendiente llega al maximo aunque tu brillo sea medio", (waiting.max() ?? 0) > 0.95)
        check("entre latidos baja a casi nada", (waiting.min() ?? 1) < 0.15)
        let beats = waiting.indices.dropFirst().filter { waiting[$0] > 0.9 && waiting[$0 - 1] <= 0.9 }.count
        check("hace dos latidos por vuelta (tres vueltas, seis latidos)", beats == 6)
        check("el error da destellos y se acaba", KeyboardWave.level(state: .error, age: 0.05, time: 0, base: base) == 1 && KeyboardWave.level(state: .error, age: 0.3, time: 0, base: base) == 0.15 * base && KeyboardWave.level(state: .error, age: 2, time: 0, base: base) == nil)
        let errorFlashes = stride(from: 0.0, to: 1.8, by: 0.01).filter { (KeyboardWave.level(state: .error, age: $0, time: 0, base: base) ?? 0) == 1 }
        check("son unos tres destellos", errorFlashes.count > 60 && errorFlashes.count < 100)
        let done = stride(from: 0.0, to: 1.3, by: 0.05).compactMap { KeyboardWave.level(state: .done, age: $0, time: 0, base: base) }
        check("terminar es una ola que sube y vuelve a tu brillo", (done.max() ?? 0) > base + 0.15 && abs((done.first ?? 9) - base) < 0.01 && KeyboardWave.level(state: .done, age: 1.4, time: 0, base: base) == nil)
        check("nunca devuelve algo fuera de 0 a 1", PetState.allCases.allSatisfy { s in stride(from: 0.0, to: 6.0, by: 0.07).allSatisfy { t in let v = KeyboardWave.level(state: s, age: t, time: t, base: 1) ?? 0.5; return v >= 0 && v <= 1 } })
        check("entre dos agentes manda el que mas urge", KeyboardWave.combined(.thinking, .waiting) == .waiting && KeyboardWave.combined(.error, .tool) == .error && KeyboardWave.combined(.idle, .done) == .done && KeyboardWave.combined(.tool, .tool) == .tool)

        print(ok ? "TECLADO OK" : "TECLADO FALLO")
        let allow = stride(from: 0.0, to: 0.7, by: 0.02).compactMap { KeyboardWave.ack(allow: true, age: $0, base: base) }
        check("aprobar es una ola que sube y baja y acaba", (allow.max() ?? 0) > 0.95 && allow.allSatisfy { $0 >= base - 0.001 && $0 <= 1 } && KeyboardWave.ack(allow: true, age: 0.7, base: base) == nil)
        let deny = stride(from: 0.0, to: 0.5, by: 0.01).compactMap { KeyboardWave.ack(allow: false, age: $0, base: base) }
        var flashes = 0, prevHigh = false
        for v in deny { let high = v > 0.9; if high && !prevHigh { flashes += 1 }; prevHigh = high }
        check("rechazar son dos destellos secos y acaba", flashes == 2 && KeyboardWave.ack(allow: false, age: 0.5, base: base) == nil)
        check("la confirmacion no enciende un teclado apagado", KeyboardWave.ack(allow: true, age: 0.2, base: 0.02) == nil && KeyboardWave.ack(allow: false, age: 0.1, base: 0.02) == nil)
        return ok
    }
}
