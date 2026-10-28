import AppKit
import CryptoKit
import ImageIO

/// Una cancion que ya sono: lo justo para mostrarla con su portada y volver a ponerla.
struct IndexedTrack: Codable, Equatable, Identifiable {
    var id: String            // clave de la cancion (hash de app, titulo, artista y album)
    var app: String           // MusicApp.rawValue
    var title: String
    var artist: String
    var album: String
    var uri: String?          // spotify:track:... o el identificador persistente de Music
    var lastPlayed: Date
    var plays: Int
}

/// Indice de lo reciente, acotado: las canciones mas nuevas primero, hasta 60.
struct MusicIndex: Codable, Equatable {
    static let maxTracks = 60
    static var path: String { ProcessInfo.processInfo.environment["CLAUDE_PET_MUSIC_INDEX"] ?? (NSHomeDirectory() + "/.claude-pet/music-index.json") }
    var tracks: [IndexedTrack] = []

    @discardableResult
    mutating func record(_ n: NowPlaying, at date: Date = Date()) -> IndexedTrack {
        let key = CoverCache.key(n.trackID)
        if let i = tracks.firstIndex(where: { $0.id == key }) {
            tracks[i].lastPlayed = date; tracks[i].plays += 1
            if let u = n.uri { tracks[i].uri = u }
            let t = tracks.remove(at: i); tracks.insert(t, at: 0)
            return t
        }
        let t = IndexedTrack(id: key, app: n.app.rawValue, title: n.title, artist: n.artist, album: n.album, uri: n.uri, lastPlayed: date, plays: 1)
        tracks.insert(t, at: 0)
        if tracks.count > Self.maxTracks { tracks.removeLast(tracks.count - Self.maxTracks) }
        return t
    }

    func recents(_ n: Int) -> [IndexedTrack] { Array(tracks.prefix(max(0, n))) }

    /// Lo que no cumple las reglas se descarta al cargar: el archivo lo puede tocar cualquiera.
    var sanitized: MusicIndex {
        let ok = tracks.filter { t in
            t.id.count == 24 && t.id.allSatisfy(\.isHexDigit) && MusicApp(rawValue: t.app) != nil
                && !t.title.isEmpty && t.title.count <= 160 && t.artist.count <= 160 && t.album.count <= 160 && (t.uri.map { MusicScript.validID($0, app: MusicApp(rawValue: t.app)!) } ?? true)
        }
        return MusicIndex(tracks: Array(ok.prefix(Self.maxTracks)))
    }

    static func load(from path: String = MusicIndex.path) -> MusicIndex {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 512 * 1024 else { return MusicIndex() }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return ((try? d.decode(MusicIndex.self, from: data)) ?? MusicIndex()).sanitized
    }

    func save(to path: String = MusicIndex.path) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        chmod(path, 0o600)
    }
}

/// Portadas ya descargadas, en ~/Library/Caches: aparecen al instante y sobreviven a reinicios.
/// Se guardan a 192 px en JPEG y la carpeta no pasa de 80 archivos ni 24 MB.
enum CoverCache {
    static let maxPixels = 192
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_PET_COVERS"] { return URL(fileURLWithPath: custom) }
        return URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/claude-pet/covers")
    }

    static func key(_ trackID: String) -> String { SHA256.hash(data: Data(trackID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() }

    private static func isKey(_ k: String) -> Bool { k.count == 24 && k.allSatisfy(\.isHexDigit) }
    static func file(_ key: String, in dir: URL = directory) -> URL? { isKey(key) ? dir.appendingPathComponent(key + ".jpg") : nil }

    /// Reduce la imagen sin decodificarla entera y la guarda. nil si no es una imagen valida.
    @discardableResult
    static func store(_ data: Data, key: String, in dir: URL = directory) -> NSImage? {
        guard data.count < 4_000_000, let url = file(key, in: dir), let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                                                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: thumb)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: .atomic)
        return NSImage(data: jpeg)
    }

    static func load(_ key: String, in dir: URL = directory) -> NSImage? {
        guard let url = file(key, in: dir), let data = try? Data(contentsOf: url), data.count < 1_000_000 else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)   // lo usado hace poco se conserva
        return NSImage(data: data)
    }

    /// Borra lo mas antiguo hasta cumplir los dos limites.
    static func prune(in dir: URL = directory, maxFiles: Int = 80, maxBytes: Int = 24 * 1024 * 1024) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var items = urls.filter { $0.pathExtension == "jpg" }.compactMap { u -> (URL, Date, Int)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var total = items.reduce(0) { $0 + $1.2 }
        while let last = items.last, items.count > maxFiles || total > maxBytes {
            try? FileManager.default.removeItem(at: last.0); total -= last.2; items.removeLast()
        }
    }
}
