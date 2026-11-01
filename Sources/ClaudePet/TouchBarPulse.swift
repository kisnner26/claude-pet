import SwiftUI
import AppKit

/// "Pulso": lo que solo tiene sentido en una Mac con Touch Bar. Aprovecha lo que ninguna otra pantalla de la Mac ofrece:
/// una tira tactil a todo color, siempre a la vista, que se toca, se arrastra y se siente (el trackpad vibra debajo).
/// - Pulso: cada agente con su mascota y el calor de su actividad de los ultimos 48 min; arrastra el dedo por la tira y
///   la barra cuenta que paso en ese momento. Tocar a una mascota la hace saltar.
/// - Limites: contexto de cada agente y los limites de 5 h y semanal del plan, como medidores largos.
/// - Foco: el pomodoro con su cuenta atras, empezar, pausar y parar.
/// - Musica: portada, progreso que se arrastra para saltar y los controles, teñidos con el color de la cancion.
/// - Cerebro: las ultimas notas compartidas y un boton para dejar una.
/// - Cuando un agente pide permiso la barra cambia a un deslizador: hay que arrastrarlo hasta el final para permitir
///   (un toque suelto en una tira sin teclas se da sin querer; arrastrar es una decision; con riesgo alto, a fondo del todo).
/// - Cuando pregunta, las opciones son botones de la propia barra.
/// - Al terminar una tarea, el confeti cruza toda la barra.
/// La parte pura (hardware, calor, columnas, umbral del deslizador, modo) no toca AppKit y se prueba sin barra.
enum TouchBarHardware {
    /// Modelos de Mac que traen Touch Bar (MacBook Pro de 2016 a 2022 con la fila tactil).
    static let models: Set<String> = [
        "MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3",
        "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
        "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
        "MacBookPro17,1", "Mac14,7",
    ]

    static func hasTouchBar(model: String) -> Bool { models.contains(model) }

    static func currentModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// `CLAUDE_PET_TOUCHBAR=1` lo fuerza (para probar con el simulador) y `=0` lo apaga.
    static func enabled(env: [String: String] = ProcessInfo.processInfo.environment, model: String = currentModel()) -> Bool {
        switch env["CLAUDE_PET_TOUCHBAR"] {
        case "1": return true
        case "0": return false
        default: return hasTouchBar(model: model)
        }
    }
}

/// Pronostico del contexto: con las lecturas recientes calcula en cuantos minutos se llega a compactar.
enum ContextForecast {
    struct Result: Equatable {
        let minutes: Double
        let percentPerMinute: Double
        let tokensPerMinute: Int
    }
    static let window: TimeInterval = 30 * 60
    static let minSpan: TimeInterval = 120
    static let farAway = 240.0

    /// Las lecturas del ultimo tramo: dentro de la ventana y despues del ultimo salto hacia arriba (una compactacion).
    static func recent(_ samples: [ContextSample], now: Date) -> [ContextSample] {
        var pts = samples.filter { now.timeIntervalSince($0.at) <= window }.sorted { $0.at < $1.at }
        if let jump = pts.indices.dropFirst().last(where: { pts[$0].percent - pts[$0 - 1].percent >= 8 }) { pts = Array(pts[jump...]) }
        return pts
    }

    static func project(samples: [ContextSample], compactAt: Int, now: Date) -> Result? {
        let pts = recent(samples, now: now)
        guard pts.count >= 3, let first = pts.first, let last = pts.last, last.at.timeIntervalSince(first.at) >= minSpan, last.percent > 0 else { return nil }
        let xs = pts.map { $0.at.timeIntervalSince(first.at) / 60 }, ys = pts.map { Double($0.percent) }
        let n = Double(pts.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / den      // puntos por minuto
        guard slope <= -0.05 else { return nil }
        let minutes = Double(last.percent) / -slope
        guard minutes <= farAway else { return nil }
        return Result(minutes: minutes, percentPerMinute: -slope, tokensPerMinute: Int((-slope / 100 * Double(compactAt)).rounded()))
    }

    static func label(_ r: Result) -> String {
        let m = Int(r.minutes.rounded(.up))
        if m < 2 { return "compactas ya" }
        if m < 60 { return "compactas en ~\(m) min" }
        return "compactas en ~\(m / 60) h \(String(format: "%02d", m % 60))"
    }

    /// Por que no hay pronostico: faltan lecturas, esta estable o no hay riesgo.
    static func status(_ samples: [ContextSample], now: Date) -> String {
        let pts = recent(samples, now: now)
        guard pts.count >= 3, let a = pts.first, let b = pts.last, b.at.timeIntervalSince(a.at) >= minSpan else { return "reuniendo datos" }
        return "sin riesgo cerca"
    }

    static func compactTokens(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
}

enum TouchBarPulse {
    static let columns = 24
    static let minutesPerColumn = 2.0

    private static func column(of e: PetMemoryEvent, now: Date) -> Int? {
        let age = now.timeIntervalSince(e.at)
        guard age >= 0, age < Double(columns) * minutesPerColumn * 60 else { return nil }
        return columns - 1 - Int(age / (minutesPerColumn * 60))
    }
    private static func agent(_ e: PetMemoryEvent) -> String { e.agent.isEmpty ? "claude" : e.agent }

    /// Calor por columna (la ultima es "ahora"), de 0 a 1 respecto a la columna mas activa de ese agente.
    static func lanes(events: [PetMemoryEvent], agent name: String, now: Date) -> [Double] {
        var counts = [Int](repeating: 0, count: columns)
        for e in events where agent(e) == name { if let c = column(of: e, now: now) { counts[c] += 1 } }
        let peak = max(1, counts.max() ?? 1)
        return counts.map { Double($0) / Double(peak) }
    }

    /// Lo que paso en una columna: la barra lo cuenta cuando arrastras el dedo por ella.
    static func readout(events: [PetMemoryEvent], agent name: String, column col: Int, now: Date) -> String {
        let inCol = events.filter { agent($0) == name && column(of: $0, now: now) == col }
        let ago = (columns - 1 - col) * Int(minutesPerColumn)
        let when = ago == 0 ? "ahora" : "hace \(ago) min"
        guard !inCol.isEmpty else { return "\(when) · nada" }
        func n(_ k: PetMemoryEvent.Kind) -> Int { inCol.filter { $0.kind == k }.count }
        var parts: [String] = []
        if n(.tool) > 0 { parts.append("\(n(.tool)) \(n(.tool) == 1 ? "uso" : "usos")") }
        if n(.session) > 0 { parts.append("\(n(.session)) \(n(.session) == 1 ? "sesión" : "sesiones")") }
        if n(.permission) > 0 { parts.append("\(n(.permission)) \(n(.permission) == 1 ? "permiso" : "permisos")") }
        if n(.error) > 0 { parts.append("\(n(.error)) \(n(.error) == 1 ? "fallo" : "fallos")") }
        return "\(when) · " + parts.joined(separator: " · ")
    }

    /// "232k / 800k": cuanto lleva y hasta donde llega antes de compactar.
    static func tokens(_ r: ContextReading) -> String {
        func k(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1000 ? "\(Int((Double(n) / 1000).rounded()))k" : "\(n)" }
        return "\(k(r.usedTokens)) / \(k(r.compactAtTokens))"
    }

    enum Mode: Equatable { case pulse, permission, question }
    static func mode(pendingPermissions: Int, pendingQuestions: Int = 0) -> Mode {
        pendingPermissions > 0 ? .permission : pendingQuestions > 0 ? .question : .pulse
    }

    /// Hasta donde hay que arrastrar el deslizador para que cuente como "permitir".
    static func threshold(risk: PermissionRisk) -> Double { risk == .high ? 1.0 : 0.92 }
    enum SlideOutcome: Equatable { case allow, reset }
    static func slideOutcome(value: Double, risk: PermissionRisk) -> SlideOutcome { value >= threshold(risk: risk) - 0.0001 ? .allow : .reset }

    static func word(_ s: PetState) -> String {
        switch s {
        case .idle: return "en calma"
        case .starting: return "arrancando"
        case .thinking: return "pensando"
        case .tool: return "trabajando"
        case .waiting: return "espera"
        case .error: return "fallo"
        case .done: return "listo"
        }
    }

    /// Nombre del archivo de una captura: claude-pet-touchbar-pronostico-20261101-153000.png
    static func captureName(page: Page, date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyyMMdd-HHmmss"
        let title = page.title.folding(options: .diacriticInsensitive, locale: nil)
        return "claude-pet-touchbar-\(title)-\(f.string(from: date)).png"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    enum Page: Int, CaseIterable {
        case pulse, limits, forecast, focus, music, brain
        var symbol: String {
            switch self { case .pulse: return "waveform.path.ecg"; case .limits: return "gauge.with.dots.needle.50percent"; case .forecast: return "chart.line.uptrend.xyaxis"; case .focus: return "timer"; case .music: return "music.note"; case .brain: return "brain" }
        }
        var title: String {
            switch self { case .pulse: return "pulso"; case .limits: return "límites"; case .forecast: return "pronóstico"; case .focus: return "foco"; case .music: return "música"; case .brain: return "cerebro" }
        }
    }
}

// MARK: vista

@MainActor final class TouchBarState: ObservableObject {
    @Published var events: [PetMemoryEvent] = []
    @Published var page: TouchBarPulse.Page = .pulse
    @Published var notes: [BrainNote] = []
    @Published var noteTotal = 0
    /// Aviso breve dentro de la barra ("captura guardada").
    @Published var flash: String?
}

private enum TB {
    static let claude = Color(hex: 0xE0824F), codex = Color(hex: 0x5270E8)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func pressure(_ p: ContextPressure) -> Color { IslandMeterStyle.color(p) }
}

struct TouchBarRootView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var state: TouchBarState
    @ObservedObject private var music: MusicController

    init(store: PetStore, state: TouchBarState) {
        self.store = store; self.state = state
        _music = ObservedObject(wrappedValue: store.music)
    }

    var body: some View {
        ZStack {
            Group {
                switch state.page {
                case .pulse: TouchBarPulseView(store: store, state: state)
                case .limits: TouchBarLimitsView(store: store)
                case .forecast: TouchBarForecastView(store: store)
                case .focus: TouchBarFocusView(store: store)
                case .music: TouchBarMusicView(music: music, store: store)
                case .brain: TouchBarBrainView(store: store, state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if (store.state == .done || store.codexState == .done) && !store.reduceMotion { TouchBarConfetti().allowsHitTesting(false) }
            if let note = state.flash {
                Text(note).font(TB.mono(11, .bold)).foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(Color.white))
                    .frame(maxWidth: .infinity, alignment: .center).transition(.opacity)
            }
        }
        .frame(height: 30)
    }
}

/// Confeti que cruza toda la barra cuando un agente termina.
private struct TouchBarConfetti: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let palette: [Color] = [Color(hex: 0xE7B45B), Color(hex: 0xC84B4B), Color(hex: 0x6CCB8A), Color(hex: 0x5270E8), Color(hex: 0xE58BB0)]
                for i in 0..<70 {
                    let x = (Double(i) * 0.6180339).truncatingRemainder(dividingBy: 1) * size.width
                    let speed = 0.5 + (Double(i * 7 % 10) / 10)
                    let y = ((t * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)) * (size.height + 6) - 3
                    gc.fill(Path(CGRect(x: x + sin(t * 3 + Double(i)) * 3, y: y, width: 3, height: 3)), with: .color(palette[i % palette.count]))
                }
            }
        }
    }
}

struct TouchBarPulseView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var state: TouchBarState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 6.0)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate * 6)
            HStack(spacing: 16) {
                TouchBarLane(agent: "claude", tint: TB.claude, st: store.state, context: store.contextReading, forecast: ContextForecast.project(samples: store.contextHistory, compactAt: store.contextReading?.compactAtTokens ?? 0, now: ctx.date), events: state.events, tick: tick, now: ctx.date)
                if store.codexPresent {
                    TouchBarLane(agent: "codex", tint: TB.codex, st: store.codexState, context: store.codexContextReading, forecast: ContextForecast.project(samples: store.codexContextHistory, compactAt: store.codexContextReading?.compactAtTokens ?? 0, now: ctx.date), events: state.events, tick: tick, now: ctx.date)
                }
            }
        }
    }
}

private struct TouchBarLane: View {
    let agent: String
    let tint: Color
    let st: PetState
    let context: ContextReading?
    var forecast: ContextForecast.Result? = nil
    let events: [PetMemoryEvent]
    let tick: Int
    let now: Date
    @State private var scrub: Int?
    @State private var hopAt: Date?
    private let barWidth: CGFloat = 156

    var body: some View {
        let heat = TouchBarPulse.lanes(events: events, agent: agent, now: now)
        let working = st == .thinking || st == .tool || st == .starting || st == .waiting
        let hop = hopAt.map { max(0, 1 - now.timeIntervalSince($0) / 0.6) } ?? 0
        HStack(spacing: 6) {
            Canvas { gc, size in
                let lift = CGFloat(sin(hop * .pi)) * 1.6
                if agent == "claude" {
                    var pose = PetPose(); pose.dy = (working ? -CGFloat(abs(sin(Double(tick) * 0.9))) * 0.8 : 0) - lift
                    PetFace.draw(&gc, size: size, pixels: Sprite.pixels(hop > 0 ? .done : st, tick: tick), pose: pose)
                } else {
                    let u = min(size.width / 18, size.height / 21)
                    let ox = (size.width - 18 * u) / 2
                    let face: CodexAvatar.Face = {
                        if hop > 0 { return .happy }
                        switch st {
                        case .waiting: return .alert(on: tick % 2 == 0)
                        case .error: return .cross
                        case .done: return .happy
                        case .thinking, .starting: return .dots(tick % 4)
                        case .tool: return .typing(tick)
                        default: return .prompt(cursor: tick % 2 == 0)
                        }
                    }()
                    for c in CodexAvatar.cells(legs: working && tick % 2 == 0 ? .step : .stand, face: face) {
                        gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: CGFloat(c.y) * u - lift, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
                    }
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .onTapGesture { hopAt = Date(); TouchBarHaptics.tap(.generic) }

            Canvas { gc, size in
                let w = size.width / CGFloat(heat.count)
                for (i, h) in heat.enumerated() {
                    let bar = max(2, size.height * CGFloat(h))
                    let age = Double(i) / Double(heat.count)
                    let chosen = scrub == i
                    gc.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w + 0.5, y: size.height - bar, width: w - 1.5, height: bar), cornerRadius: 1),
                            with: .color(chosen ? .white : tint.opacity(h == 0 ? 0.18 : 0.35 + 0.65 * age)))
                }
            }
            .frame(width: barWidth, height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let col = max(0, min(heat.count - 1, Int(v.location.x / (barWidth / CGFloat(heat.count)))))
                    if col != scrub { TouchBarHaptics.tap(.alignment) }
                    scrub = col
                }
                .onEnded { _ in scrub = nil })

            VStack(alignment: .leading, spacing: 0) {
                if let col = scrub {
                    Text(TouchBarPulse.readout(events: events, agent: agent, column: col, now: now)).font(TB.mono(9, .semibold)).foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.8)
                } else {
                    Text("\(agent) · \(TouchBarPulse.word(st))").font(TB.mono(10, .bold)).foregroundColor(working ? tint : .white).lineLimit(1)
                    if let f = forecast, f.minutes <= 10 {
                        Text(ContextForecast.label(f)).font(TB.mono(8.5, .bold)).foregroundColor(Color(hex: f.minutes <= 4 ? 0xD85C5C : 0xE7B45B)).lineLimit(1)
                    } else if let r = context {
                        Text("ctx \(r.remainingPercent)% · \(TouchBarPulse.tokens(r))").font(TB.mono(8.5)).foregroundColor(TB.pressure(r.pressure)).lineLimit(1)
                    } else {
                        Text("ctx sin lectura").font(TB.mono(8.5)).foregroundColor(.white.opacity(0.35)).lineLimit(1)
                    }
                }
            }
            .frame(width: 118, alignment: .leading)
        }
    }
}

/// Medidor largo con titulo, valor y texto aparte: para contexto y limites del plan.
private struct TouchBarGauge: View {
    let title: String
    let value: String
    let fraction: Double?
    let color: Color
    let note: String?
    var width: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(TB.mono(8.5, .semibold)).foregroundColor(.white.opacity(0.55))
                Spacer(minLength: 0)
                Text(value).font(TB.mono(10, .bold)).foregroundColor(fraction == nil ? .white.opacity(0.35) : color)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                if let f = fraction { Capsule().fill(color).frame(width: max(3, width * CGFloat(min(1, max(0, f))))) }
            }.frame(height: 6)
            Text(note ?? " ").font(TB.mono(8)).foregroundColor(.white.opacity(0.4)).lineLimit(1)
        }
        .frame(width: width)
    }
}

struct TouchBarLimitsView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            HStack(spacing: 14) {
                gauge(title: "claude · contexto", reading: store.contextReading)
                if store.codexPresent { gauge(title: "codex · contexto", reading: store.codexContextReading) }
                if let u = store.plan.usage {
                    if let f = u.five { plan("plan · 5 h", f, now: now, stale: u.isStale(now: now)) }
                    if let w = u.week { plan("plan · semana", w, now: now, stale: u.isStale(now: now)) }
                } else {
                    Text("sin datos del plan: aparecen cuando claude trabaja").font(TB.mono(9)).foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private func gauge(title: String, reading: ContextReading?) -> some View {
        if let r = reading {
            return TouchBarGauge(title: title, value: "\(r.remainingPercent)%", fraction: Double(r.remainingPercent) / 100, color: TB.pressure(r.pressure), note: "\(TouchBarPulse.tokens(r)) · \(r.pressureLabel)")
        }
        return TouchBarGauge(title: title, value: "—", fraction: nil, color: .white, note: "sin lectura")
    }

    private func plan(_ title: String, _ w: PlanWindow, now: Date, stale: Bool) -> some View {
        let used = w.effectivePercent(now: now), left = w.remainingPercent(now: now)
        let color: Color = used >= 95 ? Color(hex: 0xD85C5C) : used >= 80 ? Color(hex: 0xE7B45B) : Color(hex: 0x5270E8)
        let reset = w.resetText(now: now).map { "reinicia en \($0)" } ?? ""
        return TouchBarGauge(title: title, value: "\(left)%", fraction: Double(left) / 100, color: color, note: stale ? "dato viejo · \(reset)" : reset)
    }
}

/// Pronostico: la curva del contexto de cada agente y, en punteado, hacia donde va a este ritmo.
struct TouchBarForecastView: View {
    @ObservedObject var store: PetStore
    var claudeSamples: [ContextSample]? = nil
    var codexSamples: [ContextSample]? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 16) {
                block("claude", TB.claude, claudeSamples ?? store.contextHistory, store.contextReading, now: ctx.date)
                if store.codexPresent { block("codex", TB.codex, codexSamples ?? store.codexContextHistory, store.codexContextReading, now: ctx.date) }
            }
        }
    }

    private func block(_ agent: String, _ tint: Color, _ samples: [ContextSample], _ reading: ContextReading?, now: Date) -> some View {
        let f = ContextForecast.project(samples: samples, compactAt: reading?.compactAtTokens ?? 0, now: now)
        let urgent: Color = (f?.minutes ?? 999) <= 4 ? Color(hex: 0xD85C5C) : (f?.minutes ?? 999) <= 10 ? Color(hex: 0xE7B45B) : tint
        return HStack(spacing: 8) {
            Canvas { gc, size in
                let pts = ContextForecast.recent(samples, now: now)
                guard let first = pts.first, let last = pts.last else {
                    gc.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(.white.opacity(0.2))); return
                }
                let horizon = min(f?.minutes ?? 0, 45)
                let t0 = first.at.timeIntervalSince(now) / 60, span = max(2, -t0 + horizon)
                func pt(_ minutes: Double, _ percent: Double) -> CGPoint { CGPoint(x: CGFloat((minutes - t0) / span) * size.width, y: size.height - CGFloat(percent / 100) * size.height) }
                var line = Path()
                for (i, s) in pts.enumerated() { let q = pt(s.at.timeIntervalSince(now) / 60, Double(s.percent)); if i == 0 { line.move(to: q) } else { line.addLine(to: q) } }
                gc.stroke(line, with: .color(tint), lineWidth: 2)
                gc.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(.white.opacity(0.25)))     // el limite: 0 % restante
                if let f {
                    var proj = Path()
                    proj.move(to: pt(last.at.timeIntervalSince(now) / 60, Double(last.percent)))
                    proj.addLine(to: pt(horizon, max(0, Double(last.percent) - f.percentPerMinute * (horizon - last.at.timeIntervalSince(now) / 60))))
                    gc.stroke(proj, with: .color(urgent), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                }
            }
            .frame(width: 170, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.map { ContextForecast.label($0) } ?? ContextForecast.status(samples, now: now)).font(TB.mono(10, .bold)).foregroundColor(f == nil ? .white.opacity(0.7) : urgent).lineLimit(1)
                Text(f.map { "\(agent) · ≈ \(ContextForecast.compactTokens($0.tokensPerMinute))/min" } ?? "\(agent) · contexto").font(TB.mono(8.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
        }
    }
}

struct TouchBarFocusView: View {
    @ObservedObject var store: PetStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let p = store.pomodoro
            HStack(spacing: 12) {
                if p.phase == .idle {
                    Text("sin foco en marcha").font(TB.mono(11)).foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    button("empezar 25 min", "play.fill", prominent: true) { store.pomodoro.start(now: ProcessInfo.processInfo.systemUptime) }
                } else {
                    let total = p.length(of: p.phase), left = p.remaining(now: now)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.phase == .work ? "foco" : p.phase.rawValue).font(TB.mono(8.5, .semibold)).foregroundColor(.white.opacity(0.55))
                        Text(TouchBarPulse.clock(left)).font(TB.mono(16, .bold)).foregroundColor(p.phase == .work ? TB.claude : Color(hex: 0x6CCB8A))
                    }
                    .frame(width: 70, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(p.phase == .work ? TB.claude : Color(hex: 0x6CCB8A)).frame(width: max(4, 300 * CGFloat(total > 0 ? 1 - left / total : 0)))
                    }.frame(width: 300, height: 8)
                    Text("\(p.completed) hechos").font(TB.mono(9)).foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                    if p.isPaused { button("reanudar", "play.fill") { store.pomodoro.resume(now: ProcessInfo.processInfo.systemUptime) } }
                    else { button("pausar", "pause.fill") { store.pomodoro.pause(now: ProcessInfo.processInfo.systemUptime) } }
                    button("parar", "stop.fill") { store.pomodoro.stop() }
                }
            }
            .frame(width: 640)
        }
    }

    private func button(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button { TouchBarHaptics.tap(.generic); action() } label: {
            Label(title, systemImage: symbol).font(TB.mono(10, .bold)).foregroundColor(prominent ? .black : .white)
                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(prominent ? TB.claude : Color.white.opacity(0.16)))
        }.buttonStyle(.plain)
    }
}

struct TouchBarMusicView: View {
    @ObservedObject var music: MusicController
    let store: PetStore
    @State private var drag: Double?

    var body: some View {
        if let n = music.nowPlaying {
            let accent = Color(hex: music.tint ?? 0xE0824F)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let pos = music.position(at: ProcessInfo.processInfo.systemUptime)
                let frac = drag ?? (n.duration > 0 ? min(1, max(0, pos / n.duration)) : 0)
                HStack(spacing: 10) {
                    Group {
                        if let c = music.cover { Image(nsImage: c).resizable().scaledToFill() } else { accent.opacity(0.5) }
                    }
                    .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(n.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Text(n.artist).font(.system(size: 9)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                    Text(TouchBarPulse.clock(frac * n.duration)).font(TB.mono(9)).foregroundColor(.white.opacity(0.6))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.16))
                            Capsule().fill(accent).frame(width: max(4, geo.size.width * CGFloat(frac)))
                            Circle().fill(.white).frame(width: 14, height: 14).offset(x: max(0, geo.size.width * CGFloat(frac) - 7))
                        }
                        .frame(height: 14)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in drag = min(1, max(0, Double(v.location.x / geo.size.width))) }
                            .onEnded { v in music.seek(toFraction: min(1, max(0, Double(v.location.x / geo.size.width)))); TouchBarHaptics.tap(.levelChange); drag = nil })
                    }
                    .frame(width: 210, height: 14)
                    Text(TouchBarPulse.clock(n.duration)).font(TB.mono(9)).foregroundColor(.white.opacity(0.6))
                    control("backward.fill") { music.send(.previous) }
                    control(n.isPlaying ? "pause.fill" : "play.fill", big: true, tint: accent) { music.send(.playPause) }
                    control("forward.fill") { music.send(.next) }
                }
            }
        } else {
            Text("no suena nada: pon música en Spotify o Música").font(TB.mono(11)).foregroundColor(.white.opacity(0.5))
        }
    }

    private func control(_ symbol: String, big: Bool = false, tint: Color = Color.white.opacity(0.16), action: @escaping () -> Void) -> some View {
        Button { TouchBarHaptics.tap(.generic); action() } label: {
            Image(systemName: symbol).font(.system(size: big ? 13 : 11, weight: .bold)).foregroundColor(big ? .black : .white)
                .frame(width: big ? 44 : 36, height: 26).background(Capsule().fill(big ? tint : Color.white.opacity(0.16)))
        }.buttonStyle(.plain)
    }
}

struct TouchBarBrainView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var state: TouchBarState

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(state.noteTotal)").font(TB.mono(15, .bold)).foregroundColor(.white)
                Text(store.terminalProject.isEmpty ? "global" : BrainStore.clean(project: store.terminalProject)).font(TB.mono(8.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            if state.notes.isEmpty {
                Text("sin notas todavía: los agentes las dejan al terminar algo importante").font(TB.mono(9.5)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
            } else {
                ForEach(state.notes.prefix(3)) { n in
                    HStack(spacing: 5) {
                        Circle().fill(n.kind.tint).frame(width: 6, height: 6)
                        Text(n.text).font(.system(size: 10)).foregroundColor(.white).lineLimit(1).frame(width: 150, alignment: .leading)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
            Spacer(minLength: 0)
            Button { TouchBarHaptics.tap(.generic); BrainEditorWindow.present(project: store.terminalProject, note: nil) } label: {
                Label("nota", systemImage: "plus").font(TB.mono(10, .bold)).foregroundColor(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(TB.claude))
            }.buttonStyle(.plain)
        }
        .frame(width: 640)
    }
}

enum TouchBarHaptics {
    /// El trackpad vibra debajo de la barra: confirma lo que tocas sin mirar.
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

// MARK: la barra

extension NSTouchBarItem.Identifier {
    static let pager = NSTouchBarItem.Identifier("claudepet.pager")
    static let content = NSTouchBarItem.Identifier("claudepet.content")
    static let shot = NSTouchBarItem.Identifier("claudepet.shot")
    static let askLabel = NSTouchBarItem.Identifier("claudepet.ask.label")
    static let askSlide = NSTouchBarItem.Identifier("claudepet.ask.slide")
    static let askAlways = NSTouchBarItem.Identifier("claudepet.ask.always")
    static let askDeny = NSTouchBarItem.Identifier("claudepet.ask.deny")
    static let qLabel = NSTouchBarItem.Identifier("claudepet.q.label")
    static let qDone = NSTouchBarItem.Identifier("claudepet.q.done")
    static func qOption(_ i: Int) -> NSTouchBarItem.Identifier { NSTouchBarItem.Identifier("claudepet.q.option.\(i)") }
}

@MainActor final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let store: PetStore
    private let state = TouchBarState()
    private lazy var pulseBar: NSTouchBar = makeBar([.pager, .content, .shot])
    private var askBar = NSTouchBar()
    private var questionBar = NSTouchBar()
    private var shown: TouchBarPulse.Mode?
    private var shownBar: NSTouchBar?
    private var timer: Timer?
    private var currentAsk: PermissionAsk?
    private var askRisk: PermissionRisk = .low
    private var currentQuestion: QuestionAsk?
    private var qIndex = 0
    private var qSelected = Set<Int>()
    private var qAnswers: [String: String] = [:]

    init(store: PetStore) { self.store = store }

    func start() {
        guard TouchBarHardware.enabled(), timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        dismiss()
        shown = nil
    }

    private func makeBar(_ ids: [NSTouchBarItem.Identifier]) -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = ids
        return bar
    }

    private func refresh() {
        state.events = PetMemoryStore.shared.snapshot()
        let project = store.terminalProject
        let all = BrainStore.shared.notes(project)
        state.notes = all; state.noteTotal = all.count
        let mode = TouchBarPulse.mode(pendingPermissions: store.permissionAsks.count, pendingQuestions: store.questionAsks.count)
        var changed = mode != shown

        if mode == .permission, let a = store.permissionAsks.first, a.id != currentAsk?.id {
            currentAsk = a
            askRisk = PermissionRiskClassifier.classify(tool: a.tool, detail: a.detail, project: a.project).risk
            askBar = makeBar([.askLabel, .askSlide] + (a.canAlways && askRisk != .high && a.tool != "ExitPlanMode" ? [.askAlways] : []) + [.askDeny])
            changed = true
        }
        if mode != .permission { currentAsk = nil }

        if mode == .question, let q = store.questionAsks.first {
            if q.id != currentQuestion?.id { currentQuestion = q; qIndex = 0; qSelected = []; qAnswers = [:]; rebuildQuestionBar(); changed = true }
        } else if mode != .question { currentQuestion = nil }

        guard changed else { return }
        dismiss()
        let bar = mode == .permission ? askBar : mode == .question ? questionBar : pulseBar
        present(bar)
        shown = mode; shownBar = bar
        if mode != .pulse { TouchBarHaptics.tap(.levelChange) }
    }

    private func rebuildQuestionBar() {
        guard let q = currentQuestion, q.questions.indices.contains(qIndex) else { return }
        let item = q.questions[qIndex]
        var ids: [NSTouchBarItem.Identifier] = [.qLabel] + item.options.prefix(4).indices.map { .qOption($0) }
        if item.multiSelect { ids.append(.qDone) }
        questionBar = makeBar(ids)
    }

    // La barra a pantalla completa de una app en segundo plano solo se puede pedir por la API privada del sistema,
    // la misma que usan otras apps de barra. Si el sistema no la ofrece, simplemente no se muestra.
    private func present(_ bar: NSTouchBar) {
        let cls = NSTouchBar.self as AnyObject
        for name in ["presentSystemModalTouchBar:systemTrayItemIdentifier:", "presentSystemModalFunctionBar:systemTrayItemIdentifier:"] {
            let sel = NSSelectorFromString(name)
            if cls.responds(to: sel) { _ = cls.perform(sel, with: bar, with: nil); return }
        }
    }

    private func dismiss() {
        guard let bar = shownBar else { return }
        let cls = NSTouchBar.self as AnyObject
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let sel = NSSelectorFromString(name)
            if cls.responds(to: sel) { _ = cls.perform(sel, with: bar); break }
        }
        shownBar = nil
    }

    private static let alert = NSColor(srgbRed: 1, green: 0.45, blue: 0.4, alpha: 1)
    private static let ember = NSColor(srgbRed: 0.88, green: 0.51, blue: 0.31, alpha: 1)

    private func label(_ id: NSTouchBarItem.Identifier, _ text: String, color: NSColor = .white, width: CGFloat) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: id)
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        item.view = field
        return item
    }

    private func button(_ id: NSTouchBarItem.Identifier, _ title: String, tint: NSColor? = nil, action: Selector) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: id)
        let b = NSButton(title: title, target: self, action: action)
        if let tint { b.bezelColor = tint }
        item.view = b
        return item
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case .pager:
            let item = NSCustomTouchBarItem(identifier: id)
            let seg = NSSegmentedControl(images: TouchBarPulse.Page.allCases.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title) ?? NSImage() },
                                         trackingMode: .selectOne, target: self, action: #selector(pageChanged(_:)))
            seg.selectedSegment = state.page.rawValue
            for i in 0..<seg.segmentCount { seg.setWidth(36, forSegment: i) }
            item.view = seg
            return item
        case .content:
            let item = NSCustomTouchBarItem(identifier: id)
            let host = NSHostingView(rootView: TouchBarRootView(store: store, state: state))
            host.widthAnchor.constraint(equalToConstant: 740).isActive = true
            item.view = host
            return item
        case .shot:
            let item = NSCustomTouchBarItem(identifier: id)
            let b = NSButton(image: NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "captura de la barra") ?? NSImage(), target: self, action: #selector(capture))
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            item.view = b
            return item
        case .askLabel:
            let more = store.permissionAsks.count > 1 ? "  +\(store.permissionAsks.count - 1)" : ""
            let isPlan = currentAsk?.tool == "ExitPlanMode"
            let target = (currentAsk?.detail ?? "").replacingOccurrences(of: "\n", with: " ")
            return label(id, "\(isPlan ? "plan" : currentAsk?.tool ?? "permiso") \(target.prefix(48))\(more)", color: askRisk == .high ? Self.alert : .white, width: 300)
        case .askSlide:
            let item = NSSliderTouchBarItem(identifier: id)
            item.slider.minValue = 0; item.slider.maxValue = 1; item.slider.doubleValue = 0
            item.slider.isContinuous = false
            item.slider.trackFillColor = askRisk == .high ? Self.alert : Self.ember
            item.label = askRisk == .high ? "a fondo para permitir" : currentAsk?.tool == "ExitPlanMode" ? "desliza para aprobar" : "desliza para permitir"
            item.target = self; item.action = #selector(slid(_:))
            item.view.widthAnchor.constraint(equalToConstant: 280).isActive = true
            return item
        case .askAlways: return button(id, "siempre", action: #selector(always))
        case .askDeny: return button(id, "denegar", action: #selector(deny))
        case .qLabel:
            guard let q = currentQuestion, q.questions.indices.contains(qIndex) else { return nil }
            let item = q.questions[qIndex]
            let step = q.questions.count > 1 ? " (\(qIndex + 1)/\(q.questions.count))" : ""
            return label(id, "\(item.question)\(step)", width: 250)
        case .qDone: return button(id, "listo", tint: Self.ember, action: #selector(questionDone))
        default:
            if id.rawValue.hasPrefix("claudepet.q.option."), let i = Int(id.rawValue.split(separator: ".").last ?? ""),
               let q = currentQuestion, q.questions.indices.contains(qIndex), q.questions[qIndex].options.indices.contains(i) {
                let b = button(id, String(q.questions[qIndex].options[i].label.prefix(22)), action: #selector(optionTapped(_:)))
                (b.view as? NSButton)?.tag = i
                if qSelected.contains(i) { (b.view as? NSButton)?.bezelColor = Self.ember }
                return b
            }
            return nil
        }
    }

    /// Lo que se ve en la barra, tal cual: la pagina actual a 2170 x 60 px (el tamano real de la pantalla) o mas.
    /// Se guarda en el escritorio y se copia al portapapeles para pegarla donde quieras.
    @objc private func capture() {
        let page = state.page
        let view = TouchBarRootView(store: store, state: state).frame(width: 740, height: 30).padding(.horizontal, 10).padding(.vertical, 4).background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { flash("no se pudo capturar"); return }
        let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let url = dir.appendingPathComponent(TouchBarPulse.captureName(page: page, date: Date()))
        do { try png.write(to: url) } catch { flash("no se pudo guardar"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        TouchBarHaptics.tap(.levelChange)
        flash("captura guardada y copiada")
    }

    private func flash(_ text: String) {
        withAnimation { state.flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in withAnimation { self?.state.flash = nil } }
    }

    @objc private func pageChanged(_ sender: NSSegmentedControl) {
        state.page = TouchBarPulse.Page(rawValue: sender.selectedSegment) ?? .pulse
        TouchBarHaptics.tap(.alignment)
    }

    @objc private func slid(_ sender: NSSliderTouchBarItem) {
        guard let ask = currentAsk else { return }
        switch TouchBarPulse.slideOutcome(value: sender.slider.doubleValue, risk: askRisk) {
        case .allow: TouchBarHaptics.tap(.levelChange); store.answerPermission(ask.id, .allow)
        case .reset:
            TouchBarHaptics.tap(.alignment)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; sender.slider.animator().doubleValue = 0 }
        }
    }

    @objc private func always() { if let ask = currentAsk { TouchBarHaptics.tap(.levelChange); store.answerPermission(ask.id, .always) } }
    @objc private func deny() { if let ask = currentAsk { TouchBarHaptics.tap(.generic); store.answerPermission(ask.id, .deny) } }

    @objc private func optionTapped(_ sender: NSButton) {
        guard let q = currentQuestion, q.questions.indices.contains(qIndex) else { return }
        TouchBarHaptics.tap(.generic)
        if q.questions[qIndex].multiSelect {
            if qSelected.contains(sender.tag) { qSelected.remove(sender.tag) } else { qSelected.insert(sender.tag) }
            rebuildQuestionBar(); dismiss(); present(questionBar); shownBar = questionBar
        } else {
            commit(selected: [sender.tag])
        }
    }

    @objc private func questionDone() { commit(selected: qSelected.sorted()) }

    private func commit(selected: [Int]) {
        guard let q = currentQuestion, q.questions.indices.contains(qIndex) else { return }
        let item = q.questions[qIndex]
        qAnswers[item.question] = selected.compactMap { item.options.indices.contains($0) ? item.options[$0].label : nil }.joined(separator: ", ")
        qSelected = []
        if qIndex + 1 >= q.questions.count {
            store.answerQuestion(q.id, qAnswers)
            currentQuestion = nil
        } else {
            qIndex += 1
            rebuildQuestionBar(); dismiss(); present(questionBar); shownBar = questionBar
        }
    }
}

// MARK: pruebas y captura

enum TouchBarSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ c: Bool) { print((c ? "PASS " : "FAIL ") + name); if !c { ok = false } }
        check("un MacBook Pro 2019 de 16 pulgadas tiene Touch Bar", TouchBarHardware.hasTouchBar(model: "MacBookPro16,1"))
        check("un MacBook Pro con notch no la tiene", !TouchBarHardware.hasTouchBar(model: "Mac15,6") && !TouchBarHardware.hasTouchBar(model: "MacBookPro18,3"))
        check("el entorno fuerza y apaga", TouchBarHardware.enabled(env: ["CLAUDE_PET_TOUCHBAR": "1"], model: "Mac15,6") && !TouchBarHardware.enabled(env: ["CLAUDE_PET_TOUCHBAR": "0"], model: "MacBookPro16,1"))
        check("sin entorno decide el modelo", TouchBarHardware.enabled(env: [:], model: "MacBookPro16,1") && !TouchBarHardware.enabled(env: [:], model: "Mac15,6"))
        let now = Date()
        func ev(_ agent: String, ago: TimeInterval, _ kind: PetMemoryEvent.Kind = .tool) -> PetMemoryEvent { PetMemoryEvent(id: UUID(), at: now.addingTimeInterval(-ago), kind: kind, agent: agent, project: "p") }
        let events = [ev("claude", ago: 10), ev("claude", ago: 20), ev("claude", ago: 400), ev("codex", ago: 30), ev("claude", ago: 60 * 60 * 2), ev("claude", ago: 15, .error)]
        let c = TouchBarPulse.lanes(events: events, agent: "claude", now: now)
        check("hay una columna por cada 2 minutos", c.count == TouchBarPulse.columns)
        check("lo de ahora cae en la ultima columna y es el maximo", c.last == 1 && c.dropLast().allSatisfy { $0 <= 1 })
        check("lo de hace 7 minutos cae mas atras", c[TouchBarPulse.columns - 4] == 1.0 / 3.0)
        check("lo de hace mas de 48 minutos no cuenta", c.filter { $0 > 0 }.count == 2)
        check("cada agente tiene su pista", TouchBarPulse.lanes(events: events, agent: "codex", now: now).last == 1)
        check("un evento sin agente cuenta como claude", TouchBarPulse.lanes(events: [ev("", ago: 5)], agent: "claude", now: now).last == 1)
        check("sin eventos todo queda a cero", TouchBarPulse.lanes(events: [], agent: "claude", now: now).allSatisfy { $0 == 0 })
        let last = TouchBarPulse.columns - 1
        check("al arrastrar cuenta lo de esa columna", TouchBarPulse.readout(events: events, agent: "claude", column: last, now: now) == "ahora · 2 usos · 1 fallo")
        check("una columna vacia lo dice", TouchBarPulse.readout(events: events, agent: "claude", column: 3, now: now) == "hace 40 min · nada")
        check("la columna de hace 7 minutos dice hace 6 min", TouchBarPulse.readout(events: events, agent: "claude", column: last - 3, now: now).hasPrefix("hace 6 min"))
        check("modo: permisos mandan sobre preguntas", TouchBarPulse.mode(pendingPermissions: 1, pendingQuestions: 1) == .permission && TouchBarPulse.mode(pendingPermissions: 0, pendingQuestions: 2) == .question && TouchBarPulse.mode(pendingPermissions: 0) == .pulse)
        check("a medio camino el deslizador vuelve", TouchBarPulse.slideOutcome(value: 0.5, risk: .low) == .reset)
        check("al final permite", TouchBarPulse.slideOutcome(value: 0.95, risk: .low) == .allow)
        check("con riesgo alto no basta casi llegar", TouchBarPulse.slideOutcome(value: 0.95, risk: .high) == .reset && TouchBarPulse.slideOutcome(value: 1, risk: .high) == .allow)
        check("reloj de foco", TouchBarPulse.clock(1500) == "25:00" && TouchBarPulse.clock(61) == "01:01" && TouchBarPulse.clock(-3) == "00:00")
        check("fichas de contexto legibles", TouchBarPulse.tokens(ContextReading(usedTokens: 232_000, compactAtTokens: 800_000, model: "x")) == "232k / 800k"
              && TouchBarPulse.tokens(ContextReading(usedTokens: 90_500, compactAtTokens: 1_000_000, model: "x")) == "91k / 1.0M")
        // contexto: la ventana se deduce de lo usado (antes marcaba 0 % pasados 160 000 tokens)
        check("ventana normal hasta 200 000 tokens", ContextMeter.compactAt(forUsed: 90_000, env: [:]) == 160_000 && ContextMeter.compactAt(forUsed: 200_000, env: [:]) == 160_000)
        check("pasados 200 000 tokens es la ventana grande", ContextMeter.compactAt(forUsed: 232_000, env: [:]) == 800_000)
        check("una sesion de 232 000 tokens ya no marca 0 %", ContextReading(usedTokens: 232_000, compactAtTokens: ContextMeter.compactAt(forUsed: 232_000, env: [:]), model: "x").remainingPercent == 71)
        check("el entorno manda sobre la deduccion", ContextMeter.compactAt(forUsed: 232_000, env: ["CLAUDE_PET_COMPACTION_TOKENS": "300000"]) == 300_000)
        // pronostico del contexto
        func sample(_ percent: Int, minutesAgo: Double) -> ContextSample { ContextSample(percent: percent, pressure: .normal, at: now.addingTimeInterval(-minutesAgo * 60)) }
        let falling = [sample(80, minutesAgo: 10), sample(70, minutesAgo: 5), sample(60, minutesAgo: 0)]
        let fc = ContextForecast.project(samples: falling, compactAt: 160_000, now: now)
        check("a 2 puntos por minuto desde 60 % quedan 30 min", fc.map { abs($0.minutes - 30) < 0.01 } == true)
        check("calcula los tokens por minuto", fc?.tokensPerMinute == 3200)
        check("la etiqueta dice cuanto falta", fc.map(ContextForecast.label) == "compactas en ~30 min")
        check("con una hora o mas usa horas", ContextForecast.label(.init(minutes: 65, percentPerMinute: 1, tokensPerMinute: 0)) == "compactas en ~1 h 05")
        check("estable no pronostica", ContextForecast.project(samples: [sample(60, minutesAgo: 10), sample(60, minutesAgo: 5), sample(59, minutesAgo: 0)], compactAt: 160_000, now: now) == nil)
        check("con menos de tres lecturas no pronostica", ContextForecast.project(samples: Array(falling.prefix(2)), compactAt: 160_000, now: now) == nil
              && ContextForecast.status(Array(falling.prefix(2)), now: now) == "reuniendo datos")
        check("una compactacion reinicia el tramo", ContextForecast.project(samples: [sample(20, minutesAgo: 20), sample(15, minutesAgo: 18), sample(10, minutesAgo: 16), sample(90, minutesAgo: 10), sample(80, minutesAgo: 5), sample(70, minutesAgo: 0)], compactAt: 160_000, now: now).map { abs($0.minutes - 35) < 0.01 } == true)
        check("lo lejano no se anuncia", ContextForecast.project(samples: [sample(90, minutesAgo: 20), sample(89, minutesAgo: 10), sample(88, minutesAgo: 0)], compactAt: 160_000, now: now) == nil)
        check("las lecturas viejas no cuentan", ContextForecast.recent([sample(50, minutesAgo: 90), sample(40, minutesAgo: 1)], now: now).count == 1)
        let when = Date(timeIntervalSince1970: 1_793_547_000)
        check("el nombre de la captura lleva pagina y fecha sin acentos", TouchBarPulse.captureName(page: .forecast, date: when, timeZone: TimeZone(identifier: "UTC")!) == "claude-pet-touchbar-pronostico-20261101-153000.png")
        print(ok ? "TOUCHBAR OK" : "TOUCHBAR FALLO")
        return ok
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-touchbar <ruta.png>`: las paginas de la barra a su tamano real (30 pt de alto) sobre negro.
    private static func forecastDemo(_ now: Date, from: Int, step: Int) -> [ContextSample] {
        (0..<8).map { i in ContextSample(percent: from + step * i, pressure: .normal, at: now.addingTimeInterval(-Double(7 - i) * 150)) }
    }

    static func touchBar(to path: String) {
        let store = PetStore.shared
        store.startDemo()
        let now = Date()
        var events: [PetMemoryEvent] = []
        for i in 0..<90 {
            let ago = Double(i * i % 2600)
            let kind: PetMemoryEvent.Kind = i % 17 == 0 ? .error : .tool
            let agent = i % 3 == 0 ? "codex" : "claude"
            events.append(PetMemoryEvent(id: UUID(), at: now.addingTimeInterval(-ago), kind: kind, agent: agent, project: "demo"))
        }
        let view = VStack(alignment: .leading, spacing: 8) {
            ForEach(TouchBarPulse.Page.allCases, id: \.rawValue) { page in
                let state = TouchBarState()
                let _ = { state.events = events; state.page = page; state.notes = BrainStore.shared.notes("claude-pet"); state.noteTotal = state.notes.count }()
                HStack(spacing: 10) {
                    Text(page.title).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 52, alignment: .leading)
                    TouchBarRootView(store: store, state: state).frame(width: 760, height: 30)
                }
            }
            HStack(spacing: 10) {
                Text("pronóstico\n(con datos)").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 52, alignment: .leading)
                TouchBarForecastView(store: store, claudeSamples: forecastDemo(now, from: 80, step: -3), codexSamples: forecastDemo(now, from: 70, step: -1))
                    .frame(width: 740, height: 30, alignment: .leading)
            }
        }.padding(10).background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 3
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
