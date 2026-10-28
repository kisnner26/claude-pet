import Foundation
import AppKit
import Darwin

/// Las tres herramientas del laboratorio, incluidas en la app: galaxia (un repo como estrellas), ciudad (una carpeta de repos como edificios)
/// y radar (sondeo de la red). Son programas de Node sin dependencias que escuchan solo en 127.0.0.1 y no escriben nada; claude pet los
/// lanza, espera a que respondan, abre la pagina y los cierra al salir.
enum LabTool: String, CaseIterable, Identifiable {
    case galaxy = "galaxia", city = "ciudad", radar
    var id: String { rawValue }
    var folder: String { rawValue }
    var title: String { switch self { case .galaxy: return "galaxia del repo"; case .city: return "ciudad de proyectos"; case .radar: return "radar de red" } }
    var symbol: String { switch self { case .galaxy: return "sparkles"; case .city: return "building.2"; case .radar: return "dot.radiowaves.left.and.right" } }
    var detail: String {
        switch self {
        case .galaxy: return "cada archivo del proyecto es una estrella: su historial decide el tamaño y el brillo."
        case .city: return "cada repo de la carpeta es un edificio: altura, luces y color salen de su git."
        case .radar: return "sondea tus servicios y compara el DNS de tu equipo con los públicos."
        }
    }
    var defaultPort: Int { switch self { case .galaxy: return 4949; case .city: return 5050; case .radar: return 4848 } }
}

enum LabRules {
    static let minNodeMajor = 20

    /// "v26.8.1" -> (26, 8, 1). Cualquier otra cosa es nil.
    static func nodeVersion(from output: String) -> (Int, Int, Int)? {
        let t = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("v") else { return nil }
        let parts = t.dropFirst().split(separator: ".").prefix(3).map { Int($0) }
        guard parts.count == 3, !parts.contains(where: { $0 == nil }) else { return nil }
        return (parts[0]!, parts[1]!, parts[2]!)
    }

    static func nodeSupported(_ v: (Int, Int, Int)?) -> Bool { (v?.0 ?? 0) >= minNodeMajor }

    /// Donde buscar node, de mas probable a menos. No se usa el shell: la app no hereda tu PATH.
    static func nodeCandidates(home: String = NSHomeDirectory(), env: [String: String] = ProcessInfo.processInfo.environment, fm: FileManager = .default) -> [String] {
        var out: [String] = []
        if let p = env["CLAUDE_PET_NODE"], !p.isEmpty { out.append(p) }
        out += ["/opt/homebrew/bin/node", "/usr/local/bin/node", home + "/.volta/bin/node", "/usr/bin/node"]
        // nvm: la version mas reciente instalada
        let nvm = home + "/.nvm/versions/node"
        if let vs = try? fm.contentsOfDirectory(atPath: nvm) {
            out += vs.sorted { $0.localizedStandardCompare($1) == .orderedDescending }.map { nvm + "/" + $0 + "/bin/node" }
        }
        return out
    }

    /// La carpeta `tools`: la de la app empaquetada, o la del repo si se ejecuta desde el codigo fuente.
    static func toolsRoot(resources: String? = Bundle.main.resourcePath, env: [String: String] = ProcessInfo.processInfo.environment, fm: FileManager = .default) -> String? {
        var options: [String] = []
        if let p = env["CLAUDE_PET_TOOLS"], !p.isEmpty { options.append(p) }
        if let r = resources { options.append(r + "/tools") }
        options.append(fm.currentDirectoryPath + "/tools")
        return options.first { fm.fileExists(atPath: $0 + "/galaxia/bin/galaxia.js") }
    }

    /// Que carpeta recibe cada herramienta a partir del proyecto activo: galaxia el propio repo, ciudad la carpeta que contiene los repos.
    static func targetDirectory(_ tool: LabTool, workspace: String) -> String? {
        switch tool {
        case .galaxy: return workspace.isEmpty ? nil : workspace
        case .city: return workspace.isEmpty ? nil : (workspace as NSString).deletingLastPathComponent
        case .radar: return nil
        }
    }

    static func arguments(tool: LabTool, root: String, directory: String?, port: Int) -> [String] {
        var a = ["\(root)/\(tool.folder)/bin/\(tool.folder).js"]
        if let d = directory { a.append(d) }
        a += ["--port", String(port), "--no-open"]
        return a
    }

    /// Primer puerto libre desde `start`. `isFree` se inyecta para poder probarlo.
    static func freePort(from start: Int, tries: Int = 30, isFree: (Int) -> Bool = portIsFree) -> Int? {
        (start..<(start + tries)).first { $0 < 65_535 && isFree($0) }
    }

    static func portIsFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian); addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
    }

    /// La direccion que imprime la herramienta al arrancar: solo se acepta 127.0.0.1.
    static func url(in line: String) -> URL? {
        guard let r = line.range(of: #"http://127\.0\.0\.1:\d{2,5}/"#, options: .regularExpression) else { return nil }
        return URL(string: String(line[r]))
    }
}

enum LabResult: Equatable {
    case started(URL), reused(URL), failure(String)
}

@MainActor
final class LabLauncher: ObservableObject {
    static let shared = LabLauncher()
    @Published private(set) var urls: [LabTool: URL] = [:]
    private var processes: [LabTool: Process] = [:]
    private var cachedNode: String??

    /// node 20 o superior, o nil si no esta.
    var nodePath: String? {
        if let c = cachedNode { return c }
        let found = LabRules.nodeCandidates().first { path in
            guard FileManager.default.isExecutableFile(atPath: path) else { return false }
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = ["--version"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return LabRules.nodeSupported(LabRules.nodeVersion(from: String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""))
        }
        cachedNode = .some(found)
        return found
    }

    var available: Bool { nodePath != nil && LabRules.toolsRoot() != nil }

    func isRunning(_ tool: LabTool) -> Bool { processes[tool]?.isRunning == true }

    /// Lanza la herramienta (o reutiliza la que ya corre), espera a que responda y devuelve su direccion.
    func launch(_ tool: LabTool, workspace: String, root: String? = LabRules.toolsRoot()) async -> LabResult {
        if let p = processes[tool], p.isRunning, let u = urls[tool] { return .reused(u) }
        guard let node = nodePath else { return .failure("falta node \(LabRules.minNodeMajor) o superior (brew install node)") }
        guard let rawRoot = root else { return .failure("no encuentro las herramientas incluidas") }
        let root = URL(fileURLWithPath: rawRoot).standardizedFileURL.path      // absoluta: el proceso arranca dentro de la carpeta de la herramienta
        let directory = LabRules.targetDirectory(tool, workspace: workspace)
        if tool != .radar, directory == nil { return .failure("no hay un proyecto activo") }
        if let d = directory, !FileManager.default.fileExists(atPath: d) { return .failure("la carpeta ya no existe") }
        guard let port = LabRules.freePort(from: tool.defaultPort) else { return .failure("no hay un puerto libre") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = LabRules.arguments(tool: tool, root: root, directory: directory, port: port)
        p.currentDirectoryURL = URL(fileURLWithPath: root + "/" + tool.folder)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.terminationHandler = { [weak self] _ in Task { @MainActor in self?.processes[tool] = nil; self?.urls[tool] = nil } }
        do { try p.run() } catch { return .failure("no se pudo lanzar node") }
        processes[tool] = p

        let result: LabResult = await withCheckedContinuation { (cont: CheckedContinuation<LabResult, Never>) in
            let gate = Gate(cont)
            out.fileHandleForReading.readabilityHandler = { h in
                let text = String(data: h.availableData, encoding: .utf8) ?? ""
                if let u = LabRules.url(in: text) { gate.resolve(.started(u)) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let text = (String(data: h.availableData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { gate.resolve(.failure(String(text.prefix(120)))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { gate.resolve(.failure("no respondió a tiempo")) }
        }
        out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
        switch result {
        case .started(let u): urls[tool] = u
        default: if p.isRunning { p.terminate() }; processes[tool] = nil
        }
        return result
    }

    /// Lanza y abre la pagina en el navegador.
    @discardableResult
    func open(_ tool: LabTool, workspace: String) async -> LabResult {
        let r = await launch(tool, workspace: workspace)
        switch r { case .started(let u), .reused(let u): NSWorkspace.shared.open(u); default: break }
        return r
    }

    func stop(_ tool: LabTool) { processes[tool]?.terminate(); processes[tool] = nil; urls[tool] = nil }
    func stopAll() { LabTool.allCases.forEach(stop) }
}

/// Entrega un unico resultado aunque lleguen varios eventos (salida, error y plazo).
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<LabResult, Never>?
    init(_ c: CheckedContinuation<LabResult, Never>) { cont = c }
    func resolve(_ r: LabResult) { lock.lock(); let c = cont; cont = nil; lock.unlock(); c?.resume(returning: r) }
}
