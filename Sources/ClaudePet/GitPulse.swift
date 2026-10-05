import Foundation
import Darwin

enum GitPulse {
    static let outputLimit = 4 * 1024 * 1024
    static let entryLimit = 20_000

    static func parse(_ data: Data, branch fallbackBranch: String = "", limited: Bool = false) -> GitHealth {
        let records = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        var health = GitHealth(branch: fallbackBranch, available: true, limited: limited)
        var index = 0
        while index < records.count {
            let record = records[index]
            if record.hasPrefix("## ") {
                health.branch = branchName(from: record)
                index += 1
                continue
            }
            guard record.count >= 2 else { index += 1; continue }
            let status = String(record.prefix(2))
            let conflict = ["UU", "AA", "DD", "AU", "UA", "DU", "UD"].contains(status)
            health.affected += 1
            if status == "??" {
                health.untracked += 1
            } else if conflict {
                health.conflicts += 1
            } else {
                if status.first != " " && status.first != "?" { health.staged += 1 }
                if status.last != " " { health.changed += 1 }
            }
            if status.first == "R" || status.first == "C" || status.last == "R" || status.last == "C" {
                index += 1 // porcelain -z entrega la ruta origen en el registro siguiente
            }
            index += 1
        }
        return health
    }

    static func scan(_ workspace: String, timeout: TimeInterval = 10) -> GitHealth {
        var isDirectory: ObjCBool = false
        guard workspace.hasPrefix("/"),
              FileManager.default.fileExists(atPath: workspace, isDirectory: &isDirectory),
              isDirectory.boolValue else { return GitHealth() }

        guard let first = status(workspace: workspace, includeUntracked: true, timeout: timeout) else { return GitHealth() }
        let entries = first.data.reduce(into: 0) { if $1 == 0 { $0 += 1 } }
        if first.truncated || entries > entryLimit {
            guard let compact = status(workspace: workspace, includeUntracked: false, timeout: timeout) else { return GitHealth() }
            return parse(compact.data, limited: true)
        }
        return parse(first.data)
    }

    static func runForTest(executable: String, arguments: [String], timeout: TimeInterval) -> Bool {
        run(executable: executable, arguments: arguments, timeout: timeout)?.status == 0
    }

    private static func status(workspace: String, includeUntracked: Bool, timeout: TimeInterval) -> (data: Data, truncated: Bool)? {
        let args = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", workspace,
                    "status", "-b", "--porcelain=v1", "-z",
                    includeUntracked ? "--untracked-files=normal" : "--untracked-files=no"]
        guard let result = run(executable: "/usr/bin/git", arguments: args, timeout: timeout), result.status == 0 else { return nil }
        return (result.data, result.truncated)
    }

    private static func branchName(from header: String) -> String {
        let value = String(header.dropFirst(3))
        if value.hasPrefix("No commits yet on ") { return String(value.dropFirst("No commits yet on ".count)) }
        if value.hasPrefix("Initial commit on ") { return String(value.dropFirst("Initial commit on ".count)) }
        return value.components(separatedBy: "...").first ?? value
    }

    private static func run(executable: String, arguments: [String], timeout: TimeInterval) -> (data: Data, truncated: Bool, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let capture = CappedOutput(limit: outputLimit)
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { reader.leave() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                capture.append(chunk)
            }
        }
        guard (try? process.run()) != nil else {
            try? output.fileHandleForWriting.close()
            _ = reader.wait(timeout: .now() + 1)
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.25)
            while process.isRunning && Date() < grace { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForWriting.close()
        _ = reader.wait(timeout: .now() + 1)
        let result = capture.result
        return (result.data, result.truncated, process.terminationStatus)
    }
}

private final class CappedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var didTruncate = false

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let room = max(0, limit - data.count)
        if room > 0 { data.append(chunk.prefix(room)) }
        if chunk.count > room { didTruncate = true }
    }

    var result: (data: Data, truncated: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (data, didTruncate)
    }
}
