import Foundation
enum ApprovalScopeSelfTest {
    static func run() -> Bool {
        let checks = ApprovalScope.allCases.count == 4 && ApprovalScope.project.duration == 1800 && ApprovalScope.session.duration == 28800 && ApprovalScope.once.duration == nil && ApprovalScope.always.isAllowed(for: .low) && !ApprovalScope.always.isAllowed(for: .high)
        print(checks ? "ALCANCE OK" : "ALCANCE FALLOS"); return checks
    }
}
