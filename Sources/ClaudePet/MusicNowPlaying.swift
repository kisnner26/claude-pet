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
    /// spotify:track:... o el identificador persistente de Music: sirve para volver a poner la cancion.
    var uri: String?

    /// Identifica la cancion para detectar cambios de tema (la posicion no cuenta).
    var trackID: String { "\(app.rawValue)|\(title)|\(artist)|\(album)" }
    /// Igual que `self` pero sin la posicion: sirve para decidir si hay que republicar.
    var withoutPosition: NowPlaying { var c = self; c.position = 0; return c }
}

/// Scripts de AppleScript y su respuesta. Todo es texto fijo: lo unico que se interpola son numeros ya acotados.
enum MusicScript {
    static let separator = "\u{1F}"

    /// Toda orden va dentro de `with timeout`: si la app no responde, el script falla en 3 s en vez de esperar dos minutos.
    private static func guarded(_ body: String) -> String { "with timeout of 3 seconds\n\(body)\nend timeout" }

    static func query(_ app: MusicApp) -> String {
        let artwork = app == .spotify ? "(artwork url of trk)" : "\"\""
        let ident = app == .spotify ? "(spotify url of trk)" : "(persistent ID of trk)"
        // ojo con los nombres: en el diccionario de Music una variable llamada `st` no compila
        return guarded("""
        tell application id "\(app.bundle)"
        set stateText to player state as string
        if stateText is "stopped" then return "stopped"
        set sepChar to character id 31
        set trk to current track
        return stateText & sepChar & (name of trk) & sepChar & (artist of trk) & sepChar & (album of trk) & sepChar & (player position as string) & sepChar & ((duration of trk) as string) & sepChar & (sound volume as string) & sepChar & \(artwork) & sepChar & \(ident)
        end tell
        """)
    }

    /// Los identificadores se interpolan en un script: solo se aceptan con la forma exacta de cada app.
    static func validID(_ id: String, app: MusicApp) -> Bool {
        switch app {
        case .spotify: return id.count == 36 && id.hasPrefix("spotify:track:") && id.dropFirst(14).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        case .appleMusic: return id.count == 16 && id.allSatisfy { $0.isHexDigit && !$0.isLowercase }
        }
    }

    /// Vuelve a poner una cancion del indice. nil si el identificador no es valido.
    static func play(id: String, app: MusicApp) -> String? {
        guard validID(id, app: app) else { return nil }
        switch app {
        case .spotify: return guarded("tell application id \"\(app.bundle)\" to play track \"\(id)\"")
        case .appleMusic: return guarded("tell application id \"\(app.bundle)\" to play (first track of library playlist 1 whose persistent ID is \"\(id)\")")
        }
    }

    /// Portada de Apple Music como datos de imagen; Spotify da una direccion en la consulta.
    static let appleMusicArtwork = guarded("tell application id \"com.apple.Music\" to return data of artwork 1 of current track")

    enum Command: Equatable { case playPause, next, previous, seek(Int), volume(Int) }

    static func command(_ c: Command, app: MusicApp) -> String {
        let head = "tell application id \"\(app.bundle)\" to "
        switch c {
        case .playPause: return guarded(head + "playpause")
        case .next: return guarded(head + "next track")
        case .previous: return guarded(head + "previous track")
        case .seek(let s): return guarded(head + "set player position to \(max(0, min(86_400, s)))")
        case .volume(let v): return guarded(head + "set sound volume to \(max(0, min(100, v)))")
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
        var uri: String?
        if parts.count > 8 { let u = parts[8].trimmingCharacters(in: .whitespacesAndNewlines); if validID(u, app: app) { uri = u } }
        return NowPlaying(app: app, isPlaying: state == "playing", title: title, artist: clean(parts[2]), album: clean(parts[3]),
                          position: max(0, min(pos, duration)), duration: duration, volume: Int(max(0, min(100, vol)).rounded()), artworkURL: art, uri: uri)
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

    static func notes(at t: TimeInterval, level: Double, trackAge: TimeInterval, colors: [UInt32]? = nil) -> [FxPixel] {
        let colors = colors ?? Self.colors
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
