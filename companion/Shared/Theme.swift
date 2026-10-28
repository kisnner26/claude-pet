import SwiftUI
import VistoCore

/// Identidad de Visto: carbón, un azul para la acción, rojo solo para negar, y el dúo naranja-azul de claude pet como firma.
enum VT {
    static let ink = Color(red: 0.07, green: 0.075, blue: 0.095)
    static let ink2 = Color(red: 0.13, green: 0.135, blue: 0.16)
    static let blue = Color(red: 0.16, green: 0.40, blue: 0.93)
    static let red = Color(red: 0.90, green: 0.13, blue: 0.25)
    static let green = Color(red: 0.20, green: 0.80, blue: 0.36)
    static let amber = Color(red: 0.94, green: 0.64, blue: 0.29)
    static let claude = Color(red: 0.878, green: 0.51, blue: 0.31)
    static let codex = Color(red: 0.32, green: 0.44, blue: 0.91)
    static let mute = Color.white.opacity(0.55)
    static let duo = LinearGradient(colors: [claude, codex], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func riskColor(_ risk: String) -> Color { risk == "alto" ? red : risk == "medio" ? amber : green }
    static func barColor(used: Double) -> Color { used >= 95 ? red : used >= 80 ? amber : blue }
}

struct VTBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [VT.ink, VT.ink2], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [VT.claude.opacity(0.16), .clear], center: .topLeading, startRadius: 10, endRadius: 360)
            RadialGradient(colors: [VT.codex.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

/// Dos barras finas con lo que queda del límite de 5 horas y del semanal.
struct PlanBars: View {
    let plan: PlanSnapshot
    var compact = false

    private func bar(_ title: String, _ w: VistoCore.PlanWindow) -> some View {
        let used = w.effectivePercent(), left = w.remaining()
        return HStack(spacing: 8) {
            Text(title).font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced)).foregroundStyle(VT.mute).frame(width: compact ? 22 : 26, alignment: .leading)
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(VT.barColor(used: used)).frame(width: max(4, p.size.width * CGFloat(left) / 100))
                }
            }.frame(height: compact ? 4 : 5)
            Text("\(left)%").font(.system(size: compact ? 10 : 12, weight: .semibold, design: .monospaced)).foregroundStyle(VT.barColor(used: used)).frame(width: 38, alignment: .trailing)
        }
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            if let f = plan.five { bar("5h", f) }
            if let w = plan.week { bar("7d", w) }
        }
    }
}

struct RiskChip: View {
    let risk: String
    var body: some View {
        Text("riesgo \(risk)").font(.system(size: 9, weight: .semibold, design: .monospaced)).textCase(.uppercase).tracking(0.8)
            .foregroundStyle(VT.riskColor(risk)).padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(VT.riskColor(risk).opacity(0.16)))
    }
}

enum VTFormat {
    static func state(_ raw: String) -> String {
        switch raw {
        case "starting": return "Iniciando"; case "thinking": return "Pensando"; case "tool": return "Ejecutando"
        case "waiting": return "Espera tu respuesta"; case "done": return "Listo"; case "error": return "Error"; default: return "En reposo"
        }
    }
    static func stateColor(_ raw: String) -> Color {
        switch raw {
        case "thinking", "starting": return VT.codex; case "tool": return VT.claude; case "waiting": return VT.amber
        case "done": return VT.green; case "error": return VT.red; default: return Color.white.opacity(0.35)
        }
    }
    static func agentName(_ a: String) -> String { a == "codex" ? "Codex" : "Claude" }
    static func agentColor(_ a: String) -> Color { a == "codex" ? VT.codex : VT.claude }
    static func duration(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600) h \(seconds % 3600 / 60) m" }
        if seconds >= 60 { return "\(seconds / 60) m \(seconds % 60) s" }
        return "\(max(0, seconds)) s"
    }
}

struct AgentRow: View {
    let agent: AgentInfo
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 8) {
                Circle().fill(VTFormat.agentColor(agent.agent)).frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                Text(VTFormat.agentName(agent.agent)).font(.system(size: compact ? 13 : 17, weight: .heavy, design: .rounded))
                Spacer(minLength: 4)
                Text(VTFormat.state(agent.state)).font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced)).foregroundStyle(VTFormat.stateColor(agent.state))
            }
            if !agent.project.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(agent.project) · \(VTFormat.duration(Int(ctx.date.timeIntervalSince(agent.since))))").font(.system(size: compact ? 10 : 12, design: .monospaced)).foregroundStyle(VT.mute).lineLimit(1)
                }
            }
            if let c = agent.contextRemaining {
                HStack(spacing: 6) {
                    Text("ctx").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(VT.mute)
                    GeometryReader { p in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(c <= 15 ? VT.red : c <= 35 ? VT.amber : VT.blue).frame(width: max(3, p.size.width * CGFloat(c) / 100))
                        }
                    }.frame(height: 3)
                    Text("\(c)%").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(VT.mute)
                }
            }
        }
    }
}
