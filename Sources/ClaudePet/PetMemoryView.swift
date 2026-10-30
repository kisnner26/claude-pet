import SwiftUI

/// Resonancia visual de los hitos locales. La nube se genera de forma determinista y no representa datos biométricos.
struct PetMemoryView: View {
    @ObservedObject var store: PetStore
    @State private var events: [PetMemoryEvent] = []
    @State private var tick = 0

    private var sessions: Int { events.filter { $0.kind == .session }.count }
    private var namedEvents: Int { events.filter { !$0.project.isEmpty }.count }
    private var recall: Int { events.isEmpty ? 0 : Int((Double(namedEvents) / Double(events.count) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            stats
            HStack(alignment: .top, spacing: 8) {
                resonance
                slices
            }
            labels
        }
        .onAppear(perform: reload)
        .onReceive(Timer.publish(every: store.reduceMotion ? 3 : 1, on: .main, in: .common).autoconnect()) { _ in
            if !store.reduceMotion { tick += 1 }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 12, weight: .semibold)).foregroundStyle(DashboardTheme.ember)
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

    private var stats: some View {
        LazyVGrid(columns: DashboardGrid.columns(4), spacing: DashboardGrid.gap) {
            stat("recuerdos", "\(events.count)")
            stat("sesiones", "\(sessions)")
            stat("recall", "\(recall)%")
            stat("racha", "\(store.weeklyRecap.streak)d")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).dashboardLabel()
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            Capsule().fill(DashboardTheme.accent).frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardTile(padding: 7)
    }

    private var resonance: some View {
        ZStack(alignment: .topLeading) {
            ResonanceCloud(phase: tick, reducedMotion: store.reduceMotion)
        }
        .overlay(alignment: .topLeading) { mapHeader.padding(8) }
        .overlay(alignment: .topLeading) { mapTag("primeros hitos", color: DashboardTheme.ember).padding(.top, 48).padding(.leading, 12) }
        .overlay(alignment: .bottomTrailing) { mapTag("proyectos vistos", color: DashboardTheme.signal).padding(.bottom, 18).padding(.trailing, 12) }
        .frame(height: 142)
        .frame(maxWidth: .infinity)
        .dashboardTile(padding: 0, active: !events.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("mapa de memoria con \(events.count) recuerdos locales")
    }

    private var slices: some View {
        VStack(spacing: 6) {
            ForEach([0, 1, 2], id: \.self) { index in
                VStack(alignment: .leading, spacing: 2) {
                    Text("corte 0\(index + 1)").dashboardLabel()
                    ResonanceSlice(index: index, phase: tick).frame(height: 29)
                }
                .dashboardTile(padding: 6)
            }
        }
        .frame(width: 104)
    }

    private var labels: some View {
        LazyVGrid(columns: DashboardGrid.columns(3), spacing: DashboardGrid.gap) {
            memoryLabel("hitos", count: events.filter { $0.kind == .session }.count, color: DashboardTheme.ember)
            memoryLabel("herramientas", count: events.filter { $0.kind == .tool }.count, color: DashboardTheme.signal)
            memoryLabel("incidencias", count: events.filter { $0.kind == .error }.count, color: DashboardTheme.amber)
        }
    }

    private func memoryLabel(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 2, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dashboardLabel()
                Text("\(count) registrados").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).dashboardTile(padding: 6)
    }

    private var mapHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("mapa de actividad").dashboardLabel()
            Text(events.isEmpty ? "esperando el primer hito" : "\(events.last?.at.formatted(date: .abbreviated, time: .shortened) ?? "")")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
        }
    }

    private func mapTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(DashboardTheme.black.opacity(0.84))
            .overlay(Rectangle().stroke(DashboardTheme.line, lineWidth: 0.6))
    }

    private func reload() { events = PetMemoryStore.shared.snapshot() }
}

private enum DashboardGrid {
    static let gap: CGFloat = 6
    static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: gap), count: count)
    }
}

private struct ResonanceCloud: View {
    let phase: Int
    let reducedMotion: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.52, y: size.height * 0.57)
            for point in 0..<210 {
                let angle = Double(point * 47 % 360) * .pi / 180
                let ring = Double(point % 17) / 17
                let wobble = reducedMotion ? 0 : sin(Double(phase) * 0.8 + Double(point)) * 1.8
                let x = center.x + CGFloat(cos(angle) * (ring * 76 + Double(point % 11) * 0.9))
                let y = center.y + CGFloat(sin(angle) * (ring * 45 + Double(point % 7) * 0.8) + wobble)
                let color = point % 5 == 0 ? DashboardTheme.ember : DashboardTheme.signal
                let radius = point % 9 == 0 ? 1.7 : 0.9
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color.opacity(point % 5 == 0 ? 0.9 : 0.55)))
            }
            for (from, to) in [(CGPoint(x: 15, y: 30), CGPoint(x: size.width * 0.35, y: size.height * 0.37)), (CGPoint(x: size.width - 8, y: 104), CGPoint(x: size.width * 0.67, y: size.height * 0.68))] {
                var line = Path(); line.move(to: from); line.addLine(to: to)
                context.stroke(line, with: .color(DashboardTheme.ember.opacity(0.4)), lineWidth: 0.6)
            }
        }
        .drawingGroup()
    }
}

private struct ResonanceSlice: View {
    let index: Int
    let phase: Int

    var body: some View {
        Canvas { context, size in
            let inset = CGFloat(index * 3 + 4)
            let rect = CGRect(x: inset, y: 3, width: size.width - inset * 2, height: size.height - 6)
            context.stroke(Path(ellipseIn: rect), with: .color(DashboardTheme.ember.opacity(0.45)), lineWidth: 0.8)
            for dot in 0..<14 {
                let x = rect.minX + CGFloat((dot * 17 + index * 11) % 100) / 100 * rect.width
                let y = rect.minY + CGFloat((dot * 31 + phase) % 100) / 100 * rect.height
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(DashboardTheme.signal.opacity(0.75)))
            }
        }
    }
}
