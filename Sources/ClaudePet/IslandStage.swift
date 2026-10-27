import SwiftUI

/// Texto que se escribe letra a letra, como si la mascota hablara. Con reducir movimiento aparece completo.
struct TypewriterText: View {
    let text: String
    var reduceMotion = false
    @State private var shown = 0

    var body: some View {
        let count = text.count
        let visible = reduceMotion ? count : min(shown, count)
        HStack(spacing: 0) {
            Text(String(text.prefix(visible)))
            if visible < count { Text("▍").foregroundColor(Color(hex: 0xE0824F)) }
        }
        .task(id: text) {
            guard !reduceMotion else { return }
            shown = 0
            for i in 1...max(1, count) {
                try? await Task.sleep(nanoseconds: 26_000_000)
                if Task.isCancelled { return }
                shown = i
            }
        }
        .accessibilityLabel(text)
    }
}

/// Escena de la mascota en la vista abierta: grande, con su suelo, su mundo y sus extras.
struct IslandStage: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    let agent: IslandAgentTab
    var statusColor: Color

    private var state: PetState { agent == .claude ? store.state : store.codexState }
    private var animated: Bool { store.animationsEnabled && !store.reduceMotion && !IslandSnapshot.isRendering }
    private var width: CGFloat { store.codexPresent ? 150 : 104 }

    var body: some View {
        ZStack(alignment: .bottom) {
            if animated { StageSceneView(state: state).frame(width: 104, height: 100) }      // el clima y los detalles del estado
            EvolutionView(level: store.weeklyRecap.level).frame(width: 104, height: 100)       // halo y estrellitas por nivel
            // suelo: un disco de luz tenue bajo los pies
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 96, height: 14)
                .offset(y: 4)
            Group {
                if agent == .claude { PetFace(store: store, model: model) }
                else { CodexMini(store: store, model: model, greet: false) }
            }
            .frame(width: 92, height: 92)
            .contentShape(Rectangle())
            .onTapGesture { if agent == .claude { model.poke() } else { model.pokeCodex() } }
            .accessibilityLabel("\(agent.rawValue): toca para saludar")
            if animated, let ping = model.pingAt { ActivityPingView(since: ping).frame(width: 110, height: 110) }
            if animated, agent == .claude, let rain = model.lineRain {
                LineRainView(since: rain.since, added: rain.added, deleted: rain.deleted).frame(width: 104, height: 100)
            }
        }
        .frame(width: 104, height: 100)
        .overlay(alignment: .topLeading) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black, lineWidth: 1.5)).offset(x: 2, y: 2)
                .opacity(statusColor == .clear ? 0 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if let top = model.hourglassTop { HourglassView(top: top).offset(x: 10, y: -2) }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.codexPresent { DuoMate(store: store, model: model, active: agent).offset(x: 44, y: 2) }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// El otro agente, pequeno al lado: cuando los dos terminan casi a la vez, chocan los cinco.
struct DuoMate: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    let active: IslandAgentTab

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let now = ProcessInfo.processInfo.systemUptime
            let p = DuoScene.highFive(claudeDoneAt: model.claudeDoneAt, codexDoneAt: model.codexDoneAt, now: now)
            ZStack {
                Group {
                    if active == .claude { CodexMini(store: store, model: model, greet: false) }
                    else { PetFace(store: store, model: model) }
                }
                .frame(width: 38, height: 40)
                .offset(y: p.map { CGFloat(-sin($0 * .pi) * 10) } ?? 0)
                if let p {
                    // chispas entre los dos en el momento del choque
                    FxCanvas(pixels: (0..<10).map { i in
                        let a = Double(i) / 10 * 2 * .pi, r = 0.08 + p * 0.3
                        return FxPixel(x: 0.1 + cos(a) * r, y: 0.5 + sin(a) * r, size: 1.5, color: i % 2 == 0 ? 0xFFE9A8 : 0xFF9F43, alpha: 1 - p)
                    }, unit: 3).frame(width: 60, height: 50).offset(x: -34)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Pestana de agente con su carita: sustituye al selector de texto.
struct AgentAvatarTab: View {
    let tab: IslandAgentTab
    let selected: Bool
    let state: PetState
    var codexSkin: CodexSkin = .cloud
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Canvas { gc, size in
                    if tab == .claude { PetFace.draw(&gc, size: size, pixels: Sprite.block(state, tick: 3), pose: PetPose()) }
                    else {
                        let u = min(size.width / 18, size.height / 21)
                        for c in CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true), skin: codexSkin) {
                            gc.fill(Path(CGRect(x: CGFloat(c.x) * u, y: CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
                        }
                    }
                }.frame(width: 22, height: 22)
                if selected { Text(tab.rawValue).font(.system(size: 11, weight: .medium)) }
            }
            .foregroundColor(selected ? .black : .white.opacity(0.8))
            .padding(.leading, 6).padding(.trailing, selected ? 12 : 6).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(hover ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
        .accessibilityLabel("agente \(tab.rawValue)").accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Aparicion escalonada de las secciones al abrir la isla.
struct Reveal: ViewModifier {
    let index: Int
    let shown: Bool
    let animated: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown || !animated ? 1 : 0)
            .offset(y: shown || !animated ? 0 : 10)
            .animation(animated ? .spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.06) : nil, value: shown)
    }
}
extension View { func reveal(_ index: Int, _ shown: Bool, animated: Bool) -> some View { modifier(Reveal(index: index, shown: shown, animated: animated)) } }
