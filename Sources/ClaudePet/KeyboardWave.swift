import Foundation

/// El teclado respira: la retroiluminacion sigue el estado de los agentes. Esto es solo la forma de la onda (pura, sin hardware).
/// Cada estado tiene su ritmo, y se mide siempre respecto al brillo que tu tenias para no dejarte el teclado distinto de como estaba.
enum KeyboardWave {
    /// Cuanto pide atencion un estado: cuando los dos agentes estan activos manda el mas urgente.
    static func urgency(_ s: PetState) -> Int {
        switch s {
        case .waiting: return 4
        case .error: return 3
        case .tool, .thinking, .starting: return 2
        case .done: return 1
        case .idle: return 0
        }
    }

    static func combined(_ a: PetState, _ b: PetState) -> PetState { urgency(b) > urgency(a) ? b : a }

    private static func wave(_ time: TimeInterval, period: TimeInterval) -> Float { Float(0.5 + 0.5 * sin(2 * .pi * time / period - .pi / 2)) }

    /// Brillo objetivo de 0 a 1, o nil para dejar el teclado como lo tiene el usuario.
    /// - `age`: segundos desde que empezo este estado (para los destellos de una sola vez).
    /// - `time`: reloj continuo (para las ondas que se repiten).
    /// - `base`: el brillo del usuario. Con la luz apagada (menos de 5 %) no se enciende nada.
    static func level(state: PetState, age: TimeInterval, time: TimeInterval, base: Float) -> Float? {
        guard base >= 0.05 else { return nil }
        switch state {
        case .thinking, .starting:
            // respiracion lenta: 4,5 s, del 30 % al 100 % de tu brillo
            return base * (0.30 + 0.70 * wave(time, period: 4.5))
        case .tool:
            // mas viva mientras trabaja: 1,4 s
            return base * (0.45 + 0.55 * wave(time, period: 1.4))
        case .waiting:
            // dos latidos seguidos y una pausa, siempre hasta el maximo para que se vea: pide tu atencion
            let phase = time.truncatingRemainder(dividingBy: 1.3)
            func beat(_ start: Double, _ length: Double) -> Float { phase >= start && phase < start + length ? Float(sin(.pi * (phase - start) / length)) : 0 }
            return min(1, 0.12 * base + (1 - 0.12 * base) * max(beat(0, 0.24), beat(0.34, 0.24)))
        case .error:
            // tres destellos secos y se acaba: no se queda parpadeando
            guard age < 1.8 else { return nil }
            return sin(2 * .pi * 2.5 * age) > 0 ? 1 : 0.15 * base
        case .done:
            // una ola suave que sube y baja una vez
            guard age < 1.3 else { return nil }
            return min(1, base + (1 - base) * 0.9 * Float(sin(.pi * age / 1.3)))
        case .idle:
            return nil
        }
    }
}
