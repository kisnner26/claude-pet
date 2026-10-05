import Foundation
import SwiftUI

@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore()

    @Published private(set) var state: PetState = .idle
    @Published private(set) var tool: String = ""
    @Published private(set) var bridgeOK = false
    @Published private(set) var busOK = false
    @Published private(set) var peer: Peer?
    @Published private(set) var gameActive = false
    @Published var stageMirrored = false
    /// Interruptor general: apagado, la mascota queda quieta y no hay partidos.
    @Published var animationsEnabled: Bool = UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(animationsEnabled, forKey: "animationsEnabled"); syncGame() }
    }
    @Published var footballEnabled: Bool = UserDefaults.standard.object(forKey: "footballEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(footballEnabled, forKey: "footballEnabled"); syncGame() }
    }
    @Published var skin: Skin = Skin(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .block {
        didSet { Sprite.skin = skin; UserDefaults.standard.set(skin.rawValue, forKey: "skin") }
    }
    @Published private(set) var activity: Activity?
    @Published var showBubble: Bool = UserDefaults.standard.object(forKey: "showBubble") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBubble, forKey: "showBubble") }
    }
    /// Archivos, descripciones y programa de un comando. Solo local: nunca sale por el pet bus.
    @Published var showDetail: Bool = UserDefaults.standard.object(forKey: "showDetail") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDetail, forKey: "showDetail"); refresh() }
    }
    /// Por defecto el nombre del proyecto NO sale de la app.
    @Published var shareProject: Bool = UserDefaults.standard.bool(forKey: "shareProject") {
        didSet { UserDefaults.standard.set(shareProject, forKey: "shareProject"); publish(event: nil) }
    }

    private struct Info { var state: PetState; var tool: String; var project: String; var detail: String; var origin: String; var prompt: String; var todo: String; var at: Date }
    private var sessions: [String: Info] = [:]
    private var manual: (PetState, Date)?
    private var project = ""
    private var timer: Timer?
    private var beat: Timer?
    private var greetUntil = Date.distantPast
    private var cheerUntil = Date.distantPast
    private var concernUntil = Date.distantPast
    private let peerTTL: TimeInterval = 25
    /// Partido de futbol entre Claude y el mini del par (solo visual, deducido de presencia y estado).
    private let game = FootballGame(config: .fromEnvironment())
    private var peerStateKnown = false

    init() {
        Sprite.skin = skin
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
        beat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publish(event: nil) }
        }
    }

    func setBridge(_ ok: Bool) { bridgeOK = ok }
    func setBus(_ ok: Bool) { busOK = ok; if ok { publish(event: "appeared") } }
    func shutdownBus() { publish(event: "left", wait: true) }

    // MARK: hooks de Claude Code

    func apply(_ e: PetEvent) {
        switch e.kind {
        case .end: sessions[e.session] = nil
        case .state(let s):
            // la tarea persiste durante la sesion: tu ultimo mensaje y la tarea en curso de la lista
            var prompt = sessions[e.session]?.prompt ?? "", todo = sessions[e.session]?.todo ?? ""
            if e.task.hasPrefix("p:") { prompt = String(e.task.dropFirst(2)); todo = "" }
            if e.task.hasPrefix("t:") { todo = String(e.task.dropFirst(2)) }
            sessions[e.session] = Info(state: s, tool: (s == .tool || s == .waiting) ? e.tool : "", project: e.project,
                                       detail: e.detail, origin: e.origin, prompt: prompt, todo: todo, at: Date())
        }
        refresh()
    }

    func preview(_ s: PetState) { manual = (s, Date()); refresh() }

    // MARK: pet bus

    func receive(line: String) {
        guard let m = PetBus.decode(line) else { return }
        let now = Date()
        let old = peer
        if let o = old, o.id == m.id, m.ts < o.lastTs { return }   // mensaje viejo fuera de orden
        if m.event == "left" { if peer?.id == m.id { peer = nil }; return }
        let known = PetState(rawValue: m.state)
        peerStateKnown = known != nil                              // desconocido: hay presencia, pero no cuenta como idle para el partido
        let st = known ?? .idle
        let proj = m.project.map { String($0.prefix(40)) }
        peer = Peer(id: m.id, state: st, project: proj, lastTs: m.ts, seen: now)
        if old == nil || m.event == "appeared" { greetUntil = now.addingTimeInterval(3) }
        switch m.event {
        case "finished": cheerUntil = now.addingTimeInterval(2.5)
        case "error": concernUntil = now.addingTimeInterval(3)
        default: break
        }
        syncGame()
    }

    /// Reduce movimiento del sistema (o forzado con CLAUDE_PET_REDUCE_MOTION=1 para pruebas).
    var gameStart: Date? { game.startedAt }
    var reduceMotion: Bool {
        ProcessInfo.processInfo.environment["CLAUDE_PET_REDUCE_MOTION"] == "1"
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: disparadores manuales (menu y `ClaudePet --trigger <nombre>`)

    static let triggerNames = ["football", "greet", "cheer", "concern"]
    private var demoUntil = Date.distantPast

    /// Lanza una animacion al instante, sin esperar ni exigir a Codex.
    func trigger(_ name: String) {
        guard animationsEnabled else { return }
        let now = Date()
        switch name {
        case "football":
            game.forceStart(now: now)
            if game.isActive != gameActive { gameActive = game.isActive }
            return
        case "greet": greetUntil = now.addingTimeInterval(3)
        case "cheer": cheerUntil = now.addingTimeInterval(2.5)
        case "concern": concernUntil = now.addingTimeInterval(3)
        default: return
        }
        demoUntil = now.addingTimeInterval(3)       // muestra al companero aunque Codex no este
        objectWillChange.send()
    }

    private func syncGame() {
        guard animationsEnabled, footballEnabled || game.forced else {
            game.cancel()
            if gameActive { gameActive = false }
            return
        }
        game.update(now: Date(), claude: state, peer: peerStateKnown ? peer?.state : nil)
        if game.isActive != gameActive { gameActive = game.isActive }
    }

    func cue(at date: Date) -> PeerCue? {
        guard peer != nil || date < demoUntil || game.isActive else { return nil }
        let p = peer ?? Peer(id: "demo", state: .idle, project: nil, lastTs: 0, seen: date)
        let frame = game.elapsed(at: date).flatMap { FootballChoreography.frame(elapsed: $0, reduceMotion: reduceMotion) }
        return PeerCue(state: p.state, greet: date < greetUntil, cheer: date < cheerUntil, concern: date < concernUntil, game: frame)
    }

    private var lastPublished: (PetState, String)?

    private func publish(event: String?, wait: Bool = false) {
        guard busOK || event == "left" else { return }
        let proj = shareProject && !project.isEmpty ? project : nil
        let msg = BusMessage(v: PetBus.version, id: PetBus.selfID, state: state.rawValue,
                             project: proj, ts: Date().timeIntervalSince1970, event: event)
        PetBus.publish(msg, wait: wait)
        lastPublished = (state, project)
    }

    /// Titulo = lo que hace ahora, lo mas exacto posible. Subtitulo = la tarea de fondo.
    static func describe(_ s: PetState, tool: String, detail: String, task: String) -> (String, String) {
        func action() -> String {
            let d = detail
            switch tool {
            case "Bash":
                if d.hasPrefix("$ ") { return "Ejecutando " + d.dropFirst(2) }
                return d.isEmpty ? "Ejecutando un comando" : d
            case "Read": return d.isEmpty ? "Leyendo un archivo" : "Leyendo " + d
            case "Edit", "MultiEdit": return d.isEmpty ? "Editando un archivo" : "Editando " + d
            case "Write": return d.isEmpty ? "Escribiendo un archivo" : "Escribiendo " + d
            case "NotebookEdit": return d.isEmpty ? "Editando un notebook" : "Editando " + d
            case "Grep": return d.isEmpty ? "Buscando en el codigo" : "Buscando \u{AB}\(d)\u{BB}"
            case "Glob": return d.isEmpty ? "Buscando archivos" : "Buscando archivos \u{AB}\(d)\u{BB}"
            case "WebFetch": return d.isEmpty ? "Consultando una pagina" : "Consultando " + d
            case "WebSearch": return d.isEmpty ? "Buscando en la web" : "Buscando en la web: " + d
            case "Task", "Agent": return d.isEmpty ? "Delegando a un subagente" : "Subagente: " + d
            case "TodoWrite", "TaskUpdate", "TaskCreate": return task.isEmpty ? "Actualizando tareas" : task
            case "": return task.isEmpty ? "Trabajando" : task
            default:
                if tool.hasPrefix("mcp__") {
                    let parts = tool.components(separatedBy: "__")
                    let name = parts.count > 2 ? parts[2] : tool
                    return d.isEmpty ? "Usando " + name : "\(name): \(d)"
                }
                return d.isEmpty ? tool : "\(tool): \(d)"
            }
        }
        switch s {
        case .starting: return ("Iniciando sesion", "")
        case .thinking: return (task.isEmpty ? "Pensando" : task, task.isEmpty ? "" : "Pensando")
        case .tool: return (action(), task)
        case .waiting: return (action(), "Esperando tu aprobacion")
        case .done: return (task.isEmpty ? "Termino" : task, "Termino")
        case .error: return (task.isEmpty ? "Algo fallo" : task, "Algo fallo")
        case .idle: return ("", "")
        }
    }

    private func eventFor(_ s: PetState) -> String? {
        switch s {
        case .starting, .thinking, .tool: return "working"
        case .waiting: return "waiting"
        case .done: return "finished"
        case .error: return "error"
        case .idle: return nil
        }
    }

    // MARK: ciclo

    private func prune() {
        let now = Date()
        for (k, v) in sessions {
            let age = now.timeIntervalSince(v.at)
            if (v.state == .done && age > 5) || (v.state == .error && age > 8) || age > 900 { sessions[k] = nil }
        }
        if let m = manual, now.timeIntervalSince(m.1) > 5 { manual = nil }
        if let p = peer, now.timeIntervalSince(p.seen) > peerTTL { peer = nil }   // el par desaparecio sin avisar
        refresh()
    }

    private func refresh() {
        if let m = manual {
            state = m.0; tool = ""
            activity = m.0 == .idle ? nil : Activity(title: "Prueba de estado", subtitle: m.0.label.capitalized, origin: "")
            syncGame()
            return
        }
        let top = sessions.values.max { a, b in
            a.state.priority != b.state.priority ? a.state.priority < b.state.priority : a.at < b.at
        }
        let new = top?.state ?? .idle
        let newTool = top?.tool ?? ""
        let newProject = top?.project ?? ""
        if newTool != tool { tool = newTool }
        let act: Activity? = {
            guard let t = top, new != .idle else { return nil }
            let task = showDetail ? (t.todo.isEmpty ? t.prompt : t.todo) : ""
            let d = Self.describe(new, tool: t.tool, detail: showDetail ? t.detail : "", task: task)
            return Activity(title: d.0, subtitle: d.1, origin: t.origin)
        }()
        if act != activity { activity = act }
        let changed = new != state || newProject != project
        project = newProject
        if new != state { state = new }
        if changed { publish(event: eventFor(new)) }
        syncGame()
    }
}
