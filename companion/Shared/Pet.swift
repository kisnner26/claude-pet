import SwiftUI
import VistoCore

/// Arte en píxeles de las mascotas de claude pet: el mismo bloque naranja de Claude y la nube azul de Codex.
struct PixelArt {
    let rows: [String]
    let palette: [Character: Color]
    var width: Int { rows.first?.count ?? 0 }
    var height: Int { rows.count }

    private static func c(_ hex: UInt32) -> Color { Color(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }

    static let claude = PixelArt(rows: [
        "................", "................", "................", "................",
        "..cccccccccccc..", "..aaaaaaaaaaab..", "..aadaaaaaadab..", "baaaadaaaadaabab",
        "baaaaadaadaaabab", "baaaadaaaadaabab", "baaadaaaaaadabab", "..aaaaaaaaaaab..",
        "..bbbbbbbbbbbb..", "...aa.aa.aa.aa..", "...aa.aa.aa.aa..", "...bb.bb.bb.bb.."],
        palette: ["a": c(0xE0824F), "b": c(0xB9603A), "c": c(0xEC9A6E), "d": c(0x1C1B1A)])

    static let codex = PixelArt(rows: [
        ".....eeeeeeee.....", "..ejeeffffffeeee..", ".ejjffffffffffffe.", ".ejffkkkkkkkkfffe.",
        "ejffkllllllllkfffe", "ejffklgllllllkfffe", "efffkllglllllkfffe", "efffklgllggglkfffe",
        "efffkllllllllkfffe", ".efffkkkkkkkkfffe.", "..eiiiiiiiiiiiie..", "...eeeeeeeeeeee...",
        "..eeeffffffffeee..", "..effffghhhffffe..", "..eiiffhghhffiie..", "..eeeifghggfieee..",
        ".....efieeife.....", ".....efe..efe.....", ".....eie..eie.....", ".....eee..eee.....", ".................."],
        palette: ["e": c(0x223496), "f": c(0x5270E8), "g": c(0x96EBFF), "h": c(0x6E8CF5), "i": c(0x3E5ACE), "j": c(0x7E98FF), "k": c(0x2C346E), "l": c(0x161B40)])
}

struct PixelSprite: View {
    let art: PixelArt
    var blink = false

    var body: some View {
        Canvas { ctx, size in
            let cell = min(size.width / CGFloat(art.width), size.height / CGFloat(art.height))
            let ox = (size.width - cell * CGFloat(art.width)) / 2, oy = (size.height - cell * CGFloat(art.height)) / 2
            for (y, row) in art.rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard var color = art.palette[ch] else { continue }
                    if blink, ch == "d" { color = art.palette["a"] ?? color }
                    ctx.fill(Path(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell + 0.4, height: cell + 0.4)), with: .color(color))
                }
            }
        }
    }
}

/// Cómo se mueve la mascota según lo que hace el agente.
enum PetMotion {
    struct Pose { var dx: CGFloat = 0; var dy: CGFloat = 0; var sx: CGFloat = 1; var sy: CGFloat = 1; var tilt: Double = 0 }

    static func pose(_ state: String, _ t: Double) -> Pose {
        switch state {
        case "thinking", "starting": return Pose(dy: CGFloat(sin(t * 3.2)) * 3, tilt: sin(t * 1.6) * 3)
        case "tool": return Pose(dx: CGFloat(sin(t * 22)) * 1.4, dy: CGFloat(abs(sin(t * 11))) * -2.5)
        case "waiting": let p = (sin(t * 5) + 1) / 2; return Pose(sx: 1 + 0.04 * CGFloat(p), sy: 1 + 0.06 * CGFloat(p), tilt: sin(t * 7) * 6)
        case "done": let j = abs(sin(t * 4.2)); return Pose(dy: CGFloat(j) * -14, sx: 1 - 0.05 * CGFloat(j), sy: 1 + 0.07 * CGFloat(j))
        case "error": return Pose(dx: CGFloat(sin(t * 40)) * 3, tilt: sin(t * 40) * 4)
        default: let b = (sin(t * 1.5) + 1) / 2; return Pose(sx: 1 - 0.012 * CGFloat(b), sy: 1 + 0.03 * CGFloat(b))
        }
    }

    static func blink(_ t: Double) -> Bool { t.truncatingRemainder(dividingBy: 4.2) < 0.16 }
}

/// Línea de pulso: plana en reposo, con latidos cuando el agente trabaja. Es la «vida» del agente de un vistazo.
struct HeartbeatLine: View {
    let state: String
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let busy = ["starting", "thinking", "tool", "waiting", "error"].contains(state)
                let amp: CGFloat = state == "tool" ? 0.45 : state == "error" ? 0.5 : busy ? 0.3 : 0.04
                let speed = state == "tool" ? 5.0 : 2.4
                var path = Path()
                let n = 90
                for i in 0...n {
                    let x = size.width * CGFloat(i) / CGFloat(n)
                    let u = Double(i) / Double(n) * 3 - t * speed * 0.3
                    let frac = u - floor(u)
                    var y = 0.0
                    if frac > 0.40 && frac < 0.46 { y = -1 } else if frac >= 0.46 && frac < 0.52 { y = 1.5 } else if frac >= 0.52 && frac < 0.58 { y = -0.4 }
                    let p = CGPoint(x: x, y: size.height / 2 + CGFloat(y) * size.height * amp)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                g.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color, color.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// La mascota en el centro de tres anillos: lo que queda del límite de 5 horas, del semanal y del contexto.
struct PetHero: View {
    let agent: AgentInfo?
    let plan: PlanSnapshot?
    var size: CGFloat = 220
    /// Inclinación del dispositivo (-1...1): mueve cada capa a distinta profundidad, como un diorama.
    var tilt: CGSize = .zero
    /// Pantalla siempre encendida del reloj: la mascota se queda quieta y tenue para gastar poco.
    @Environment(\.isLuminanceReduced) private var dim

    private func ring(_ remaining: Int?, _ radius: CGFloat, _ width: CGFloat, _ base: Color) -> some View {
        let left = Double(remaining ?? 0) / 100
        let color: Color = (remaining ?? 100) <= 5 ? VT.red : (remaining ?? 100) <= 20 ? VT.amber : base
        return ZStack {
            Circle().stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: width, lineCap: .round)).frame(width: radius * 2, height: radius * 2)
            if remaining != nil {
                Circle().trim(from: 0, to: max(0.012, left)).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2).rotationEffect(.degrees(-90)).shadow(color: color.opacity(0.5), radius: 4)
            }
        }
    }

    var body: some View {
        let state = agent?.state ?? "idle"
        let art = agent?.agent == "codex" ? PixelArt.codex : PixelArt.claude
        let tint = VTFormat.stateColor(state)
        ZStack {
            Circle().fill(RadialGradient(colors: [tint.opacity(state == "idle" ? 0.10 : 0.30), .clear], center: .center, startRadius: 4, endRadius: size * 0.5))
                .offset(x: -tilt.width * size * 0.03, y: -tilt.height * size * 0.03)
            ring(plan?.five?.remaining(), size * 0.47, size * 0.045, VT.blue).offset(x: tilt.width * size * 0.012, y: tilt.height * size * 0.012)
            ring(plan?.week?.remaining(), size * 0.40, size * 0.035, VT.codex.opacity(0.8)).offset(x: tilt.width * size * 0.024, y: tilt.height * size * 0.024)
            ring(agent?.contextRemaining, size * 0.34, size * 0.028, VT.claude).offset(x: tilt.width * size * 0.036, y: tilt.height * size * 0.036)
            TimelineView(.animation(minimumInterval: dim ? 5 : 1.0 / 30)) { ctx in
                let t = dim ? 0 : ctx.date.timeIntervalSinceReferenceDate
                let pose = PetMotion.pose(dim ? "idle" : state, t)
                ZStack {
                    PixelSprite(art: art, blink: agent?.agent != "codex" && PetMotion.blink(t) && state == "idle")
                        .frame(width: size * 0.40, height: size * 0.40)
                        .scaleEffect(x: pose.sx, y: pose.sy).rotationEffect(.degrees(pose.tilt)).offset(x: pose.dx + tilt.width * size * 0.07, y: pose.dy + tilt.height * size * 0.07)
                    if !dim { overlay(state, t) }
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(dim ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(agent.map { "\(VTFormat.agentName($0.agent)): \(VTFormat.state($0.state))" } ?? "Sin agentes activos")
    }

    @ViewBuilder private func overlay(_ state: String, _ t: Double) -> some View {
        let r = size * 0.22
        switch state {
        case "thinking", "starting":
            HStack(spacing: 4) { ForEach(0..<3, id: \.self) { i in Circle().fill(.white).frame(width: size * 0.028, height: size * 0.028).opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.8))) } }.offset(y: -r - 10)
        case "waiting":
            Text("!").font(.system(size: size * 0.16, weight: .black, design: .rounded)).foregroundStyle(VT.amber).offset(x: r, y: -r).opacity(0.6 + 0.4 * sin(t * 6))
        case "done":
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * .pi * 2 + t, d = size * (0.18 + 0.10 * (sin(t * 2 + Double(i)) + 1) / 2)
                Rectangle().fill([VT.claude, VT.codex, VT.green, VT.amber][i % 4]).frame(width: 4, height: 4).offset(x: CGFloat(cos(a)) * d, y: CGFloat(sin(a)) * d - 6)
            }
        case "error":
            Image(systemName: "xmark").font(.system(size: size * 0.10, weight: .black)).foregroundStyle(VT.red).offset(x: r, y: -r)
        case "tool":
            ForEach(0..<4, id: \.self) { i in
                let a = t * 3 + Double(i) * 1.57
                Rectangle().fill(VT.claude.opacity(0.9)).frame(width: 3, height: 3).offset(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a * 1.3)) * r * 0.8)
            }
        default: EmptyView()
        }
    }
}
