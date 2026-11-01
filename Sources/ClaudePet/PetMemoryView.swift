import SwiftUI

/// Cuántos recuerdos hay en cada intervalo y de qué tipo: la base del gráfico de actividad.
enum MemoryRange: String, CaseIterable, Identifiable {
    case day = "24 h", week = "7 días"
    var id: String { rawValue }
    var seconds: TimeInterval { self == .day ? 86_400 : 7 * 86_400 }
    var bucketCount: Int { self == .day ? 24 : 7 }
    var bucketSeconds: TimeInterval { seconds / Double(bucketCount) }
}

struct MemoryBucket: Equatable {
    var counts: [PetMemoryEvent.Kind: Int] = [:]
    var total: Int { counts.values.reduce(0, +) }
}

enum MemoryStats {
    /// Eventos de la ventana [now - rango, now], del mas viejo al mas nuevo cubierto por `buckets`.
    static func window(_ events: [PetMemoryEvent], range: MemoryRange, now: Date) -> [PetMemoryEvent] {
        let start = now.addingTimeInterval(-range.seconds)
        return events.filter { $0.at >= start && $0.at <= now.addingTimeInterval(60) }
    }

    /// El ultimo cubo termina en `now`; el primero queda a `rango` de distancia.
    static func buckets(_ events: [PetMemoryEvent], range: MemoryRange, now: Date) -> [MemoryBucket] {
        var out = Array(repeating: MemoryBucket(), count: range.bucketCount)
        let start = now.addingTimeInterval(-range.seconds)
        for e in events where e.at >= start {
            let index = min(range.bucketCount - 1, max(0, Int(e.at.timeIntervalSince(start) / range.bucketSeconds)))
            out[index].counts[e.kind, default: 0] += 1
        }
        return out
    }

    static func share(_ events: [PetMemoryEvent], agent: String) -> Int { events.filter { $0.agent == agent }.count }

    static func topProject(_ events: [PetMemoryEvent]) -> (name: String, count: Int)? {
        var tally: [String: Int] = [:]
        for e in events where !e.project.isEmpty { tally[e.project, default: 0] += 1 }
        return tally.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }.map { ($0.key, $0.value) }
    }

    /// Parte de los recuerdos sin incidencias, de 0 a 1.
    static func successRate(_ events: [PetMemoryEvent]) -> Double {
        events.isEmpty ? 0 : Double(events.filter { $0.kind != .error }.count) / Double(events.count)
    }
}

extension PetMemoryEvent.Kind {
    var tint: Color {
        switch self {
        case .session: return DashboardTheme.ember
        case .tool: return DashboardTheme.signal
        case .permission: return DashboardTheme.cream.opacity(0.6)
        case .error: return DashboardTheme.amber
        }
    }
    var plural: String {
        switch self {
        case .session: return "sesiones"
        case .tool: return "herramientas"
        case .permission: return "permisos"
        case .error: return "incidencias"
        }
    }
}

/// Memoria local de la mascota: un medidor con la parte sin fallos, tres cifras, el gráfico de actividad
/// del periodo elegido, el reparto por tipo y por agente. Todo sale del registro local y no guarda contenido.
enum MemoryTab: String, CaseIterable, Identifiable { case activity = "actividad", brain = "cerebro", character = "carácter"; var id: String { rawValue } }

struct PetMemoryView: View {
    @ObservedObject var store: PetStore
    @State private var events: [PetMemoryEvent] = []
    @State private var range: MemoryRange = .day
    @State private var tab: MemoryTab

    init(store: PetStore, initialTab: MemoryTab = .activity) {
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    private var now: Date { Date() }
    private var scoped: [PetMemoryEvent] { MemoryStats.window(events, range: range, now: now) }
    private func count(_ k: PetMemoryEvent.Kind) -> Int { scoped.filter { $0.kind == k }.count }
    private var recall: Double { MemoryStats.successRate(scoped) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if tab == .brain {
                BrainPanel(project: store.terminalProject)
            } else if tab == .character {
                PersonalityPanel(events: events)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    MemoryHealth(percent: Int((recall * 100).rounded()), incidents: count(.error), total: scoped.count, reduceMotion: store.reduceMotion)
                        .frame(width: 128, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        statRow("recuerdos", "\(scoped.count)", "en \(range.rawValue)", DashboardTheme.cream)
                        statRow("sesiones", "\(count(.session))", "tareas largas", DashboardTheme.ember)
                        statRow("racha", store.weeklyRecap.streak == 1 ? "1 día" : "\(store.weeklyRecap.streak) días", "con actividad", DashboardTheme.amber)
                    }
                    .frame(width: 150, alignment: .leading)
                    MemoryActivityChart(buckets: MemoryStats.buckets(scoped, range: range, now: now), range: range, now: now)
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                }
                MemoryBreakdown(parts: PetMemoryEvent.Kind.allCases.map { ($0, count($0)) })
                MemoryAgents(claude: MemoryStats.share(scoped, agent: "claude"), codex: MemoryStats.share(scoped, agent: "codex"), top: MemoryStats.topProject(scoped))
            }
        }
        .onAppear(perform: reload)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("memoria local: \(scoped.count) recuerdos en \(range.rawValue), \(Int((recall * 100).rounded()))% sin fallos")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 12, weight: .semibold)).foregroundStyle(DashboardTheme.ember)
            Text("memoria").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            Text("registro local").dashboardLabel()
            Spacer(minLength: 0)
            pill(MemoryTab.allCases, selection: $tab) { $0.rawValue }
            if tab == .activity { pill(MemoryRange.allCases, selection: $range) { $0.rawValue } }
            Button("actualizar", systemImage: "arrow.clockwise", action: reload)
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DashboardTheme.ember)
                .buttonStyle(.plain)
                .help("actualizar recuerdos")
                .accessibilityLabel("actualizar recuerdos")
        }
    }

    private func pill<T: Identifiable & Equatable>(_ items: [T], selection: Binding<T>, title: @escaping (T) -> String) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { withAnimation(store.reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { selection.wrappedValue = item } } label: {
                    Text(title(item)).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selection.wrappedValue == item ? Color.black : DashboardTheme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(selection.wrappedValue == item ? DashboardTheme.ember : Color.clear))
                }
                .buttonStyle(.plain).accessibilityLabel(title(item))
            }
        }
        .padding(2).background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func statRow(_ label: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).dashboardLabel()
                Text(caption).font(.system(size: 8.5)).foregroundStyle(DashboardTheme.muted.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
                .contentTransition(.numericText())
        }
    }

    private func reload() {
        withAnimation(store.reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
            events = PetMemoryStore.shared.snapshot()
        }
    }
}

/// Medidor de salud: el porcentaje sin fallos en grande y una regleta de 24 marcas que se llena de izquierda a derecha.
/// Las marcas llenas pasan de ámbar a verde señal; las que faltan quedan como riel apagado.
private struct MemoryHealth: View {
    let percent: Int
    let incidents: Int
    let total: Int
    let reduceMotion: Bool
    @State private var shown = false
    private let ticks = 24

    private var filled: Int { total == 0 ? 0 : Int((Double(percent) / 100 * Double(ticks)).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("salud").dashboardLabel()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(total == 0 ? "--" : "\(percent)").font(.system(size: 38, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
                    .contentTransition(.numericText())
                if total > 0 { Text("%").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(DashboardTheme.muted) }
            }
            .minimumScaleFactor(0.7).lineLimit(1)
            HStack(spacing: 2) {
                ForEach(0..<ticks, id: \.self) { i in
                    let on = shown && i < filled
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(on ? tint(i) : Color.white.opacity(0.09))
                        .frame(height: on ? 14 : 8)
                        .frame(maxHeight: 14, alignment: .bottom)
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75).delay(Double(i) * 0.012), value: shown)
                }
            }
            .frame(height: 14)
            Text(total == 0 ? "sin datos todavía" : (incidents == 0 ? "\(total) recuerdos, sin fallos" : "\(incidents) \(incidents == 1 ? "fallo" : "fallos") de \(total)"))
                .font(.system(size: 9.5)).foregroundStyle(DashboardTheme.muted).lineLimit(1)
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total == 0 ? "sin datos" : "salud \(percent) por ciento, \(incidents) fallos de \(total) recuerdos")
    }

    private func tint(_ i: Int) -> Color {
        let t = Double(i) / Double(ticks - 1)
        return t < 0.5 ? DashboardTheme.amber : (t < 0.8 ? DashboardTheme.ember : DashboardTheme.signal)
    }
}

/// Barras apiladas por intervalo: cada color es un tipo de recuerdo. Abajo, el eje con horas o días.
private struct MemoryActivityChart: View {
    let buckets: [MemoryBucket]
    let range: MemoryRange
    let now: Date

    private var peak: Int { max(1, buckets.map(\.total).max() ?? 1) }
    private var empty: Bool { buckets.allSatisfy { $0.total == 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("actividad").dashboardLabel()
                Spacer(minLength: 0)
                if !empty { Text("pico \(peak)").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted) }
            }
            ZStack {
                Canvas { gc, size in draw(&gc, size: size) }
                if empty {
                    Text("sin actividad en este periodo").font(.system(size: 10)).foregroundStyle(DashboardTheme.muted.opacity(0.8))
                }
            }
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                    if i > 0 { Spacer(minLength: 0) }
                    Text(l).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(DashboardTheme.muted.opacity(0.7))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("actividad de \(range.rawValue): \(buckets.map(\.total).reduce(0, +)) recuerdos, pico \(peak)")
    }

    private var labels: [String] {
        range == .day ? ["hace 24 h", "12 h", "ahora"] : ["hace 7 d", "3 d", "hoy"]
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize) {
        let n = buckets.count
        let gap: CGFloat = range == .day ? 2 : 6
        let w = max(2, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
        for frac in [0.5, 1.0] {
            let y = size.height - size.height * CGFloat(frac)
            gc.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                      with: .color(.white.opacity(frac == 1 ? 0.0 : 0.07)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        for (i, b) in buckets.enumerated() {
            let x = CGFloat(i) * (w + gap)
            // base fina para que los intervalos vacios se vean como un riel
            gc.fill(Path(roundedRect: CGRect(x: x, y: size.height - 2, width: w, height: 2), cornerRadius: 1), with: .color(.white.opacity(0.08)))
            var y = size.height
            for kind in PetMemoryEvent.Kind.allCases {
                let c = b.counts[kind] ?? 0
                guard c > 0 else { continue }
                let h = max(2, (size.height - 2) * CGFloat(c) / CGFloat(peak))
                y -= h
                gc.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: min(2, w / 2)), with: .color(kind.tint.opacity(i == n - 1 ? 1 : 0.85)))
            }
        }
    }
}

/// Reparto por tipo en una barra y su leyenda con cifra y porcentaje.
private struct MemoryBreakdown: View {
    let parts: [(kind: PetMemoryEvent.Kind, count: Int)]
    private var total: Int { parts.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.count > 0 {
                            Capsule().fill(part.kind.tint).frame(width: max(3, (geo.size.width - 6) * CGFloat(part.count) / CGFloat(max(1, total))))
                        }
                    }
                    if total == 0 { Capsule().fill(DashboardTheme.line).frame(width: geo.size.width) }
                }
            }
            .frame(height: 6)
            HStack(spacing: 14) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in legend(part.kind, part.count) }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.map { "\($0.count) \($0.kind.plural)" }.joined(separator: ", "))
    }

    private func legend(_ kind: PetMemoryEvent.Kind, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(kind.tint).frame(width: 5, height: 5)
            Text(kind.plural).dashboardLabel()
            Text("\(count)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
            if total > 0, count > 0 { Text("\(Int((Double(count) / Double(total) * 100).rounded()))%").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted.opacity(0.7)) }
        }
    }
}

/// Quién hizo qué: reparto entre claude y codex y el proyecto con más recuerdos.
private struct MemoryAgents: View {
    let claude: Int
    let codex: Int
    let top: (name: String, count: Int)?
    private let claudeTint = Color(hex: 0xE0824F), codexTint = Color(hex: 0x5270E8)

    var body: some View {
        HStack(spacing: 10) {
            dot(claudeTint); Text("claude").dashboardLabel(); value(claude)
            GeometryReader { geo in
                let total = max(1, claude + codex)
                HStack(spacing: 2) {
                    if claude + codex == 0 { Capsule().fill(DashboardTheme.line) }
                    if claude > 0 { Capsule().fill(claudeTint).frame(width: max(3, (geo.size.width - 2) * CGFloat(claude) / CGFloat(total))) }
                    if codex > 0 { Capsule().fill(codexTint) }
                }
            }
            .frame(height: 4).frame(maxWidth: 140)
            dot(codexTint); Text("codex").dashboardLabel(); value(codex)
            Spacer(minLength: 0)
            if let top {
                Image(systemName: "folder").font(.system(size: 9)).foregroundStyle(DashboardTheme.muted)
                Text(top.name).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(DashboardTheme.ink).lineLimit(1)
                Text("\(top.count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("claude \(claude), codex \(codex)" + (top.map { ", proyecto principal \($0.name)" } ?? ""))
    }

    private func dot(_ c: Color) -> some View { Circle().fill(c).frame(width: 5, height: 5) }
    private func value(_ n: Int) -> some View { Text("\(n)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DashboardTheme.ink) }
}

extension BrainKind {
    var tint: Color {
        switch self {
        case .decision: return DashboardTheme.ember
        case .hecho: return DashboardTheme.signal
        case .cuidado: return DashboardTheme.amber
        case .pendiente: return DashboardTheme.cream.opacity(0.7)
        case .trato: return Color(hex: 0x8FB8FF)
        }
    }
}

private func brainAgentTint(_ agent: String) -> Color {
    switch agent { case "claude": return Color(hex: 0xE0824F); case "codex": return Color(hex: 0x5270E8); default: return DashboardTheme.cream.opacity(0.8) }
}

/// El cerebro compartido: cuantas notas hay y quien las dejo, y las mas recientes del proyecto actual.
private struct BrainPanel: View {
    let project: String
    @State private var notes: [BrainNote] = []
    @State private var globalCount = 0
    @State private var showGlobal = false

    private var name: String { BrainStore.clean(project: project) }
    private var scopeProject: String { showGlobal ? "global" : project }
    private var shown: [BrainNote] { showGlobal ? BrainStore.shared.notes("global") : notes }
    private func scopeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(on ? DashboardTheme.ink : DashboardTheme.muted)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(on ? Color.white.opacity(0.12) : .clear))
        }.buttonStyle(.plain)
    }
    private func count(agent: String) -> Int { notes.filter { $0.agent == agent }.count }
    private func count(kind: BrainKind) -> Int { notes.filter { $0.kind == kind }.count }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.isEmpty ? "global" : name).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(notes.count)").font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink).contentTransition(.numericText())
                    Text(notes.count == 1 ? "nota" : "notas").font(.system(size: 11)).foregroundStyle(DashboardTheme.muted)
                }
                agentBar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(BrainKind.allCases, id: \.self) { k in
                        HStack(spacing: 5) {
                            Circle().fill(k.tint).frame(width: 5, height: 5)
                            Text(k.label).dashboardLabel()
                            Spacer(minLength: 0)
                            Text("\(count(kind: k))").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
                        }
                    }
                }
                if globalCount > 0 { Text("+ \(globalCount) globales").font(.system(size: 9.5)).foregroundStyle(DashboardTheme.muted) }
            }
            .frame(width: 128, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("notas").dashboardLabel()
                    Spacer(minLength: 0)
                    if name != "global" {
                        scopeButton("proyecto", on: !showGlobal) { showGlobal = false; reload() }
                        scopeButton("global", on: showGlobal) { showGlobal = true; reload() }
                    }
                    Button { BrainEditorWindow.present(project: showGlobal ? "global" : project, note: nil) } label: {
                        Label("nueva", systemImage: "plus").labelStyle(.titleAndIcon).font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.black).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(DashboardTheme.ember))
                    }.buttonStyle(.plain).help("escribir una nota para tus agentes")
                }
                if shown.isEmpty { empty } else {
                    ForEach(shown.prefix(4)) { n in row(n) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: reload)
        .onChange(of: project) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .brainChanged)) { _ in reload() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("cerebro compartido de \(name): \(notes.count) notas")
    }

    private var agentBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if notes.isEmpty { Capsule().fill(DashboardTheme.line) }
                    ForEach(BrainStore.agents, id: \.self) { a in
                        let c = count(agent: a)
                        if c > 0 { Capsule().fill(brainAgentTint(a)).frame(width: max(3, (geo.size.width - 4) * CGFloat(c) / CGFloat(notes.count))) }
                    }
                }
            }
            .frame(height: 5)
            HStack(spacing: 8) {
                ForEach(BrainStore.agents, id: \.self) { a in
                    HStack(spacing: 3) {
                        Circle().fill(brainAgentTint(a)).frame(width: 4, height: 4)
                        Text("\(a) \(count(agent: a))").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
                    }
                }
            }
        }
    }

    private func row(_ n: BrainNote) -> some View {
        HStack(spacing: 7) {
            Text(n.kind.label).font(.system(size: 8.5, weight: .bold, design: .monospaced)).textCase(.uppercase)
                .foregroundStyle(Color.black).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(n.kind.tint)).frame(width: 66, alignment: .leading)
            Text(n.text).font(.system(size: 11.5)).foregroundStyle(DashboardTheme.ink).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Circle().fill(brainAgentTint(n.agent)).frame(width: 5, height: 5)
            Text(BrainStore.ago(n.at)).font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted).fixedSize()
            Button { BrainEditorWindow.present(project: scopeProject, note: n) } label: { Image(systemName: "pencil").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(DashboardTheme.muted).help("editar").accessibilityLabel("editar nota")
            Button { BrainStore.shared.forget(id: n.short, project: scopeProject); reload() } label: { Image(systemName: "trash").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(DashboardTheme.muted).help("olvidar").accessibilityLabel("olvidar nota")
        }
        .help("\(n.agent) · \(n.text)")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("todavía no hay notas de este proyecto").font(.system(size: 12, weight: .medium)).foregroundStyle(DashboardTheme.ink)
            Text("claude y codex las dejan al terminar algo que la próxima sesión debe saber.").font(.system(size: 10.5)).foregroundStyle(DashboardTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func reload() {
        notes = BrainStore.shared.notes(project)
        globalCount = name == "global" ? 0 : BrainStore.shared.notes("global").count
    }
}

/// Carácter de cada agente: lo que fue formando contigo. Se calcula del registro local; no hay nada inventado.
private struct PersonalityPanel: View {
    let events: [PetMemoryEvent]

    private func notes(_ agent: String) -> Int {
        BrainStore.shared.projects().reduce(0) { $0 + BrainStore.shared.notes($1.name).filter { $0.agent == agent }.count }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(["claude", "codex"], id: \.self) { agent in card(Personality.profile(agent: agent, events: events, notes: notes(agent))) }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ p: PersonalityProfile) -> some View {
        let tint = brainAgentTint(p.agent)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(p.agent).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(DashboardTheme.ink)
                Spacer(minLength: 0)
                Text(p.stage).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color.black)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(tint))
            }
            Text(p.summary).font(.system(size: 15, weight: .semibold)).foregroundStyle(DashboardTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
            VStack(spacing: 4) { ForEach(p.traits) { t in traitRow(t, tint: tint, faded: !p.formed) } }
            Text("\(p.events) recuerdos · \(p.activeDays) días activos").font(.system(size: 9, design: .monospaced)).foregroundStyle(DashboardTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.agent): \(p.summary), \(p.stage), \(p.events) recuerdos")
    }

    private func traitRow(_ t: PersonalityTrait, tint: Color, faded: Bool) -> some View {
        HStack(spacing: 6) {
            Text(t.label).dashboardLabel().frame(width: 74, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint.opacity(faded ? 0.35 : 0.95)).frame(width: max(3, geo.size.width * CGFloat(t.value)))
                }
            }
            .frame(height: 5)
            Text(t.note).font(.system(size: 8.5)).foregroundStyle(DashboardTheme.muted.opacity(0.8)).frame(width: 66, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
