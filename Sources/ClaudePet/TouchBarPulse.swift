import SwiftUI
import AppKit

/// "Pulso": lo que solo tiene sentido en una Mac con Touch Bar.
/// - En calma, la barra es el pulso de tus agentes: cada uno con su mascota y el calor de su actividad de los ultimos 48 min.
/// - Cuando uno pide permiso, la barra cambia a un deslizador: hay que arrastrarlo hasta el final para permitir.
///   Un toque suelto en una tira tactil sin teclas se da sin querer; arrastrar es una decision.
///   Si el riesgo es alto hay que llevarlo a fondo del todo.
/// La parte pura (hardware, calor, umbral del deslizador, modo) no toca AppKit y se prueba sin barra.
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

enum TouchBarPulse {
    static let columns = 24
    static let minutesPerColumn = 2.0

    /// Calor por columna (la ultima es "ahora"), de 0 a 1 respecto a la columna mas activa de ese agente.
    static func lanes(events: [PetMemoryEvent], agent: String, now: Date) -> [Double] {
        var counts = [Int](repeating: 0, count: columns)
        let span = Double(columns) * minutesPerColumn * 60
        for e in events where (e.agent.isEmpty ? "claude" : e.agent) == agent {
            let age = now.timeIntervalSince(e.at)
            guard age >= 0, age < span else { continue }
            let col = columns - 1 - Int(age / (minutesPerColumn * 60))
            if (0..<columns).contains(col) { counts[col] += 1 }
        }
        let peak = max(1, counts.max() ?? 1)
        return counts.map { Double($0) / Double(peak) }
    }

    enum Mode: Equatable { case pulse, permission }
    static func mode(pendingPermissions: Int) -> Mode { pendingPermissions > 0 ? .permission : .pulse }

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
}

// MARK: vista del pulso

@MainActor final class TouchBarState: ObservableObject {
    @Published var events: [PetMemoryEvent] = []
}

struct TouchBarPulseView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var state: TouchBarState

    private static let claudeTint = Color(hex: 0xE0824F), codexTint = Color(hex: 0x5270E8)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 6.0)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate * 6)
            HStack(spacing: 14) {
                lane(agent: "claude", tint: Self.claudeTint, st: store.state, tick: tick, now: ctx.date)
                if store.codexPresent { lane(agent: "codex", tint: Self.codexTint, st: store.codexState, tick: tick, now: ctx.date) }
                if let r = store.contextReading {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(r.remainingPercent)%").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        Text("contexto").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
        }
    }

    private func lane(agent: String, tint: Color, st: PetState, tick: Int, now: Date) -> some View {
        let heat = TouchBarPulse.lanes(events: state.events, agent: agent, now: now)
        let working = st == .thinking || st == .tool || st == .starting || st == .waiting
        return HStack(spacing: 6) {
            Canvas { gc, size in
                if agent == "claude" {
                    var pose = PetPose(); pose.dy = working ? -CGFloat(abs(sin(Double(tick) * 0.9))) * 0.8 : 0
                    PetFace.draw(&gc, size: size, pixels: Sprite.pixels(st, tick: tick), pose: pose)
                } else {
                    let u = min(size.width / 18, size.height / 21)
                    let ox = (size.width - 18 * u) / 2
                    let face: CodexAvatar.Face = {
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
                        gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
                    }
                }
            }
            .frame(width: 26, height: 26)
            Canvas { gc, size in
                let w = size.width / CGFloat(heat.count)
                for (i, h) in heat.enumerated() {
                    let bar = max(2, size.height * CGFloat(h))
                    let age = Double(i) / Double(heat.count)
                    gc.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w + 0.5, y: size.height - bar, width: w - 1.5, height: bar), cornerRadius: 1),
                            with: .color(tint.opacity(h == 0 ? 0.18 : 0.35 + 0.65 * age)))
                }
            }
            .frame(width: 110, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(agent).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text(TouchBarPulse.word(st)).font(.system(size: 9, design: .monospaced)).foregroundColor(working ? tint : .white.opacity(0.5))
            }
            .frame(width: 62, alignment: .leading)
        }
    }
}

// MARK: la barra

extension NSTouchBarItem.Identifier {
    static let pulse = NSTouchBarItem.Identifier("claudepet.pulse")
    static let note = NSTouchBarItem.Identifier("claudepet.note")
    static let askLabel = NSTouchBarItem.Identifier("claudepet.ask.label")
    static let askSlide = NSTouchBarItem.Identifier("claudepet.ask.slide")
    static let askDeny = NSTouchBarItem.Identifier("claudepet.ask.deny")
}

@MainActor final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let store: PetStore
    private let state = TouchBarState()
    private lazy var pulseBar: NSTouchBar = makeBar([.pulse, .flexibleSpace, .note])
    private lazy var askBar: NSTouchBar = makeBar([.askLabel, .askSlide, .askDeny])
    private var shown: TouchBarPulse.Mode?
    private var timer: Timer?
    private var currentAsk: PermissionAsk?
    private var askRisk: PermissionRisk = .low
    private weak var slider: NSSliderTouchBarItem?

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
        let mode = TouchBarPulse.mode(pendingPermissions: store.permissionAsks.count)
        let ask = store.permissionAsks.first
        if mode == .permission, ask?.id != currentAsk?.id {
            currentAsk = ask
            if let a = ask { askRisk = PermissionRiskClassifier.classify(tool: a.tool, detail: a.detail, project: a.project).risk }
            askBar = makeBar([.askLabel, .askSlide, .askDeny])      // barra nueva: el deslizador vuelve a cero y el texto se rehace
            shown = nil
        }
        if mode != .permission { currentAsk = nil }
        guard mode != shown else { return }
        dismiss()
        present(mode == .permission ? askBar : pulseBar)
        shown = mode
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
        let cls = NSTouchBar.self as AnyObject
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let sel = NSSelectorFromString(name)
            if cls.responds(to: sel) {
                if shown == .permission { _ = cls.perform(sel, with: askBar) } else { _ = cls.perform(sel, with: pulseBar) }
                return
            }
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch id {
        case .pulse:
            let item = NSCustomTouchBarItem(identifier: id)
            let host = NSHostingView(rootView: TouchBarPulseView(store: store, state: state))
            host.widthAnchor.constraint(equalToConstant: 560).isActive = true
            item.view = host
            return item
        case .note:
            let item = NSCustomTouchBarItem(identifier: id)
            item.view = NSButton(title: "nota para los agentes", target: self, action: #selector(newNote))
            return item
        case .askLabel:
            let item = NSCustomTouchBarItem(identifier: id)
            let more = store.permissionAsks.count > 1 ? "  +\(store.permissionAsks.count - 1)" : ""
            let isPlan = currentAsk?.tool == "ExitPlanMode"
            let target = (currentAsk?.detail ?? "").replacingOccurrences(of: "\n", with: " ")
            let text = NSTextField(labelWithString: "\(isPlan ? "plan" : currentAsk?.tool ?? "permiso") \(target.prefix(48))\(more)")
            text.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            text.textColor = askRisk == .high ? NSColor(srgbRed: 1, green: 0.45, blue: 0.4, alpha: 1) : .white
            text.lineBreakMode = .byTruncatingTail
            text.widthAnchor.constraint(equalToConstant: 300).isActive = true
            item.view = text
            return item
        case .askSlide:
            let item = NSSliderTouchBarItem(identifier: id)
            item.slider.minValue = 0; item.slider.maxValue = 1; item.slider.doubleValue = 0
            item.slider.isContinuous = false
            item.slider.trackFillColor = askRisk == .high ? NSColor(srgbRed: 1, green: 0.45, blue: 0.4, alpha: 1) : NSColor(srgbRed: 0.88, green: 0.51, blue: 0.31, alpha: 1)
            item.label = askRisk == .high ? "a fondo para permitir" : "desliza para permitir"
            item.target = self; item.action = #selector(slid(_:))
            item.view.widthAnchor.constraint(equalToConstant: 300).isActive = true
            slider = item
            return item
        case .askDeny:
            let item = NSCustomTouchBarItem(identifier: id)
            item.view = NSButton(title: "denegar", target: self, action: #selector(deny))
            return item
        default: return nil
        }
    }

    @objc private func slid(_ sender: NSSliderTouchBarItem) {
        guard let ask = currentAsk else { return }
        switch TouchBarPulse.slideOutcome(value: sender.slider.doubleValue, risk: askRisk) {
        case .allow: store.answerPermission(ask.id, .allow)
        case .reset: NSAnimationContext.runAnimationGroup { $0.duration = 0.25; sender.slider.animator().doubleValue = 0 }
        }
    }

    @objc private func deny() { if let ask = currentAsk { store.answerPermission(ask.id, .deny) } }
    @objc private func newNote() { BrainEditorWindow.present(project: store.terminalProject, note: nil) }
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
        func ev(_ agent: String, ago: TimeInterval) -> PetMemoryEvent { PetMemoryEvent(id: UUID(), at: now.addingTimeInterval(-ago), kind: .tool, agent: agent, project: "p") }
        let events = [ev("claude", ago: 10), ev("claude", ago: 20), ev("claude", ago: 400), ev("codex", ago: 30), ev("claude", ago: 60 * 60 * 2)]
        let c = TouchBarPulse.lanes(events: events, agent: "claude", now: now)
        check("hay una columna por cada 2 minutos", c.count == TouchBarPulse.columns)
        check("lo de ahora cae en la ultima columna y es el maximo", c.last == 1 && c.dropLast().allSatisfy { $0 <= 1 })
        check("lo de hace 7 minutos cae mas atras", c[TouchBarPulse.columns - 4] == 0.5)
        check("lo de hace mas de 48 minutos no cuenta", c.filter { $0 > 0 }.count == 2)
        check("cada agente tiene su pista", TouchBarPulse.lanes(events: events, agent: "codex", now: now).last == 1)
        check("sin eventos todo queda a cero", TouchBarPulse.lanes(events: [], agent: "claude", now: now).allSatisfy { $0 == 0 })
        check("con permisos pendientes la barra cambia a deslizador", TouchBarPulse.mode(pendingPermissions: 1) == .permission && TouchBarPulse.mode(pendingPermissions: 0) == .pulse)
        check("a medio camino el deslizador vuelve", TouchBarPulse.slideOutcome(value: 0.5, risk: .low) == .reset)
        check("al final permite", TouchBarPulse.slideOutcome(value: 0.95, risk: .low) == .allow)
        check("con riesgo alto no basta casi llegar", TouchBarPulse.slideOutcome(value: 0.95, risk: .high) == .reset && TouchBarPulse.slideOutcome(value: 1, risk: .high) == .allow)
        print(ok ? "TOUCHBAR OK" : "TOUCHBAR FALLO")
        return ok
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-touchbar <ruta.png>`: la tira del pulso a su tamano real (30 pt de alto) sobre negro.
    static func touchBar(to path: String) {
        let store = PetStore.shared
        let state = TouchBarState()
        let now = Date()
        state.events = (0..<60).map { i in PetMemoryEvent(id: UUID(), at: now.addingTimeInterval(-Double(i * i % 2600)), kind: .tool, agent: i % 3 == 0 ? "codex" : "claude", project: "demo") }
        let view = TouchBarPulseView(store: store, state: state).frame(width: 560, height: 30).padding(.horizontal, 10).background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 4
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
