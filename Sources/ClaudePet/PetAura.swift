import SwiftUI

/// Halo suave detrás de cada mascota. Es una lectura del estado que ya existe: no añade datos.
/// Azul = trabajando (más rápido cuanto más exige), rojo = error o colisión, sin halo en reposo.
struct AuraStyle: Equatable {
    enum Tint: Equatable { case accent, alert }
    let tint: Tint
    let intensity: Double      // 0...1, opacidad máxima del centro
    let period: Double         // segundos por respiración
    let ring: Bool             // borde fino: pide atención
}

enum PetAura {
    static func style(state: PetState, collision: Bool) -> AuraStyle? {
        if collision && state.isCollisionWork { return AuraStyle(tint: .alert, intensity: 0.34, period: 1.2, ring: true) }
        switch state {
        case .idle, .done: return nil
        case .starting, .thinking: return AuraStyle(tint: .accent, intensity: 0.24, period: 3.2, ring: false)
        case .tool: return AuraStyle(tint: .accent, intensity: 0.34, period: 1.6, ring: false)
        case .waiting: return AuraStyle(tint: .accent, intensity: 0.46, period: 0.9, ring: true)
        case .error: return AuraStyle(tint: .alert, intensity: 0.4, period: 2.4, ring: true)
        }
    }

    /// Opacidad en un instante: respira entre el 65 % y el 100 % de la intensidad. Sin movimiento queda fija.
    static func level(_ style: AuraStyle, at time: Double, animate: Bool) -> Double {
        guard animate else { return style.intensity * 0.85 }
        let wave = 0.5 + 0.5 * sin(time * 2 * .pi / style.period)
        return style.intensity * (0.65 + 0.35 * wave)
    }
}

struct AuraView: View {
    let state: PetState
    var collision = false
    let animate: Bool
    var diameter: CGFloat = 112

    var body: some View {
        if let style = PetAura.style(state: state, collision: collision) {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animate)) { ctx in
                let level = PetAura.level(style, at: animate ? ctx.date.timeIntervalSinceReferenceDate : 0, animate: animate)
                let color = style.tint == .alert ? Color(hex: 0xFF8A7A) : Color(hex: 0x7DB4FF)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [color.opacity(level), color.opacity(level * 0.35), color.opacity(0)],
                                             center: .center, startRadius: 4, endRadius: diameter / 2))
                    if style.ring {
                        Circle().stroke(color.opacity(level * 1.1), lineWidth: 1.5).padding(diameter * 0.1)
                    }
                }
                .frame(width: diameter, height: diameter)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
