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

/// Escena de la mascota en la vista abierta: grande, con su suelo y el punto de estado.
struct IslandStage: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    let agent: IslandAgentTab
    var statusColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .onTapGesture { model.poke() }
            .accessibilityLabel("\(agent.rawValue): toca para saludar")
        }
        .frame(width: 104, height: 100)
        .overlay(alignment: .topLeading) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black, lineWidth: 1.5)).offset(x: 2, y: 2)
                .opacity(statusColor == .clear ? 0 : 1)
        }
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
                Text(tab.rawValue).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.8))
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 4)
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
