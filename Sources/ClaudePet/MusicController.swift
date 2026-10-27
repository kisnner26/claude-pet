import AppKit

/// Habla con Spotify y Apple Music por AppleScript: lee lo que suena y manda play, pausa, siguiente, anterior, posicion y volumen.
/// Solo pregunta a una app que ya esta abierta (nunca la lanza). La primera vez macOS pide permiso de automatizacion por app.
@MainActor
final class MusicController: ObservableObject {
    /// Solo se republica cuando cambia algo que no sea la posicion: la barra de progreso se interpola con `position(at:)`.
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var cover: NSImage?
    private(set) var trackChangedAt: TimeInterval = -100

    private var lastPosition = 0.0
    private var polledAt: TimeInterval = 0
    private var timer: Timer?
    private var scripts: [String: NSAppleScript] = [:]
    private var preferred: MusicApp?
    private var artworkTask: Task<Void, Never>?

    /// El reproductor esta activado en ajustes.
    var enabled = false { didSet { if enabled != oldValue { reschedule() } } }
    /// El panel del reproductor esta a la vista: se consulta cada segundo en vez de cada pocos.
    var watching = false { didSet { if watching != oldValue { reschedule(); if watching { poll() } } } }

    init(enabled: Bool) { self.enabled = enabled; reschedule() }

    var isPlaying: Bool { nowPlaying?.isPlaying == true }

    func position(at uptime: TimeInterval) -> Double {
        guard let n = nowPlaying else { return 0 }
        let moved = n.isPlaying ? uptime - polledAt : 0
        return max(0, min(n.duration, lastPosition + moved))
    }

    private func reschedule() {
        timer?.invalidate(); timer = nil
        guard enabled else { clear(); return }
        let t = Timer(timeInterval: watching ? 1 : 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func clear() {
        artworkTask?.cancel()
        if nowPlaying != nil { nowPlaying = nil }
        if cover != nil { cover = nil }
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script = scripts[source] ?? NSAppleScript(source: source)
        if scripts[source] == nil, scripts.count < 24 { scripts[source] = script }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func isRunning(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundle }
    }

    func poll() {
        guard enabled else { return }
        let order = MusicApp.allCases.sorted { ($0 == preferred ? 0 : 1) < ($1 == preferred ? 0 : 1) }
        var found: NowPlaying?
        for app in order where isRunning(app) {
            guard let raw = run(MusicScript.query(app))?.stringValue, let n = MusicScript.parse(raw, app: app) else { continue }
            if n.isPlaying { found = n; break }
            if found == nil { found = n }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let f = found { preferred = f.app; lastPosition = f.position; polledAt = now }
        guard found?.withoutPosition != nowPlaying?.withoutPosition else { return }
        if let f = found, let old = nowPlaying, f.trackID != old.trackID { trackChangedAt = now }
        let newTrack = found?.trackID != nowPlaying?.trackID
        nowPlaying = found
        if newTrack { loadCover(for: found) }
    }

    // MARK: portada

    private func loadCover(for n: NowPlaying?) {
        artworkTask?.cancel(); cover = nil
        guard let n else { return }
        if n.app == .appleMusic {
            if let data = run(MusicScript.appleMusicArtwork)?.data, data.count < 4_000_000 { cover = NSImage(data: data) }
        } else if let urlString = n.artworkURL, MusicScript.isAllowedArtwork(urlString), let url = URL(string: urlString) {
            let id = n.trackID
            artworkTask = Task { [weak self] in
                var request = URLRequest(url: url); request.timeoutInterval = 6
                guard let (data, _) = try? await URLSession.shared.data(for: request), data.count < 3_000_000, !Task.isCancelled else { return }
                await MainActor.run { if self?.nowPlaying?.trackID == id { self?.cover = NSImage(data: data) } }
            }
        }
    }

    // MARK: control

    func send(_ command: MusicScript.Command) {
        guard let app = nowPlaying?.app ?? preferred else { return }
        _ = run(MusicScript.command(command, app: app))
        if command == .playPause, var n = nowPlaying { n.isPlaying.toggle(); lastPosition = position(at: ProcessInfo.processInfo.systemUptime); polledAt = ProcessInfo.processInfo.systemUptime; nowPlaying = n }
        if case .seek(let s) = command { lastPosition = Double(s); polledAt = ProcessInfo.processInfo.systemUptime }
        if case .volume(let v) = command, var n = nowPlaying { n.volume = v; nowPlaying = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    func seek(toFraction f: Double) {
        guard let n = nowPlaying, n.duration > 0 else { return }
        send(.seek(Int((max(0, min(1, f)) * n.duration).rounded())))
    }
}
