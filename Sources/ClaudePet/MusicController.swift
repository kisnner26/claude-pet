import AppKit

/// Ejecuta AppleScript en una cola propia y de una en una. El hilo principal nunca espera a Spotify ni a Music:
/// si una app tarda, el script falla a los 3 s (`with timeout`) y la interfaz sigue fluida.
private final class ScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "claudepet.music", qos: .utility)
    private var compiled: [String: NSAppleScript] = [:]      // solo se toca desde `queue`

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript?
        if let c = compiled[source] { script = c } else { script = NSAppleScript(source: source); if compiled.count < 32 { compiled[source] = script } }
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    func query(order: [MusicApp], running: Set<MusicApp>, _ done: @escaping @Sendable (NowPlaying?) -> Void) {
        queue.async { [self] in
            var found: NowPlaying?
            for app in order where running.contains(app) {
                guard let raw = execute(MusicScript.query(app))?.stringValue, let n = MusicScript.parse(raw, app: app) else { continue }
                if n.isPlaying { found = n; break }
                if found == nil { found = n }
            }
            done(found)
        }
    }

    func run(_ source: String, _ done: (@Sendable () -> Void)? = nil) { queue.async { [self] in _ = execute(source); done?() } }

    func appleMusicArtwork(_ done: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in done(execute(MusicScript.appleMusicArtwork)?.data) }
    }
}

/// Habla con Spotify y Apple Music: lee lo que suena y manda play, pausa, siguiente, anterior, posicion y volumen.
/// Solo pregunta a una app que ya esta abierta (nunca la lanza). La primera vez macOS pide permiso de automatizacion por app.
@MainActor
final class MusicController: ObservableObject {
    /// Solo se republica cuando cambia algo que no sea la posicion: la barra de progreso se interpola con `position(at:)`.
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var cover: NSImage?
    @Published private(set) var recents: [IndexedTrack] = []
    private(set) var trackChangedAt: TimeInterval = -100
    /// Lo usan los plugins: se avisa al empezar una cancion nueva.
    var onTrack: ((NowPlaying) -> Void)?

    private let runner = ScriptRunner()
    private var lastPosition = 0.0
    private var polledAt: TimeInterval = 0
    private var timer: Timer?
    private var inFlight = false
    private var preferred: MusicApp?
    private var coverTask: Task<Void, Never>?
    private let memory = NSCache<NSString, NSImage>()
    private var index = MusicIndex.load()
    private var saveScheduled = false

    /// El reproductor esta activado en ajustes.
    var enabled = false { didSet { if enabled != oldValue { reschedule() } } }
    /// El panel del reproductor esta a la vista: se consulta cada segundo en vez de cada pocos.
    var watching = false { didSet { if watching != oldValue { reschedule(); if watching { poll() } } } }

    init(enabled: Bool) {
        memory.countLimit = 40
        recents = index.recents(12)
        self.enabled = enabled
        reschedule()
        DispatchQueue.global(qos: .utility).async { CoverCache.prune() }
    }

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
        t.tolerance = watching ? 0.2 : 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func clear() {
        coverTask?.cancel()
        if nowPlaying != nil { nowPlaying = nil }
        if cover != nil { cover = nil }
    }

    private func running(_ app: MusicApp) -> Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundle } }

    func poll() {
        guard enabled, !inFlight else { return }       // si Spotify tarda, no se apilan consultas
        let up = Set(MusicApp.allCases.filter(running))
        guard !up.isEmpty else { if nowPlaying != nil { apply(nil) }; return }
        inFlight = true
        let order = MusicApp.allCases.sorted { ($0 == preferred ? 0 : 1) < ($1 == preferred ? 0 : 1) }
        runner.query(order: order, running: up) { [weak self] found in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.inFlight = false; self?.apply(found) } }
        }
    }

    private func apply(_ found: NowPlaying?) {
        let now = ProcessInfo.processInfo.systemUptime
        if let f = found { preferred = f.app; lastPosition = f.position; polledAt = now }
        guard found?.withoutPosition != nowPlaying?.withoutPosition else { return }
        if let f = found, let old = nowPlaying, f.trackID != old.trackID { trackChangedAt = now }
        let newTrack = found?.trackID != nowPlaying?.trackID
        nowPlaying = found
        guard newTrack else { return }
        if let f = found, f.isPlaying { record(f); onTrack?(f) }
        loadCover(for: found)
    }

    // MARK: indice

    private func record(_ n: NowPlaying) {
        index.record(n)
        recents = index.recents(12)
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated { guard let self else { return }; self.saveScheduled = false; let snapshot = self.index; DispatchQueue.global(qos: .utility).async { snapshot.save() } }
        }
    }

    func clearIndex() {
        index = MusicIndex(); recents = []
        let snapshot = index
        DispatchQueue.global(qos: .utility).async { snapshot.save(); try? FileManager.default.removeItem(at: CoverCache.directory) }
        memory.removeAllObjects()
    }

    /// Vuelve a poner una cancion del indice, si su app esta abierta.
    func play(_ t: IndexedTrack) {
        guard let app = MusicApp(rawValue: t.app), running(app), let id = t.uri, let script = MusicScript.play(id: id, app: app) else { NSSound.beep(); return }
        runner.run(script) { [weak self] in DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { self?.poll() } } }
    }

    // MARK: portada

    /// Portada de una cancion del indice (memoria, luego disco). Nunca descarga nada.
    func cachedCover(for id: String) -> NSImage? {
        if let m = memory.object(forKey: id as NSString) { return m }
        guard let img = CoverCache.load(id) else { return nil }
        memory.setObject(img, forKey: id as NSString)
        return img
    }

    private func loadCover(for n: NowPlaying?) {
        coverTask?.cancel(); cover = nil
        guard let n else { return }
        let key = CoverCache.key(n.trackID), trackID = n.trackID
        if let hit = cachedCover(for: key) { cover = hit; return }
        coverTask = Task { [weak self] in
            var data: Data?
            if n.app == .appleMusic {
                data = await withCheckedContinuation { c in self?.runner.appleMusicArtwork { c.resume(returning: $0) } ?? c.resume(returning: nil) }
            } else if let s = n.artworkURL, MusicScript.isAllowedArtwork(s), let url = URL(string: s) {
                var request = URLRequest(url: url); request.timeoutInterval = 6
                data = (try? await URLSession.shared.data(for: request))?.0
            }
            guard let data, !Task.isCancelled else { return }
            let stored = await Task.detached(priority: .utility) { CoverCache.store(data, key: key) }.value
            await MainActor.run {
                guard let self, let img = stored else { return }
                self.memory.setObject(img, forKey: key as NSString)
                if self.nowPlaying?.trackID == trackID { self.cover = img }
            }
        }
    }

    // MARK: control

    func send(_ command: MusicScript.Command) {
        guard let app = nowPlaying?.app ?? preferred else { return }
        runner.run(MusicScript.command(command, app: app))
        let now = ProcessInfo.processInfo.systemUptime
        if command == .playPause, var n = nowPlaying { n.isPlaying.toggle(); lastPosition = position(at: now); polledAt = now; nowPlaying = n }
        if case .seek(let s) = command { lastPosition = Double(s); polledAt = now }
        if case .volume(let v) = command, var n = nowPlaying { n.volume = v; nowPlaying = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in MainActor.assumeIsolated { self?.poll() } }
    }

    func seek(toFraction f: Double) {
        guard let n = nowPlaying, n.duration > 0 else { return }
        send(.seek(Int((max(0, min(1, f)) * n.duration).rounded())))
    }
}
