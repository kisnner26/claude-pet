import Foundation

public let vistoServiceType = "_claudepet-visto._tcp"

/// Un permiso que Claude Code espera. `detail` ya llega recortado; `risk` es «bajo», «medio» o «alto»: el alto solo se puede denegar desde fuera.
public struct Ask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var tool: String
    public var project: String
    public var detail: String
    public var risk: String
    public var expires: Date
    public init(id: String, tool: String, project: String, detail: String, risk: String, expires: Date) {
        self.id = id; self.tool = tool; self.project = project; self.detail = detail; self.risk = risk; self.expires = expires
    }
    public var canAllow: Bool { risk != "alto" }
    public func isExpired(_ now: Date = Date()) -> Bool { expires <= now }
}

/// Consumo del plan de Claude (límite de 5 horas y semanal), tal como lo ve claude pet.
public struct PlanWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(usedPercent: Double, resetsAt: Date?) { self.usedPercent = usedPercent; self.resetsAt = resetsAt }
    public func effectivePercent(_ now: Date = Date()) -> Double {
        if let r = resetsAt, r <= now { return 0 }
        return min(100, max(0, usedPercent))
    }
    public func remaining(_ now: Date = Date()) -> Int { Int((100 - effectivePercent(now)).rounded()) }
}

public struct PlanSnapshot: Codable, Equatable, Sendable {
    public var five: PlanWindow?
    public var week: PlanWindow?
    public init(five: PlanWindow?, week: PlanWindow?) { self.five = five; self.week = week }
}

/// Estado de un agente (claude o codex) tal como lo ve claude pet. `state` es idle, starting, thinking, tool, waiting, done o error.
public struct AgentInfo: Codable, Equatable, Sendable, Identifiable {
    public var agent: String
    public var state: String
    public var project: String
    public var since: Date
    /// Lo que queda de la ventana de contexto, 0-100, si se conoce.
    public var contextRemaining: Int?
    public var id: String { agent }
    public init(agent: String, state: String, project: String, since: Date, contextRemaining: Int?) {
        self.agent = agent; self.state = state; self.project = project; self.since = since; self.contextRemaining = contextRemaining
    }
    public var isBusy: Bool { ["starting", "thinking", "tool"].contains(state) }
}

/// Un paso reciente de un agente (herramienta y objetivo). Nunca lleva el contenido de los archivos.
public struct Step: Codable, Equatable, Sendable, Identifiable {
    public var agent: String
    public var tool: String
    public var target: String
    public var at: Date
    public var delta: String
    public var id: String { "\(agent)\(tool)\(target)\(Int(at.timeIntervalSince1970))" }
    public init(agent: String, tool: String, target: String, at: Date, delta: String) { self.agent = agent; self.tool = tool; self.target = target; self.at = at; self.delta = delta }
}

public struct QItem: Codable, Equatable, Sendable {
    public var header: String
    public var question: String
    public var options: [String]
    public var descriptions: [String]
    public var multi: Bool
    public init(header: String, question: String, options: [String], descriptions: [String], multi: Bool) {
        self.header = header; self.question = question; self.options = options; self.descriptions = descriptions; self.multi = multi
    }
}

/// Una pregunta de Claude con opciones (AskUserQuestion). Se responde con los índices elegidos, nunca con texto libre.
public struct QAsk: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var project: String
    public var items: [QItem]
    public init(id: String, project: String, items: [QItem]) { self.id = id; self.project = project; self.items = items }
}

/// Todo lo que muestra el reloj cuando no habla directo con claude pet: lo retransmite el iPhone.
public struct VistoSnapshot: Codable, Equatable, Sendable {
    public var asks: [Ask] = []
    public var questions: [QAsk] = []
    public var agents: [AgentInfo] = []
    public var feed: [Step] = []
    public var plan: PlanSnapshot?
    public var host: String?
    public var focus = false
    public init() {}
}

public enum VistoMessage: Codable, Equatable, Sendable {
    case hello(device: String)
    case ask(Ask)
    case gone(id: String)
    case answer(id: String, allow: Bool)
    case refused(id: String, why: String)
    case plan(PlanSnapshot?)
    case host(name: String)
    case agents([AgentInfo])
    case feed([Step])
    /// Un agente terminó o falló: `kind` es «done» o «error».
    case event(kind: String, agent: String, project: String, seconds: Int)
    case question(QAsk)
    case questionGone(id: String)
    case reply(id: String, picks: [[Int]])
    /// Modo foco: claude pet lo difunde y los dispositivos lo piden.
    case focus(Bool)
}

struct Envelope: Codable { var seq: UInt64; var message: VistoMessage }
