import Foundation

/// Curvas y tiempos de los efectos de entrada de la isla. Todo es puro: recibe la edad del efecto y devuelve datos,
/// asi se prueba sin ventana y en reposo no cuesta nada (los efectos solo corren unos segundos, en eventos).
enum IslandCinema {
    // MARK: curvas

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func easeOutCubic(_ x: Double) -> Double { let k = 1 - clamp01(x); return 1 - k * k * k }
    static func easeInOutCubic(_ x: Double) -> Double {
        let k = clamp01(x)
        return k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }

    // MARK: barrido de luz en el borde

    /// Duracion de la unica pasada de luz.
    static let sweepDuration: TimeInterval = 0.6
    /// Largo de la cola de luz como fraccion del perimetro.
    static let sweepTail = 0.2

    /// Posicion de la cabeza de la luz (0...1 del perimetro) a `age` segundos; nil fuera de la pasada.
    static func sweepHead(age: TimeInterval) -> Double? {
        guard age >= 0, age <= sweepDuration else { return nil }
        return easeInOutCubic(age / sweepDuration)
    }

    /// Opacidad del barrido: entra y sale suave para que no haya ni corte ni parpadeo.
    static func sweepAlpha(age: TimeInterval) -> Double {
        guard age >= 0, age <= sweepDuration else { return 0 }
        let k = age / sweepDuration
        return min(1, k / 0.15, (1 - k) / 0.25)
    }

    // MARK: aparicion escalonada de la tarjeta

    /// Desfase entre bloques y duracion de cada uno.
    static let cardStagger: TimeInterval = 0.055
    static let cardRevealLength: TimeInterval = 0.42
    static let cardBlur: Double = 7
    static let cardRise: Double = 8

    struct Reveal: Equatable { var opacity: Double; var offsetY: Double; var blur: Double }

    /// Estado del bloque `index` de la tarjeta a `age` segundos de que apareciera. Sin movimiento solo cambia la opacidad.
    static func reveal(age: TimeInterval, index: Int, motion: Bool) -> Reveal {
        let k = clamp01((age - Double(index) * cardStagger) / cardRevealLength)
        let e = easeOutCubic(k)
        guard motion else { return Reveal(opacity: k >= 1 ? 1 : e, offsetY: 0, blur: 0) }
        return Reveal(opacity: e, offsetY: (1 - e) * cardRise, blur: (1 - e) * cardBlur)
    }

    /// Cuando termina de aparecer la tarjeta con `blocks` bloques.
    static func revealTotal(blocks: Int) -> TimeInterval { cardRevealLength + Double(max(0, blocks - 1)) * cardStagger }

    // MARK: acento segun el riesgo

    /// Mezcla el color del agente con el del riesgo: nada en bajo, un toque en medio y mas en alto.
    static func accent(agent: UInt32, risk: PermissionRisk) -> UInt32 {
        let weight: Double
        switch risk { case .low: weight = 0; case .medium: weight = 0.18; case .high: weight = 0.5 }
        let target: UInt32 = risk == .high ? 0xD85C5C : 0xE7B45B
        func lerp(_ shift: UInt32) -> UInt32 {
            let a = Double((agent >> shift) & 0xFF), b = Double((target >> shift) & 0xFF)
            return UInt32((a + (b - a) * weight).rounded())
        }
        return lerp(16) << 16 | lerp(8) << 8 | lerp(0)
    }

    /// Respiracion del borde en riesgo alto: periodo lento, sin picos (entre 0,25 y 0,7).
    static let breathPeriod: TimeInterval = 3.2
    static let breathCycles = 6
    static func breath(at t: TimeInterval) -> Double {
        0.25 + 0.45 * (0.5 - 0.5 * cos(2 * .pi * t / breathPeriod))
    }
    /// Tras unos ciclos el borde se queda fijo: un permiso pendiente no debe gastar CPU para siempre.
    static var breathLength: TimeInterval { breathPeriod * Double(breathCycles) }

    // MARK: que efectos corren

    struct Plan: Equatable {
        var sweep: Bool
        var staggered: Bool
        var breathing: Bool
        /// Con reducir movimiento el riesgo alto se marca con un borde fijo en vez de respirar.
        var staticRiskEdge: Bool
    }

    static func plan(effectsOn: Bool, risk: PermissionRisk) -> Plan {
        Plan(sweep: effectsOn, staggered: effectsOn, breathing: effectsOn && risk == .high, staticRiskEdge: !effectsOn && risk == .high)
    }
}

// MARK: animo de la mascota ante un permiso

/// Como se ve la mascota mientras un permiso espera: depende del riesgo del comando y de lo que vio el ensayo.
enum PetMood: Equatable {
    case neutral
    /// riesgo alto sin ensayo: cejas preocupadas y la gota de sudor, quieta
    case wary
    /// el ensayo vio algo destructivo: ademas tiembla
    case uneasy
    /// el ensayo salio limpio: suspira y pone ojos contentos
    case relieved
}

extension IslandCinema {
    /// El ensayo manda sobre el riesgo estimado: lo que de verdad paso en la copia pesa mas que lo que se supone.
    static func mood(risk: PermissionRisk?, severity: RehearsalSeverity?) -> PetMood {
        let high = risk == .high
        switch severity {
        case .destructive: return .uneasy
        case .calm: return high ? .neutral : .relieved
        case .changes, .unknown: return high ? .wary : .neutral
        case nil: return high ? .wary : .neutral
        }
    }

    static let sighLength: TimeInterval = 0.9
    static let uneasyShake: Double = 0.12

    /// Ajusta la pose segun el animo. `since` es cuando empezo ese animo; sin movimiento solo cambian las expresiones.
    static func applyMood(_ pose: inout PetPose, mood: PetMood, t: TimeInterval, since: TimeInterval?, motion: Bool) {
        switch mood {
        case .neutral: return
        case .wary:
            pose.worried = true
        case .uneasy:
            pose.worried = true
            if motion { pose.dx += CGFloat(sin(t * 38) * uneasyShake) }
        case .relieved:
            pose.happy = true; pose.blink = false
            if motion, let since, t >= since, t - since < sighLength {
                let k = (t - since) / sighLength, w = sin(k * .pi)
                pose.scaleY *= CGFloat(1 - 0.07 * w); pose.scaleX *= CGFloat(1 + 0.03 * w)
                pose.dy += CGFloat(0.3 * w)
            }
        }
    }
}
