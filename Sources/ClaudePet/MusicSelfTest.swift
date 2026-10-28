import AppKit

enum MusicSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }
        let sep = MusicScript.separator

        let spotify = MusicScript.parse(["playing", "Taxi Cab", "twenty one pilots", "Vessel", "12,5", "262000", "70", "https://i.scdn.co/image/abc"].joined(separator: sep), app: .spotify)
        check("spotify-parse", spotify?.title == "Taxi Cab" && spotify?.artist == "twenty one pilots" && spotify?.isPlaying == true)
        check("spotify-units", spotify?.position == 12.5 && spotify?.duration == 262 && spotify?.volume == 70)
        check("spotify-art", spotify?.artworkURL == "https://i.scdn.co/image/abc")

        let music = MusicScript.parse(["paused", "Song", "Band", "Album", "30.25", "215.3", "55", ""].joined(separator: sep), app: .appleMusic)
        check("music-parse", music?.isPlaying == false && music?.duration == 215.3 && music?.position == 30.25 && music?.artworkURL == nil)

        check("stopped", MusicScript.parse("stopped", app: .spotify) == nil)
        check("too-few", MusicScript.parse(["playing", "a", "b"].joined(separator: sep), app: .spotify) == nil)
        check("empty-title", MusicScript.parse(["playing", "", "b", "c", "1", "2", "3", ""].joined(separator: sep), app: .appleMusic) == nil)
        check("bad-number", MusicScript.parse(["playing", "a", "b", "c", "x", "2", "3", ""].joined(separator: sep), app: .appleMusic) == nil)
        check("nan", MusicScript.parse(["playing", "a", "b", "c", "nan", "2", "3", ""].joined(separator: sep), app: .appleMusic) == nil)
        check("clamp", { let n = MusicScript.parse(["playing", "a", "b", "c", "999", "100", "500", ""].joined(separator: sep), app: .appleMusic); return n?.position == 100 && n?.volume == 100 }())
        check("http-art-rejected", MusicScript.parse(["playing", "a", "b", "c", "1", "9000", "5", "http://evil/x.jpg"].joined(separator: sep), app: .spotify)?.artworkURL == nil)

        let long = String(repeating: "x", count: 500)
        let dirty = MusicScript.parse(["playing", "ti\u{7}tle\n" + long, "b", "c", "1", "9000", "5", ""].joined(separator: sep), app: .spotify)
        check("clean", dirty?.title.count == 160 && dirty?.title.hasPrefix("title") == true)

        check("track-id", spotify?.trackID == "spotify|Taxi Cab|twenty one pilots|Vessel")
        check("without-position", spotify?.withoutPosition == spotify.map { var c = $0; c.position = 99; return c.withoutPosition })

        check("art-allow", MusicScript.isAllowedArtwork("https://i.scdn.co/image/x") && MusicScript.isAllowedArtwork("https://scdn.co/a"))
        check("art-deny", !MusicScript.isAllowedArtwork("http://i.scdn.co/x") && !MusicScript.isAllowedArtwork("https://scdn.co.evil.com/x") && !MusicScript.isAllowedArtwork("https://evilscdn.co/x") && !MusicScript.isAllowedArtwork("file:///etc/passwd"))

        check("cmd-playpause", MusicScript.command(.playPause, app: .spotify).contains("tell application id \"com.spotify.client\" to playpause"))
        check("cmd-next", MusicScript.command(.next, app: .appleMusic).contains("tell application id \"com.apple.Music\" to next track"))
        check("cmd-timeout", [MusicScript.command(.next, app: .spotify), MusicScript.query(.appleMusic), MusicScript.appleMusicArtwork].allSatisfy { $0.hasPrefix("with timeout of 3 seconds\n") && $0.hasSuffix("\nend timeout") })
        check("cmd-seek-clamp", MusicScript.command(.seek(-5), app: .spotify).contains("position to 0\n") && MusicScript.command(.seek(999_999), app: .spotify).contains("position to 86400\n"))
        check("cmd-volume-clamp", MusicScript.command(.volume(250), app: .appleMusic).contains("volume to 100\n") && MusicScript.command(.volume(-3), app: .appleMusic).contains("volume to 0\n"))
        check("query-has-no-user-input", MusicScript.query(.spotify).contains("artwork url") && !MusicScript.query(.appleMusic).contains("artwork url"))
        check("clock", MusicScript.clock(0) == "0:00" && MusicScript.clock(75.9) == "1:15" && MusicScript.clock(-3) == "0:00")

        // reaccion visual
        check("notes-scale", MusicFx.noteCount(level: 0) == 2 && MusicFx.noteCount(level: 1) == 6 && MusicFx.noteCount(level: 9) == 6 && MusicFx.noteCount(level: -1) == 2)
        let quiet = MusicFx.notes(at: 3.3, level: 0, trackAge: 99).count, loud = MusicFx.notes(at: 3.3, level: 1, trackAge: 99).count
        check("notes-louder-more", loud > quiet)
        check("notes-bounded", MusicFx.notes(at: 7.1, level: 1, trackAge: 0.5).allSatisfy { $0.x > -0.2 && $0.x < 1.2 && $0.y > -0.2 && $0.y < 1.1 && $0.alpha >= 0 && $0.alpha <= 1 })
        check("burst-window", MusicFx.notes(at: 1, level: 0.5, trackAge: 0.4).count > MusicFx.notes(at: 1, level: 0.5, trackAge: 5).count && MusicFx.notes(at: 1, level: 0.5, trackAge: -1).count == MusicFx.notes(at: 1, level: 0.5, trackAge: 5).count)
        check("notes-deterministic", MusicFx.notes(at: 2.2, level: 0.7, trackAge: 0.2) == MusicFx.notes(at: 2.2, level: 0.7, trackAge: 0.2))

        // identificadores que acaban dentro de un script: solo con la forma exacta
        let goodSpotify = "spotify:track:6rqhFgbbKwnb9MLmUQDhG6", goodMusic = "A1B2C3D4E5F60789"
        check("id-valid", MusicScript.validID(goodSpotify, app: .spotify) && MusicScript.validID(goodMusic, app: .appleMusic))
        check("id-invalid", ["", "spotify:track:short", goodSpotify + "x", "spotify:track:6rqhFgbbKwnb9MLmUQDh\"&", "spotify:album:6rqhFgbbKwnb9MLmUQDhG6", "http://x"].allSatisfy { !MusicScript.validID($0, app: .spotify) }
              && ["a1b2c3d4e5f60789", "A1B2C3D4E5F6078", "A1B2C3D4E5F6078\"", "ZZZZZZZZZZZZZZZZ"].allSatisfy { !MusicScript.validID($0, app: .appleMusic) })
        check("id-cross-app", !MusicScript.validID(goodMusic, app: .spotify) && !MusicScript.validID(goodSpotify, app: .appleMusic))
        check("play-script", MusicScript.play(id: goodSpotify, app: .spotify)?.contains("play track \"\(goodSpotify)\"") == true && MusicScript.play(id: goodMusic, app: .appleMusic)?.contains("persistent ID is \"\(goodMusic)\"") == true)
        check("play-rejects-injection", MusicScript.play(id: "x\" & (do shell script \"id\") & \"", app: .spotify) == nil && MusicScript.play(id: goodMusic, app: .spotify) == nil)
        let withID = MusicScript.parse(["playing", "a", "b", "c", "1", "9000", "5", "", goodMusic].joined(separator: sep), app: .appleMusic)
        let badID = MusicScript.parse(["playing", "a", "b", "c", "1", "9000", "5", "", "x\" & evil"].joined(separator: sep), app: .appleMusic)
        check("parse-uri", withID?.uri == goodMusic && badID?.uri == nil && badID?.title == "a")

        // indice de recientes
        var idx = MusicIndex()
        let t1 = NowPlaying(app: .spotify, isPlaying: true, title: "Uno", artist: "A", album: "X", position: 0, duration: 100, volume: 50, artworkURL: nil, uri: goodSpotify)
        var t2 = t1; t2.title = "Dos"; t2.uri = nil
        idx.record(t1, at: Date(timeIntervalSince1970: 100)); idx.record(t2, at: Date(timeIntervalSince1970: 200))
        check("index-order", idx.recents(5).map(\.title) == ["Dos", "Uno"])
        idx.record(t1, at: Date(timeIntervalSince1970: 300))
        check("index-dedupe-and-bump", idx.tracks.count == 2 && idx.recents(1).first?.title == "Uno" && idx.recents(1).first?.plays == 2)
        var many = MusicIndex()
        for i in 0..<(MusicIndex.maxTracks + 20) { var n = t1; n.title = "t\(i)"; many.record(n, at: Date(timeIntervalSince1970: Double(i))) }
        check("index-cap", many.tracks.count == MusicIndex.maxTracks && many.tracks.first?.title == "t\(MusicIndex.maxTracks + 19)")
        let idxFile = NSTemporaryDirectory() + "music-index-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: idxFile) }
        idx.save(to: idxFile)
        check("index-roundtrip", MusicIndex.load(from: idxFile).tracks.map(\.title) == idx.tracks.map(\.title))
        check("index-file-0600", ((try? FileManager.default.attributesOfItem(atPath: idxFile)[.posixPermissions] as? Int) ?? 0) == 0o600)
        try? Data("{\"tracks\":[{\"id\":\"nothex\",\"app\":\"spotify\",\"title\":\"x\",\"artist\":\"\",\"album\":\"\",\"lastPlayed\":\"2026-01-01T00:00:00Z\",\"plays\":1}]}".utf8).write(to: URL(fileURLWithPath: idxFile))
        check("index-drops-invalid", MusicIndex.load(from: idxFile).tracks.isEmpty)
        try? Data("basura".utf8).write(to: URL(fileURLWithPath: idxFile))
        check("index-junk", MusicIndex.load(from: idxFile).tracks.isEmpty && MusicIndex.load(from: idxFile + ".no-existe").tracks.isEmpty)

        // cache de portadas
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "covers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let k = CoverCache.key("spotify|Taxi Cab|twenty one pilots|Vessel")
        check("cache-key", k.count == 24 && k.allSatisfy(\.isHexDigit) && k == CoverCache.key("spotify|Taxi Cab|twenty one pilots|Vessel") && k != CoverCache.key("spotify|Taxi Cab|twenty one pilots|Blurryface"))
        check("cache-key-rejects-traversal", CoverCache.file("../../etc/passwd", in: dir) == nil && CoverCache.file(k, in: dir) != nil)
        let big = NSImage(size: NSSize(width: 800, height: 800), flipped: false) { r in NSColor.systemPink.setFill(); r.fill(); return true }
        let tiff = big.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()   // como llega una portada real: comprimida
        check("cache-test-image-is-realistic", tiff.count > 0 && tiff.count < 4_000_000)
        check("cache-miss", CoverCache.load(k, in: dir) == nil)
        let stored = CoverCache.store(tiff, key: k, in: dir)
        check("cache-downscales", (stored.map { max($0.size.width, $0.size.height) <= CGFloat(CoverCache.maxPixels) } ?? false) && FileManager.default.fileExists(atPath: CoverCache.file(k, in: dir)!.path))
        check("cache-hit", CoverCache.load(k, in: dir) != nil)
        check("cache-rejects-garbage", CoverCache.store(Data("no soy una imagen".utf8), key: CoverCache.key("x"), in: dir) == nil && CoverCache.store(Data(count: 5_000_000), key: CoverCache.key("y"), in: dir) == nil)
        for i in 0..<12 { _ = CoverCache.store(tiff, key: CoverCache.key("t\(i)"), in: dir) }
        CoverCache.prune(in: dir, maxFiles: 5, maxBytes: 24 * 1024 * 1024)
        check("cache-prune-count", ((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.count ?? 99) <= 5)
        CoverCache.prune(in: dir, maxFiles: 80, maxBytes: 1)
        check("cache-prune-bytes", ((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.count ?? 99) == 0)

        // paleta de la portada
        func solid(_ r: Double, _ g: Double, _ b: Double, n: Int = 100) -> [(r: Double, g: Double, b: Double)] { Array(repeating: (r, g, b), count: n) }
        func hueOf(_ hex: UInt32) -> Double { CoverPalette.hsv(Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255).h }
        let red = CoverPalette.dominant(solid(0.8, 0.1, 0.1)), teal = CoverPalette.dominant(solid(0.1, 0.7, 0.7))
        check("paleta: rojo y verde azulado", red.map { hueOf($0) < 0.03 || hueOf($0) > 0.97 } == true && teal.map { abs(hueOf($0) - 0.5) < 0.04 } == true)
        check("paleta: grises, blancos, negros y vacio no dan color", CoverPalette.dominant(solid(0.5, 0.5, 0.5)) == nil && CoverPalette.dominant(solid(1, 1, 1)) == nil && CoverPalette.dominant(solid(0, 0, 0)) == nil && CoverPalette.dominant([]) == nil)
        check("paleta: manda el color que mas pesa", { let hex = CoverPalette.dominant(solid(0.1, 0.2, 0.9, n: 70) + solid(0.1, 0.9, 0.2, n: 30)); return hex.map { abs(hueOf($0) - 0.65) < 0.05 } ?? false }())
        check("paleta: un fondo gris no tapa el color", CoverPalette.dominant(solid(0.4, 0.4, 0.4, n: 90) + solid(0.9, 0.5, 0.1, n: 30)).map { abs(hueOf($0) - 0.08) < 0.04 } ?? false)
        check("paleta: ruido de color suelto no cuenta", CoverPalette.dominant(solid(0.4, 0.4, 0.4, n: 990) + solid(0.9, 0.1, 0.1, n: 5)) == nil)
        check("paleta: el acento sale vivo y claro", [red, teal].compactMap { $0 }.allSatisfy { h in let c = CoverPalette.hsv(Double(h >> 16 & 0xFF) / 255, Double(h >> 8 & 0xFF) / 255, Double(h & 0xFF) / 255); return c.s >= 0.55 && c.v >= 0.85 })
        let tealImage = NSImage(size: NSSize(width: 60, height: 60), flipped: false) { r in NSColor(calibratedRed: 0.1, green: 0.7, blue: 0.7, alpha: 1).setFill(); r.fill(); return true }
        let grayImage = NSImage(size: NSSize(width: 60, height: 60), flipped: false) { r in NSColor.gray.setFill(); r.fill(); return true }
        check("paleta: de una imagen real", CoverPalette.from(tealImage).map { abs(hueOf($0) - 0.5) < 0.05 } == true && CoverPalette.from(grayImage) == nil)
        check("paleta: fallback estable por titulo", CoverPalette.fallback(seed: "Taxi Cab") == CoverPalette.fallback(seed: "Taxi Cab") && CoverPalette.fallback(seed: "Taxi Cab") != CoverPalette.fallback(seed: "Heathens"))
        check("paleta: tres tonos validos y distintos", { let p = CoverPalette.palette(tint: 0xE0824F); return p.count == 3 && Set(p).count == 3 && p.allSatisfy { $0 <= 0xFFFFFF } && p[0] == 0xE0824F }())
        let c0 = CoverPalette.rgb(h: 0.33, s: 0.7, v: 0.8), c1 = CoverPalette.hsv(c0.r, c0.g, c0.b)
        check("paleta: hsv y rgb son inversos", abs(c1.h - 0.33) < 0.002 && abs(c1.s - 0.7) < 0.002 && abs(c1.v - 0.8) < 0.002)

        // los scripts tienen que compilar contra el diccionario real de cada app instalada (compilar no abre la app)
        for app in MusicApp.allCases where NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundle) != nil {
            for (label, source) in [("query", MusicScript.query(app)), ("playpause", MusicScript.command(.playPause, app: app)), ("seek", MusicScript.command(.seek(30), app: app)), ("volume", MusicScript.command(.volume(40), app: app)), ("play", MusicScript.play(id: app == .spotify ? "spotify:track:6rqhFgbbKwnb9MLmUQDhG6" : "A1B2C3D4E5F60789", app: app) ?? "")] {
                var error: NSDictionary?
                let ok = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
                check("compila-\(app.rawValue)-\(label)", ok)
            }
        }
        print(failures == 0 ? "MUSICA OK" : "MUSICA \(failures) FALLOS")
        return failures == 0
    }
}
