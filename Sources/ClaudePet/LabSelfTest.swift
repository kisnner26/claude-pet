import Foundation

/// `ClaudePet --selftest-lab`: las reglas de las herramientas incluidas y un lanzamiento real de cada una con node, abriendo su pagina por HTTP.
@MainActor
enum LabSelfTest {
    static func run(root: String) -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        typealias R = LabRules

        check("version de node", R.nodeVersion(from: "v26.8.1\n")! == (26, 8, 1) && R.nodeVersion(from: "v20.0.0")! == (20, 0, 0))
        check("version de node rara se rechaza", R.nodeVersion(from: "") == nil && R.nodeVersion(from: "node 20") == nil && R.nodeVersion(from: "v20.1") == nil && R.nodeVersion(from: "va.b.c") == nil)
        check("node 20 o superior", R.nodeSupported((20, 0, 0)) && R.nodeSupported((26, 8, 1)) && !R.nodeSupported((18, 19, 0)) && !R.nodeSupported(nil))
        check("hay candidatos de node y el de la variable va primero", R.nodeCandidates(env: ["CLAUDE_PET_NODE": "/x/node"]).first == "/x/node" && R.nodeCandidates(env: [:]).contains("/opt/homebrew/bin/node"))
        check("carpeta de cada herramienta", R.targetDirectory(.galaxy, workspace: "/a/b/proyecto") == "/a/b/proyecto" && R.targetDirectory(.city, workspace: "/a/b/proyecto") == "/a/b" && R.targetDirectory(.radar, workspace: "/a/b") == nil
              && R.targetDirectory(.galaxy, workspace: "") == nil && R.targetDirectory(.city, workspace: "") == nil)
        check("argumentos con puerto y sin abrir el navegador", R.arguments(tool: .galaxy, root: "/r", directory: "/p", port: 4950) == ["/r/galaxia/bin/galaxia.js", "/p", "--port", "4950", "--no-open"]
              && R.arguments(tool: .radar, root: "/r", directory: nil, port: 4848) == ["/r/radar/bin/radar.js", "--port", "4848", "--no-open"])
        check("puerto libre salta los ocupados", R.freePort(from: 4949, isFree: { $0 >= 4952 }) == 4952 && R.freePort(from: 4949, tries: 3, isFree: { _ in false }) == nil)
        check("un puerto ocupado de verdad se detecta", { let p = 34_000 + Int.random(in: 0..<2_000); return R.portIsFree(p) }())
        check("la direccion solo se acepta si es local", R.url(in: "galaxia de x en http://127.0.0.1:4950/")?.port == 4950 && R.url(in: "http://evil.example:4950/") == nil && R.url(in: "http://localhost:4950/") == nil && R.url(in: "sin url") == nil)
        check("encuentra las herramientas incluidas", R.toolsRoot(resources: nil, env: ["CLAUDE_PET_TOOLS": root]) == root)
        check("cada herramienta tiene titulo, simbolo y puerto propio", Set(LabTool.allCases.map(\.defaultPort)).count == 3 && LabTool.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty && !$0.detail.isEmpty })

        let lab = LabLauncher.shared
        guard lab.nodePath != nil else { print("(node 20+ no disponible: se omiten los lanzamientos reales)"); print(failures == 0 ? "LABORATORIO OK" : "LABORATORIO \(failures) FALLOS"); return failures == 0 }
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var report: [String] = []
        let repo = FileManager.default.currentDirectoryPath
        Task { @MainActor in
            let session = URLSession(configuration: .ephemeral)
            for tool in LabTool.allCases {
                let r = await lab.launch(tool, workspace: repo, root: root)
                guard case .started(let url) = r else { report.append("no arranca \(tool.rawValue): \(r)"); continue }
                if let (data, resp) = try? await session.data(from: url), (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 200 { } else { report.append("no responde \(tool.rawValue)") }
                if case .reused = await lab.launch(tool, workspace: repo, root: root) { } else { report.append("no reutiliza \(tool.rawValue)") }
                if !lab.isRunning(tool) { report.append("\(tool.rawValue) no figura corriendo") }
                lab.stop(tool)
                try? await Task.sleep(nanoseconds: 300_000_000)
                if lab.isRunning(tool) { report.append("\(tool.rawValue) no se detuvo") }
            }
            let bad = await lab.launch(.galaxy, workspace: "/no/existe/nada", root: root)
            if case .failure = bad { } else { report.append("una carpeta inexistente deberia fallar") }
            lab.stopAll()
            sem.signal()
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        report.forEach { print("FALLO \($0)") }
        failures += report.count
        print(failures == 0 ? "LABORATORIO OK" : "LABORATORIO \(failures) FALLOS")
        return failures == 0
    }
}
