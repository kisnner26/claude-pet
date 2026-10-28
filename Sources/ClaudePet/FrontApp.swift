import AppKit

/// App en primer plano: solo su identificador y su nombre. No captura pantalla, ventanas ni contenido.
/// Ignora a claude-pet: al tocar la isla o los ajustes se conserva la app donde estabas.
@MainActor
final class FrontAppTracker: ObservableObject {
    static let shared = FrontAppTracker()
    @Published private(set) var bundleID: String?
    @Published private(set) var name: String?
    @Published private(set) var icon: NSImage?
    private(set) var appURL: URL?
    /// Categoria que declara la app en su Info.plist; sirve para clasificar las que no conocemos por nombre.
    private(set) var category: String?
    private var token: NSObjectProtocol?

    var profile: AppProfile { AppProfile.classify(bundleID: bundleID, category: category) }

    func start() {
        guard token == nil else { return }
        scan()
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return }
        if bundleID != app.bundleIdentifier { category = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["LSApplicationCategoryType"] as? String }; bundleID = app.bundleIdentifier; name = app.localizedName; icon = app.icon; appURL = app.bundleURL }
    }

    deinit { if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
}

/// Direccion web del remoto "origin" de cada proyecto, leida en segundo plano y recordada un minuto.
@MainActor
final class GitRemoteCache: ObservableObject {
    static let shared = GitRemoteCache()
    @Published private(set) var urls: [String: String] = [:]
    private var checkedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []

    /// La direccion si ya se conoce; si hace falta, lanza la lectura y avisa a la interfaz al terminar.
    func webURL(for workspace: String) -> String? {
        guard CommiteroLauncher.isLaunchableWorkspace(workspace) else { return nil }
        if let t = checkedAt[workspace], Date().timeIntervalSince(t) < 60 { return urls[workspace] }
        guard !inFlight.contains(workspace) else { return urls[workspace] }
        inFlight.insert(workspace)
        Task.detached(priority: .utility) {
            let raw = GitRemoteCache.originURL(in: workspace)
            let web = raw.flatMap(GitRemote.webURL)
            await MainActor.run {
                self.inFlight.remove(workspace); self.checkedAt[workspace] = Date()
                if self.urls[workspace] != web { self.urls[workspace] = web }
            }
        }
        return urls[workspace]
    }

    nonisolated static func originURL(in workspace: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", workspace, "remote", "get-url", "origin"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data.prefix(400), as: UTF8.self) : nil
    }
}
