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

        check("cmd-playpause", MusicScript.command(.playPause, app: .spotify) == "tell application id \"com.spotify.client\" to playpause")
        check("cmd-next", MusicScript.command(.next, app: .appleMusic) == "tell application id \"com.apple.Music\" to next track")
        check("cmd-seek-clamp", MusicScript.command(.seek(-5), app: .spotify).hasSuffix("to 0") && MusicScript.command(.seek(999_999), app: .spotify).hasSuffix("to 86400"))
        check("cmd-volume-clamp", MusicScript.command(.volume(250), app: .appleMusic).hasSuffix("to 100") && MusicScript.command(.volume(-3), app: .appleMusic).hasSuffix("to 0"))
        check("query-has-no-user-input", MusicScript.query(.spotify).contains("artwork url") && !MusicScript.query(.appleMusic).contains("artwork url"))
        check("clock", MusicScript.clock(0) == "0:00" && MusicScript.clock(75.9) == "1:15" && MusicScript.clock(-3) == "0:00")

        // reaccion visual
        check("notes-scale", MusicFx.noteCount(level: 0) == 2 && MusicFx.noteCount(level: 1) == 6 && MusicFx.noteCount(level: 9) == 6 && MusicFx.noteCount(level: -1) == 2)
        let quiet = MusicFx.notes(at: 3.3, level: 0, trackAge: 99).count, loud = MusicFx.notes(at: 3.3, level: 1, trackAge: 99).count
        check("notes-louder-more", loud > quiet)
        check("notes-bounded", MusicFx.notes(at: 7.1, level: 1, trackAge: 0.5).allSatisfy { $0.x > -0.2 && $0.x < 1.2 && $0.y > -0.2 && $0.y < 1.1 && $0.alpha >= 0 && $0.alpha <= 1 })
        check("burst-window", MusicFx.notes(at: 1, level: 0.5, trackAge: 0.4).count > MusicFx.notes(at: 1, level: 0.5, trackAge: 5).count && MusicFx.notes(at: 1, level: 0.5, trackAge: -1).count == MusicFx.notes(at: 1, level: 0.5, trackAge: 5).count)
        check("notes-deterministic", MusicFx.notes(at: 2.2, level: 0.7, trackAge: 0.2) == MusicFx.notes(at: 2.2, level: 0.7, trackAge: 0.2))

        // los scripts tienen que compilar contra el diccionario real de cada app instalada (compilar no abre la app)
        for app in MusicApp.allCases where NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundle) != nil {
            for (label, source) in [("query", MusicScript.query(app)), ("playpause", MusicScript.command(.playPause, app: app)), ("seek", MusicScript.command(.seek(30), app: app)), ("volume", MusicScript.command(.volume(40), app: app))] {
                var error: NSDictionary?
                let ok = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
                check("compila-\(app.rawValue)-\(label)", ok)
            }
        }
        print(failures == 0 ? "MUSICA OK" : "MUSICA \(failures) FALLOS")
        return failures == 0
    }
}
