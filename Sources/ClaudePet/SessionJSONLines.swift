import Foundation

/// Lectura acotada: una imagen enorme no invalida el resto del chat.
enum SessionJSONLines {
    struct Report { var skipped = 0; var limited = false }
    @discardableResult
    static func read(_ url: URL, byteLimit: Int = .max, visit: ([String: Any]) -> Void) throws -> Report {
        let handle: FileHandle
        var process: Process?
        if url.pathExtension == "zst" {
            guard let executable = AgentLocator.find("zstd") else { throw LocalAgentSessionError.compressedUnavailable }
            let task = Process()
            let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = ["-q", "-d", "-c", "--", url.path]
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try task.run()
            handle = pipe.fileHandleForReading
            process = task
        } else { handle = try FileHandle(forReadingFrom: url) }
        defer {
            try? handle.close()
            if let process {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }
        }
        var report = Report()
        var pending = Data()
        var discarding = false
        var consumed = 0
        while consumed < byteLimit {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: min(65_536, byteLimit - consumed)), !chunk.isEmpty else { break }
            consumed += chunk.count
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 10)
                let end = newline ?? chunk.endIndex
                if !discarding {
                    if pending.count + end - start > 16 * 1024 * 1024 {
                        pending.removeAll(keepingCapacity: false)
                        discarding = true
                        report.skipped += 1
                    } else { pending.append(contentsOf: chunk[start..<end]) }
                }
                if let newline {
                    if !discarding, let row = object(pending) { visit(row) }
                    pending.removeAll(keepingCapacity: true)
                    discarding = false
                    start = newline + 1
                } else { break }
            }
        }
        report.limited = consumed >= byteLimit
        if !report.limited, !discarding, let row = object(pending) { visit(row) }
        if !report.limited, let process {
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LocalAgentSessionError.unreadable }
        }
        return report
    }
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
