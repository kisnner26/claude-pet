import Foundation
enum ApprovalScopeSelfTest {
    static func run() -> Bool {
        var checks = [ApprovalScope.allCases.count == 4, ApprovalScope.project.duration == 1800, ApprovalScope.session.duration == 28800, ApprovalScope.once.duration == nil, ApprovalScope.always.isAllowed(for: .low), !ApprovalScope.always.isAllowed(for: .high), ApprovalScope(rawValue: "una vez") == .once]
        let ok = checks.allSatisfy { $0 }
        print(ok ? "ALCANCE OK" : "ALCANCE FALLOS"); return ok
    }
}
