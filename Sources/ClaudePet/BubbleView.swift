import SwiftUI

extension Notification.Name {
    static let bubbleRevealed = Notification.Name("claudepet.bubble.revealed")
    static let dashboardRevealed = Notification.Name("claudepet.dashboard.revealed")
}

/// Aparición con materia: la burbuja se condensa desde la mascota (desenfoque, escala y opacidad).
/// Con reducir movimiento solo hay un fundido.
struct Condense: ViewModifier {
    let progress: Double       // 0 = formada, 1 = disuelta
    let reduceMotion: Bool
    var anchor: UnitPoint = .bottom

    func body(content: Content) -> some View {
        content
            .blur(radius: reduceMotion ? 0 : progress * 10)
            .scaleEffect(reduceMotion ? 1 : 1 - 0.3 * progress, anchor: anchor)
            .opacity(1 - progress)
    }
}

struct BubbleView: View {
    @ObservedObject var store: PetStore
    @State private var dissolved = 0.0

    var body: some View {
        if let a = store.bubbleActivity, store.showBubble {
            BubbleCard(activity: a, state: store.bubbleState, flat: false)
                .modifier(Condense(progress: dissolved, reduceMotion: store.reduceMotion))
                .frame(width: 360, height: 76)
                .onReceive(NotificationCenter.default.publisher(for: .bubbleRevealed)) { _ in
                    var instant = Transaction(); instant.disablesAnimations = true
                    withTransaction(instant) { dissolved = 1 }
                    withAnimation(store.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.78)) { dissolved = 0 }
                }
        } else {
            Color.clear.frame(width: 360, height: 76)
        }
    }
}

/// La tarjeta de la burbuja. `flat` sustituye el cristal por carbon solido (para renders sin ventana).
struct BubbleCard: View {
    let activity: Activity
    let state: PetState
    var flat = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Pal.cream)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Pal.cream.opacity(0.55))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Indicator(state: state)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(width: 340)
        .background(flat ? AnyView(Pal.charcoal) : AnyView(ZStack { GlassBackground(); Pal.charcoal.opacity(0.82) }))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(flat ? 0 : 0.35), radius: 8, y: 2)
    }

    private var subtitle: String {
        let o = activity.origin == "desktop" || activity.origin == "terminal" ? activity.origin : ""
        switch (activity.subtitle.isEmpty, o.isEmpty) {
        case (true, true): return ""
        case (true, false): return o
        case (false, true): return activity.subtitle
        case (false, false): return "\(activity.subtitle)  \(o)"
        }
    }
}

struct Indicator: View {
    let state: PetState
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                switch state {
                case .starting, .thinking, .tool:
                    Circle().trim(from: 0, to: 0.28)
                        .stroke(Pal.body, style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
                        .rotationEffect(.degrees(t * 360 / 0.9))
                case .waiting:
                    Circle().fill(Pal.body).frame(width: 9, height: 9)
                        .opacity(0.45 + 0.55 * (0.5 + 0.5 * sin(t * 5)))
                case .done:
                    Path { p in p.move(to: CGPoint(x: 2, y: 9)); p.addLine(to: CGPoint(x: 7, y: 14)); p.addLine(to: CGPoint(x: 16, y: 3)) }
                        .stroke(Pal.cream, style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
                case .error:
                    Path { p in p.move(to: CGPoint(x: 3, y: 3)); p.addLine(to: CGPoint(x: 15, y: 15)); p.move(to: CGPoint(x: 15, y: 3)); p.addLine(to: CGPoint(x: 3, y: 15)) }
                        .stroke(Pal.dark, style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
                case .idle:
                    EmptyView()
                }
            }
            .frame(width: state == .done || state == .error ? 18 : 18, height: 18)
        }
        .frame(width: 22, height: 22)
    }
}
