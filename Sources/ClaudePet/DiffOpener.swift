import AppKit
import Foundation

/// Abre el diff del proyecto. El trabajo corre fuera del hilo principal, la salida de git se lee a
/// medida que llega (si no, un diff grande llena la tuberia y git se queda esperando para siempre),
/// con tope de tamano y de tiempo, y sin ejecutar nada que defina la configuracion del repo.
enum DiffOpener {
    static let maxBytes = 5 * 1024 * 1024
    static let timeout: TimeInterval = 20

    static var outputURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claude-pet-review.diff")
    }

    static func open(workspace: String, path: String? = nil) {
        Task.detached(priority: .utility) {
            guard let url = await render(workspace: workspace, path: path) else { return }
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
    }

    static func openChange(workspace: String, file: ChangedFile) {
        if file.untracked {
            openFile(workspace: workspace, path: file.path)
        } else {
            Task.detached(priority: .utility) {
                guard let url = await render(workspace: workspace, path: file.path, includeStaged: true) else { return }
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
        }
    }

    private static func openFile(workspace: String, path: String) {
        guard ChangeMap.isSafe(path) else { return }
        let root = URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else { return }
        _ = NSWorkspace.shared.open(file)
    }

    static func render(workspace: String, path: String? = nil, includeStaged: Bool = false) async -> URL? {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async {
                c.resume(returning: renderSync(workspace: workspace, path: path, includeStaged: includeStaged))
            }
        }
    }

    /// El diff sin commitear para enviarlo a otro agente: mismas defensas que `renderSync`
    /// (sin drivers ni filtros del repo), con un tope propio de tamano. nil si no es un repo usable.
    static func capture(workspace: String, maxBytes: Int, timeout: TimeInterval = 20) -> (data: Data, truncated: Bool)? {
        var isDir: ObjCBool = false
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace, isDirectory: &isDir), isDir.boolValue else { return nil }
        let arguments = ["-C", workspace, "-c", "core.fsmonitor=false", "-c", "core.pager=cat",
                         "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--"]
        guard let result = GitPulse.run(arguments: arguments, timeout: timeout, limit: maxBytes), result.status == 0 else { return nil }
        return (result.data, result.truncated)
    }

    static func renderSync(workspace: String, path: String? = nil, includeStaged: Bool = false) -> URL? {
        var isDir: ObjCBool = false
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace, isDirectory: &isDir), isDir.boolValue else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // --no-ext-diff / --no-textconv / fsmonitor desactivado: ni drivers ni filtros definidos por el repo
        var arguments = ["-C", workspace, "-c", "core.fsmonitor=false", "-c", "core.pager=cat", "diff"]
        if includeStaged {
            let hasHead = GitPulse.run(arguments: ["-C", workspace, "rev-parse", "--verify", "HEAD"], timeout: 2)?.status == 0
            arguments.append(hasHead ? "HEAD" : "--cached")
        }
        arguments += ["--no-ext-diff", "--no-textconv", "--no-color", "--"]
        p.arguments = arguments
        if let path {
            guard ChangeMap.isSafe(path) else { return nil }
            p.arguments?.append(path)       // tras `--`: nunca se interpreta como opción
        }
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"; env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }

        var data = Data()
        var truncated = false
        let h = pipe.fileHandleForReading
        while true {
            let chunk = h.availableData          // bloquea hasta que haya datos o EOF
            if chunk.isEmpty { break }
            if data.count + chunk.count > maxBytes {
                data.append(chunk.prefix(maxBytes - data.count)); truncated = true
                p.terminate(); break
            }
            data.append(chunk)
        }
        p.waitUntilExit()

        if data.isEmpty { data = Data("sin cambios sin commitear en el proyecto (git diff)\n".utf8) }
        if truncated { data.append(Data("\n[recortado: el diff supera \(maxBytes / 1024 / 1024) MB]\n".utf8)) }
        let url = outputURL
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)   // puede contener codigo sensible
        return url
    }
}
