import SwiftUI

enum CrawlerTone { case pending, ok, warn, broken }

struct WebCrawlerTarget: Identifiable {
    let id: Int
    let rect: CGRect
    let visited: Bool
    let current: Bool
    var tone: CrawlerTone = .pending
    var badge: String? = nil
}

struct WebCrawlerScene {
    let agent: WebScoutAgent
    let targets: [WebCrawlerTarget]
    let from: CGPoint
    let to: CGPoint
    let contacts: [CGPoint]
    let step: Int
    let total: Int
    let startedAt: Date
    let duration: TimeInterval
    let reduceMotion: Bool
    var ok = 0
    var warn = 0
    var broken = 0
    var verifying = false
}

struct WebCrawlerOverlay: View {
    let scene: WebCrawlerScene

    private var primary: Color { scene.agent == .codex ? Color(hex: 0x74E8FF) : Pal.body }
    private var secondary: Color { scene.agent == .codex ? Color(hex: 0x8D7CFF) : Pal.dark }

    private func tint(for target: WebCrawlerTarget) -> Color {
        if target.current { return secondary }
        switch target.tone {
        case .pending: return primary
        case .ok: return Color(hex: 0x6FCF97)
        case .warn: return Color(hex: 0xF2C94C)
        case .broken: return Color(hex: 0xEB5757)
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("claudwler · \(scene.step)/\(scene.total)\(scene.verifying ? " · verificando" : "")")
                .font(.caption.monospaced().bold())
            HStack(spacing: 10) {
                counter(Color(hex: 0x6FCF97), "bien", scene.ok)
                counter(Color(hex: 0xF2C94C), "avisos", scene.warn)
                counter(Color(hex: 0xEB5757), "rotos", scene.broken)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(Pal.cream)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Pal.charcoal, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(primary.opacity(0.75)) }
    }

    private func counter(_ color: Color, _ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value) \(label)")
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: scene.reduceMotion ? 1 : 1.0 / 30, paused: scene.reduceMotion)) { timeline in
            let raw = scene.reduceMotion ? 0 : timeline.date.timeIntervalSince(scene.startedAt) / scene.duration
            let progress = min(1, max(0, raw))
            let eased = progress * progress * (3 - 2 * progress)
            let position = CGPoint(x: scene.from.x + (scene.to.x - scene.from.x) * eased,
                                   y: scene.from.y + (scene.to.y - scene.from.y) * eased)
            ZStack(alignment: .topLeading) {
                ForEach(scene.targets) { target in
                    let tint = tint(for: target)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(target.visited ? (target.tone == .pending ? 0.16 : 0.2) : 0.035))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(tint, style: StrokeStyle(lineWidth: target.current || target.tone == .broken ? 2 : 1,
                                                                 dash: target.visited ? [] : [4, 3]))
                        }
                        .frame(width: target.rect.width + 5, height: target.rect.height + 5)
                        .position(x: target.rect.midX, y: target.rect.midY)
                    if let badge = target.badge, target.visited {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(target.tone == .warn ? Pal.charcoal : .white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tint, in: .rect(cornerRadius: 3))
                            .position(x: target.rect.minX + 6 + CGFloat(badge.count) * 3.2, y: target.rect.minY - 7)
                    }
                }
                CrawlerSpider(position: position, contacts: scene.contacts, primary: primary, secondary: secondary)
                hud
                    .position(x: min(max(position.x, 150), 300), y: max(26, position.y - 56))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct CrawlerSpider: View {
    let position: CGPoint
    let contacts: [CGPoint]
    let primary: Color
    let secondary: Color

    var body: some View {
        Canvas { context, _ in
            for (index, contact) in contacts.prefix(8).enumerated() {
                let angle = atan2(contact.y - position.y, contact.x - position.x)
                let joint = CGPoint(x: position.x + cos(angle) * 28 + cos(angle + .pi / 2) * (index.isMultiple(of: 2) ? 11 : -11),
                                    y: position.y + sin(angle) * 28 + sin(angle + .pi / 2) * (index.isMultiple(of: 2) ? 11 : -11))
                var leg = Path()
                leg.move(to: position)
                leg.addLine(to: joint)
                leg.addLine(to: contact)
                context.stroke(leg, with: .color(index.isMultiple(of: 2) ? primary : secondary),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: contact.x - 2.5, y: contact.y - 2.5, width: 5, height: 5)),
                             with: .color(index.isMultiple(of: 2) ? secondary : primary))
            }

            // Mascota de Claude Code: bloque ancho con orejas, ojos y cuatro patas.
            let px: CGFloat = 4
            func block(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
                context.fill(Path(CGRect(x: position.x + CGFloat(x) * px, y: position.y + CGFloat(y) * px,
                                         width: CGFloat(w) * px, height: CGFloat(h) * px)), with: .color(color))
            }
            block(-6, -3, 12, 6, Pal.body)
            block(-8, -1, 2, 2, Pal.body)
            block(6, -1, 2, 2, Pal.body)
            block(-6, -3, 12, 1, Pal.light)
            block(-6, 2, 12, 1, Pal.dark)
            for x in [-5, -2, 1, 4] { block(x, 3, 1, 2, Pal.dark) }
            block(-4, -1, 1, 2, Pal.charcoal)
            block(3, -1, 1, 2, Pal.charcoal)
        }
    }
}
