import SwiftUI

/// Memoria local de la mascota, reconstruida desde cero: un núcleo que respira con la actividad y
/// orbita una mota por recuerdo reciente, un pulso en vivo y una única barra de reparto — nada de
/// cajas con números sueltos. Todo es determinista y no representa datos biométricos reales.
struct PetMemoryView: View {
    @ObservedObject var store: PetStore
    @State private var events: [PetMemoryEvent] = []

    private var sessions: Int { events.filter { $0.kind == .session }.count }
    private var tools: Int { events.filter { $0.kind == .tool }.count }
    private var incidents: Int { events.filter { $0.kind == .error }.count }
    private var namedEvents: Int { events.filter { !$0.project.isEmpty }.count }
    private var recall: Double { events.isEmpty ? 0 : Double(namedEvents) / Double(events.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .center, spacing: 16) {
                MemoryCore(recallPercent: Int((recall * 100).rounded()), pulses: min(events.count, 16), reduceMotion: store.reduceMotion)
                    .frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 7) {
                    statRow("recuerdos", "\(events.count)", DashboardTheme.ember)
                    statRow("sesiones", "\(sessions)", DashboardTheme.signal)
                    statRow("racha", store.weeklyRecap.streak == 1 ? "1 día" : "\(store.weeklyRecap.streak) días", DashboardTheme.amber)
                    MemoryPulseLine(level: events.count, reduceMotion: store.reduceMotion)
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MemoryBreakdown(sessions: sessions, tools: tools, incidents: incidents)
        }
        .onAppear(perform: reload)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("memoria local: \(events.count) recuerdos, recall \(Int((recall * 100).rounded()))%")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 12, weight: .semibold)).foregroundStyle(DashboardTheme.ember)
            Text("memoria").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            Text("registro local").dashboardLabel()
            Spacer(minLength: 0)
            Button("actualizar", systemImage: "arrow.clockwise", action: reload)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.ember)
                .buttonStyle(.plain)
                .accessibilityLabel("actualizar recuerdos")
        }
    }

    private func statRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label).dashboardLabel()
            Spacer(minLength: 6)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
                .contentTransition(.numericText())
        }
    }

    private func reload() {
        withAnimation(store.reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
            events = PetMemoryStore.shared.snapshot()
        }
    }
}

/// Núcleo circular: el anillo marca el recall, el centro respira despacio y las motas orbitan,
/// una por cada recuerdo reciente (hasta 16, para que no sature el ojo).
private struct MemoryCore: View {
    let recallPercent: Int
    let pulses: Int
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { gc, size in draw(&gc, size: size, t: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { gc, size in draw(&gc, size: size, t: timeline.date.timeIntervalSinceReferenceDate) }
                }
            }
        }
        .overlay(centerLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("recall \(recallPercent) por ciento")
    }

    private var centerLabel: some View {
        VStack(spacing: 1) {
            Text("\(recallPercent)%").font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            Text("recall").dashboardLabel()
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 5

        gc.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(DashboardTheme.line), lineWidth: 2)

        if recallPercent > 0 {
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(recallPercent) / 100), clockwise: false)
            gc.stroke(ring, with: .linearGradient(Gradient(colors: [DashboardTheme.amber, DashboardTheme.ember]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        let breathe = 1 + (reduceMotion ? 0 : 0.07 * sin(t * 1.3))
        let coreRadius = radius * 0.4 * breathe
        gc.fill(Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
                with: .radialGradient(Gradient(colors: [DashboardTheme.ember.opacity(0.5), .clear]), center: center, startRadius: 0, endRadius: coreRadius))

        guard pulses > 0 else { return }
        for i in 0..<pulses {
            let base = Double(i) / Double(pulses) * 2 * .pi
            let speed = 0.1 + 0.05 * Double(i % 3)
            let angle = base + (reduceMotion ? 0 : t * speed)
            let orbit = radius * (0.58 + 0.2 * Double(i % 3))
            let x = center.x + CGFloat(cos(angle)) * orbit
            let y = center.y + CGFloat(sin(angle)) * orbit
            let tint = i % 3 == 0 ? DashboardTheme.ember : (i % 3 == 1 ? DashboardTheme.signal : DashboardTheme.amber)
            let r: CGFloat = i % 4 == 0 ? 2.1 : 1.3
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(tint.opacity(0.85)))
        }
    }
}

/// Trazo de pulso que se mueve solo: cuanta más memoria hay, más alto late. Sustituye a los tres
/// "corte" que antes eran cajas casi vacías.
private struct MemoryPulseLine: View {
    let level: Int
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { gc, size in draw(&gc, size: size, t: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { gc, size in draw(&gc, size: size, t: timeline.date.timeIntervalSinceReferenceDate) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, t: Double) {
        let amp = min(1, Double(level) / 40) * Double(size.height / 2 - 2) + 1
        var path = Path()
        var x: CGFloat = 0
        var started = false
        while x <= size.width {
            let phase = Double(x) * 0.09 + t * 2.2
            let y = size.height / 2 - CGFloat(sin(phase) * amp * 0.5 + sin(phase * 2.3) * amp * 0.22)
            if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
            x += 3
        }
        gc.stroke(path, with: .linearGradient(Gradient(colors: [DashboardTheme.ember.opacity(0.1), DashboardTheme.ember, DashboardTheme.signal.opacity(0.7)]),
                   startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}

/// Reparto de hitos, herramientas e incidencias en una sola barra de color con su leyenda debajo:
/// una línea en vez de tres cajas sueltas con "N registrados".
private struct MemoryBreakdown: View {
    let sessions: Int
    let tools: Int
    let incidents: Int

    private var parts: [(count: Int, tint: Color, title: String)] {
        [(sessions, DashboardTheme.ember, "hitos"), (tools, DashboardTheme.signal, "herramientas"), (incidents, DashboardTheme.amber, "incidencias")]
    }
    private var total: Int { max(1, sessions + tools + incidents) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.count > 0 {
                            Capsule().fill(part.tint).frame(width: max(3, geo.size.width * CGFloat(part.count) / CGFloat(total)))
                        }
                    }
                    if sessions + tools + incidents == 0 { Capsule().fill(DashboardTheme.line).frame(width: geo.size.width) }
                }
            }
            .frame(height: 6)
            HStack(spacing: 14) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in legend(part.title, part.count, part.tint) }
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ title: String, _ count: Int, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(title).dashboardLabel()
            Text("\(count)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
        }
    }
}
