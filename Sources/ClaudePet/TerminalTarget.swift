import AppKit

struct TerminalCandidate: Equatable {
    let pid: pid_t
    let app: String
    let title: String
}

enum TerminalTargetResolver {
    static let names = ["terminal", "iterm2", "iterm", "ghostty", "warp", "visual studio code", "code"]

    static func choose(project: String, candidates: [TerminalCandidate]) -> TerminalCandidate? {
        let eligible = candidates.filter { c in
            let app = c.app.lowercased()
            guard names.contains(where: { app == $0 || app.contains($0) }) else { return false }
            guard !project.isEmpty else { return false }
            return c.title.lowercased().contains(project.lowercased())
        }
        return eligible.count == 1 ? eligible[0] : nil
    }

    @MainActor
    static func current(project: String) -> TerminalCandidate? {
        guard !project.isEmpty else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let candidates = windows.compactMap { row -> TerminalCandidate? in
            guard let number = row[kCGWindowOwnerPID as String] as? NSNumber,
                  let title = row[kCGWindowName as String] as? String, !title.isEmpty,
                  let app = apps.first(where: { $0.processIdentifier == number.int32Value })?.localizedName else { return nil }
            return TerminalCandidate(pid: number.int32Value, app: app, title: title)
        }
        return choose(project: project, candidates: candidates)
    }

    @MainActor
    static func focus(project: String) -> Bool {
        guard let target = current(project: project), let app = NSRunningApplication(processIdentifier: target.pid) else { return false }
        return app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }
}
