import SwiftUI

extension PetStore {
    /// Los efectos de entrada solo corren con animaciones activas, sin reducir movimiento y sin ahorro de energia.
    var cinemaEffectsOn: Bool { animationsEnabled && !reduceMotion && !energySaving && !IslandSnapshot.isRendering }
}

/// Edad fija de la aparicion de la tarjeta; solo la usan las capturas para congelar un fotograma.
private struct CinemaRevealAgeKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    var cinemaRevealAge: Double? {
        get { self[CinemaRevealAgeKey.self] }
        set { self[CinemaRevealAgeKey.self] = newValue }
    }
}

/// Un bloque de la tarjeta que entra con desfase: sube unos puntos, se aclara y el desenfoque se afila.
/// La edad es el dato animable: SwiftUI la interpola durante la aparicion y en reposo no hay nada que redibujar.
struct CardReveal: ViewModifier, Animatable {
    var age: Double
    let index: Int
    var animatableData: Double { get { age } set { age = newValue } }

    func body(content: Content) -> some View {
        let r = IslandCinema.reveal(age: age, index: index, motion: true)
        content
            .opacity(r.opacity)
            .offset(y: r.offsetY)
            .blur(radius: r.blur)
    }
}

extension View {
    func cardReveal(age: Double, index: Int) -> some View { modifier(CardReveal(age: age, index: index)) }
}

/// Un trazo de luz que recorre el borde una sola vez. `progress` (0...1) es el tiempo de la pasada: la cabeza avanza con
/// su curva y la cola se apaga hacia atras. Sin estado propio, asi se dibuja igual en una captura.
struct EdgeSweepView: View, Animatable {
    var progress: Double
    let shape: IslandShape
    let color: Color
    var animatableData: Double { get { progress } set { progress = newValue } }

    private static let slices = 9

    var body: some View {
        let age = progress * IslandCinema.sweepDuration
        if let head = IslandCinema.sweepHead(age: age) {
            let alpha = IslandCinema.sweepAlpha(age: age)
            let tail = IslandCinema.sweepTail
            ZStack {
                ForEach(0..<Self.slices, id: \.self) { i in
                    let to = head - tail * Double(i) / Double(Self.slices)
                    let from = max(0, head - tail * Double(i + 1) / Double(Self.slices))
                    if to > 0, from < to {
                        let fall = pow(1 - Double(i) / Double(Self.slices), 1.7)
                        shape.trim(from: from, to: min(1, to)).stroke(color.opacity(alpha * fall * 0.95), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                        if i < 3 { shape.trim(from: from, to: min(1, to)).stroke(color.opacity(alpha * fall * 0.16), style: StrokeStyle(lineWidth: 9, lineCap: .round)) }
                    }
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// Borde de un permiso pendiente: la pasada de luz al llegar y, en riesgo alto, un borde rojo apagado que respira unos
/// ciclos y se queda fijo. Con reducir movimiento (o sin animaciones) el riesgo alto es un borde fijo, sin respiracion.
struct PermissionEdgeFX: View {
    let shape: IslandShape
    let risk: PermissionRisk
    let plan: IslandCinema.Plan
    var agent: UInt32 = 0xE0824F
    @State private var sweep = 0.0
    @State private var inhale = false
    @State private var settled = false

    private var breathAlpha: Double { settled ? 0.4 : (inhale ? 0.64 : 0.22) }

    var body: some View {
        ZStack {
            if plan.breathing || plan.staticRiskEdge {
                shape.stroke(Color(hex: 0xD85C5C).opacity(plan.staticRiskEdge ? 0.5 : breathAlpha), lineWidth: 2)
            }
            if plan.sweep { EdgeSweepView(progress: sweep, shape: shape, color: Color(hex: IslandCinema.accent(agent: agent, risk: risk))) }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task {
            guard plan.sweep else { return }
            withAnimation(.linear(duration: IslandCinema.sweepDuration)) { sweep = 1 }
            guard plan.breathing else { return }
            // una respiracion es subir y bajar: un numero impar de medios ciclos deja el borde en su punto alto antes de asentarse
            withAnimation(.easeInOut(duration: IslandCinema.breathPeriod / 2).repeatCount(IslandCinema.breathCycles * 2 - 1, autoreverses: true)) { inhale = true }
            try? await Task.sleep(nanoseconds: UInt64(IslandCinema.breathLength * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.9)) { settled = true }
        }
    }
}

/// El cierre de "termino": una rafaga de pixeles y un anillo que se disuelve, una sola vez, sobre la mascota.
/// Dibuja con el `FxCanvas` de los demas efectos; la edad se anima (sin TimelineView) y al acabar no queda nada vivo.
struct FinishBurstView: View, Animatable {
    var age: Double
    let color: UInt32
    var side: CGFloat = 132
    var animatableData: Double { get { age } set { age = newValue } }

    var body: some View {
        FxCanvas(pixels: IslandCinema.burst(age: age, color: color), unit: side / CGFloat(IslandCinema.burstGrid))
            .frame(width: side, height: side)
    }
}

/// Lanza el cierre una vez (tras `delay`) y se quita solo de la jerarquia.
struct FinishBurstHost: View {
    let color: UInt32
    var delay: TimeInterval = 0
    @State private var age = 0.0
    @State private var started = false
    @State private var finished = false

    var body: some View {
        Group { if started && !finished { FinishBurstView(age: age, color: color) } }
            .allowsHitTesting(false).accessibilityHidden(true)
            .task {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                started = true
                withAnimation(.linear(duration: IslandCinema.burstLength)) { age = IslandCinema.burstLength }
                try? await Task.sleep(nanoseconds: UInt64((IslandCinema.burstLength + 0.05) * 1_000_000_000))
                finished = true
            }
    }
}
