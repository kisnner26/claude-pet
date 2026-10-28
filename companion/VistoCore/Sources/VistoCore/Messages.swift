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

public enum VistoMessage: Codable, Equatable, Sendable {
    case hello(device: String)
    case ask(Ask)
    case gone(id: String)
    case answer(id: String, allow: Bool)
    case refused(id: String, why: String)
    case plan(PlanSnapshot?)
    case host(name: String)
}

struct Envelope: Codable { var seq: UInt64; var message: VistoMessage }
