import Foundation

enum MusicApp: String, CaseIterable {
    case spotify, appleMusic
    var bundle: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var title: String { self == .spotify ? "Spotify" : "Apple Music" }
}

/// Lo que suena ahora en Spotify o Apple Music.
struct NowPlaying: Equatable {
    var app: MusicApp
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var position: Double
    var duration: Double
    var volume: Int
    var artworkURL: String?

    /// Identifica la cancion para detectar cambios de tema (la posicion no cuenta).
    var trackID: String { "\(app.rawValue)|\(title)|\(artist)|\(album)" }
    /// Igual que `self` pero sin la posicion: sirve para decidir si hay que republicar.
    var withoutPosition: NowPlaying { var c = self; c.position = 0; return c }
}

/// Scripts de AppleScript y su respuesta. Todo es texto fijo: lo unico que se interpola son numeros ya acotados.
enum MusicScript {
    static let separator = "\u{1F}"

    static func query(_ app: MusicApp) -> String {
        let artwork = app == .spotify ? "(artwork url of t)" : "\"\""
        return """
        tell application id "\(app.bundle)"
        set st to player state as string
        if st is "stopped" then return "stopped"
        set sep to character id 31
        set t to current track
        return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (player position as string) & sep & ((duration of t) as string) & sep & (sound volume as string) & sep & \(artwork)
        end tell
        """
    }

    /// Portada de Apple Music como datos de imagen; Spotify da una direccion en la consulta.
    static let appleMusicArtwork = "tell application id \"com.apple.Music\" to return data of artwork 1 of current track"

    enum Command: Equatable { case playPause, next, previous, seek(Int), volume(Int) }

    static func command(_ c: Command, app: MusicApp) -> String {
        let head = "tell application id \"\(app.bundle)\" to "
        switch c {
        case .playPause: return head + "playpause"
        case .next: return head + "next track"
        case .previous: return head + "previous track"
        case .seek(let s): return head + "set player position to \(max(0, min(86_400, s)))"
        case .volume(let v): return head + "set sound volume to \(max(0, min(100, v)))"
        }
    }

    /// Quita controles y recorta: el texto viene de fuera y acaba en pantalla.
    static func clean(_ s: String, limit: Int = 160) -> String {
        let scalars = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit).description
    }

    /// Numero con coma o punto decimal, segun el idioma del sistema.
    static func number(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), v.isFinite else { return nil }
        return v
    }

    static func parse(_ raw: String, app: MusicApp) -> NowPlaying? {
        let parts = raw.components(separatedBy: separator)
        guard parts.count >= 7 else { return nil }
        let state = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard state != "stopped" else { return nil }
        let title = clean(parts[1])
        guard !title.isEmpty, let pos = number(parts[4]), let dur = number(parts[5]), let vol = number(parts[6]) else { return nil }
        let seconds = app == .spotify ? dur / 1000 : dur          // Spotify da milisegundos, Music segundos
        let duration = max(0, min(seconds, 86_400))
        var art: String?
        if parts.count > 7 { let u = parts[7].trimmingCharacters(in: .whitespacesAndNewlines); if u.hasPrefix("https://"), u.count < 400 { art = u } }
        return NowPlaying(app: app, isPlaying: state == "playing", title: title, artist: clean(parts[2]), album: clean(parts[3]),
                          position: max(0, min(pos, duration)), duration: duration, volume: Int(max(0, min(100, vol)).rounded()), artworkURL: art)
    }

    /// Solo se descargan portadas de la CDN de Spotify, por https y con un tope de tamaño.
    static func isAllowedArtwork(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co")
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Reaccion visual a la musica: notas pixel-art que suben de la mascota (mas volumen, mas notas) y un anillo al cambiar de tema.
enum MusicFx {
    static let burst: TimeInterval = 1.6
    private static let colors: [UInt32] = [0x7FD1FF, 0xFF9FD0, 0xFFD166, 0x8CE99A]

    static func noteCount(level: Double) -> Int { 2 + Int((max(0, min(1, level)) * 4).rounded()) }

    static func notes(at t: TimeInterval, level: Double, trackAge: TimeInterval) -> [FxPixel] {
        let n = noteCount(level: level)
        var out: [FxPixel] = []
        for i in 0..<n {
            let speed = 0.16 + VisualFx.rnd(i + 3) * 0.1
            let p = (t * speed + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            let x = 0.5 + (VisualFx.rnd(i + 11) - 0.5) * 0.7 + sin(p * 7 + Double(i)) * 0.04
            let y = 0.64 - p * 0.56
            let a = sin(p * .pi)
            let c = colors[i % colors.count]
            out.append(FxPixel(x: x, y: y, size: 2.2, color: c, alpha: a))                           // cabeza
            for k in 1...3 { out.append(FxPixel(x: x + 0.022, y: y - Double(k) * 0.02, size: 1, color: c, alpha: a)) }   // plica
            out.append(FxPixel(x: x + 0.04, y: y - 0.056, size: 1, color: c, alpha: a * 0.9))         // bandera
        }
        if trackAge >= 0, trackAge < burst {
            let p = trackAge / burst
            for k in 0..<12 {
                let a = Double(k) / 12 * 2 * .pi
                out.append(FxPixel(x: 0.5 + cos(a) * (0.1 + 0.34 * p), y: 0.42 + sin(a) * (0.08 + 0.26 * p), size: 1.6, color: colors[k % colors.count], alpha: 1 - p))
            }
        }
        return out
    }
}
