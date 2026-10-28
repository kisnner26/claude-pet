import SwiftUI
import AppKit

/// La mascota de claude (bloque o clasico) dibujada en una caja cuadrada, con los atuendos indicados.
struct ClaudeSprite: View {
    var state: PetState = .idle
    var outfits: Set<Outfit> = []
    var tick = 3
    /// nil = el skin elegido por el usuario; si no, ese skin concreto (para las vistas previas).
    var skin: Skin?
    var body: some View {
        Canvas { gc, size in
            let s = skin ?? Sprite.skin
            var px = s == .block ? Sprite.block(state, tick: tick) : Sprite.classic(state, tick: tick)
            if s == .block { px = Wardrobe.compose(px, outfits: outfits, state: state, tick: tick) }
            PetFace.draw(&gc, size: size, pixels: px, pose: PetPose())
        }
        .accessibilityHidden(true)
    }
}

/// El avatar de codex, con su skin y sus atuendos.
struct CodexSprite: View {
    var face: CodexAvatar.Face = .prompt(cursor: true)
    var legs: CodexAvatar.Legs = .stand
    var skin: CodexSkin = .cloud
    var outfits: Set<Outfit> = []
    var body: some View {
        Canvas { gc, size in
            let u = min(size.width / CGFloat(CodexAvatar.width), size.height / CGFloat(CodexAvatar.height))
            let ox = (size.width - CGFloat(CodexAvatar.width) * u) / 2, oy = (size.height - CGFloat(CodexAvatar.height) * u) / 2
            for c in CodexAvatar.cells(legs: legs, face: face, skin: skin, outfits: outfits) {
                gc.fill(Path(CGRect(x: ox + CGFloat(c.x) * u, y: oy + CGFloat(c.y) * u, width: u + 0.4, height: u + 0.4)), with: .color(c.c))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Respiracion suave: una animacion de SwiftUI sobre el desplazamiento, sin volver a dibujar el sprite.
struct Breathing: ViewModifier {
    var enabled = true
    var delay = 0.0
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: enabled && up ? -2 : 0)
            .onAppear { if enabled { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay)) { up = true } } }
    }
}
extension View { func breathing(_ enabled: Bool = true, delay: Double = 0) -> some View { modifier(Breathing(enabled: enabled, delay: delay)) } }

extension IslandSnapshot {
    /// `ClaudePet --snapshot-outfits <ruta.png>`: cada atuendo en claude (bloque) y en las tres variantes de codex.
    @MainActor static func outfits(to path: String) {
        let sets: [(String, Set<Outfit>)] = [("sin nada", [])] + Outfit.allCases.map { ($0.title, [$0]) } + [("todos", Set(Outfit.allCases))]
        let view = VStack(alignment: .leading, spacing: 10) {
            row("claude") { set in ClaudeSprite(outfits: set, skin: .block) }
            ForEach(CodexSkin.allCases, id: \.self) { skin in row("codex \(skin.rawValue)") { set in CodexSprite(skin: skin, outfits: set) } }
        }
        func row<V: View>(_ name: String, _ make: @escaping (Set<Outfit>) -> V) -> some View {
            HStack(spacing: 10) {
                Text(name).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(width: 84, alignment: .leading)
                ForEach(Array(sets.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 3) { make(entry.1).frame(width: 84, height: 84); Text(entry.0).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5)) }
                }
            }
        }
        let host = view.padding(16).background(Color(hex: 0x15161C))
        let r = ImageRenderer(content: host); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-dance <ruta.png>`: Claude y Codex en cuatro instantes de un pulso, y sin escucha (volumen) y al pausar.
    @MainActor static func dance(to path: String) {
        let ages: [(String, MusicPulse)] = [
            ("pulso", MusicPulse(playing: true, listening: true, level: 0.9, bass: 1, mid: 0.6, treble: 0.3, beatAge: 0, beatCount: 2, bpm: 124)),
            ("+80 ms", MusicPulse(playing: true, listening: true, level: 0.85, bass: 0.8, mid: 0.5, treble: 0.4, beatAge: 0.08, beatCount: 2, bpm: 124)),
            ("+170 ms", MusicPulse(playing: true, listening: true, level: 0.7, bass: 0.5, mid: 0.4, treble: 0.3, beatAge: 0.17, beatCount: 2, bpm: 124)),
            ("siguiente", MusicPulse(playing: true, listening: true, level: 0.9, bass: 1, mid: 0.6, treble: 0.3, beatAge: 0, beatCount: 3, bpm: 124)),
            ("sin escucha", MusicPulse(playing: true, volume: 0.9)),
            ("al pausar", MusicPulse(playing: false, pausedAge: 0.6)),
        ]
        func scene(_ m: MusicPulse) -> PetScene { var s = PetScene(state: .idle, dancing: m.playing); s.music = m; return s }
        let worn: Set<Outfit> = [.headphones]
        let view = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(ages.enumerated()), id: \.offset) { _, entry in
                    let pose = PetAnimator.pose(at: 0.125, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: scene(entry.1))
                    VStack(spacing: 4) {
                        ZStack {
                            Canvas { gc, size in
                                let px = PetAnimator.apply(Wardrobe.compose(Sprite.block(.idle, tick: 3), outfits: worn, state: .idle, tick: 3), pose: pose)
                                PetFace.draw(&gc, size: size, pixels: px, pose: PetPose())
                            }.frame(width: 84, height: 84)
                            FxCanvas(pixels: MusicFx.beat(pulse: entry.1), unit: 3).frame(width: 104, height: 100)
                        }.frame(width: 104, height: 100)
                        Text(entry.0).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(ages.enumerated()), id: \.offset) { _, entry in
                    let pose = PetAnimator.pose(at: 0.125, gaze: .zero, pokes: [], hopStart: nil, motion: true, scene: scene(entry.1))
                    ZStack {
                        CodexMiniFrame(face: .prompt(cursor: true), legs: .stand, tick: 0, skin: .cloud, wave: false, pose: pose, outfits: worn).frame(width: 84, height: 84)
                        FxCanvas(pixels: MusicFx.beat(pulse: entry.1), unit: 3).frame(width: 104, height: 100)
                    }.frame(width: 104, height: 100)
                }
            }
        }
        .padding(16).background(Color(hex: 0x15161C))
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-vinyl <ruta.png>`: el escenario con vinilo, resplandor y colores de una portada; sonando, pausado y sin portada.
    @MainActor static func vinyl(to path: String) {
        func cover(_ a: NSColor, _ b: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 96, height: 96), flipped: false) { r in
                NSGradient(starting: a, ending: b)?.draw(in: r, angle: 55)
                NSColor.white.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: 30, y: 30, width: 36, height: 36)).fill(); return true
            }
        }
        let covers: [(String, NSImage?, String, Bool, Double)] = [
            ("sonando, en el pulso", cover(NSColor(calibratedRed: 0.1, green: 0.55, blue: 0.85, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.4, alpha: 1)), "Heathens", true, 1),
            ("sonando, otra canción", cover(NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.3, alpha: 1), NSColor(calibratedRed: 0.4, green: 0.05, blue: 0.1, alpha: 1)), "Ride", true, 0.2),
            ("pausado", cover(NSColor(calibratedRed: 0.2, green: 0.75, blue: 0.45, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.3, blue: 0.2, alpha: 1)), "Holding On", false, 0),
            ("sin portada aún", nil, "Nico", true, 0),
        ]
        let view = HStack(spacing: 14) {
            ForEach(Array(covers.enumerated()), id: \.offset) { _, c in
                let hex = c.1.flatMap { CoverPalette.from($0) } ?? CoverPalette.fallback(seed: c.2)
                let colors = CoverPalette.palette(tint: hex)
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        if c.3 { Circle().fill(Color(hex: hex)).frame(width: 96, height: 96).blur(radius: 26).opacity(0.16 + 0.34 * c.4) }
                        FxCanvas(pixels: c.3 ? MusicFx.notes(at: 3.3, level: 0.7, trackAge: 9, colors: colors) + MusicFx.beat(pulse: MusicPulse(playing: true, listening: true, level: 0.9, bass: c.4, mid: 0.5, treble: 0.3, beatAge: 0.04), colors: colors) : [], unit: 3).frame(width: 104, height: 100)
                        ClaudeSprite(outfits: [.headphones]).frame(width: 84, height: 84)
                        VinylDisc(cover: c.1, seed: c.2, tint: Color(hex: hex), playing: c.3, beat: c.4)
                            .frame(width: 104, height: 100, alignment: .topTrailing).offset(x: 2, y: -2)
                    }.frame(width: 104, height: 100)
                    Text(c.0).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    MusicPanelContent(now: NowPlaying(app: .spotify, isPlaying: c.3, title: c.2, artist: "twenty one pilots", album: "", position: 74, duration: 262, volume: 70, artworkURL: nil, uri: nil), cover: c.1, fixedPosition: 74, accent: Color(hex: hex))
                        .frame(width: 330)
                }
            }
        }
        .padding(16).background(Color(hex: 0x15161C))
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-dock <ruta.png>`: el acceso rapido en reposo, con cambios, y siguiendo a la app activa (editor, terminal, navegador, musica, Finder).
    @MainActor static func dock(to path: String) {
        let store = PetStore.shared
        func icon(_ bundle: String) -> NSImage? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) } }
        let base = QuickContext(hasWorkspace: true, isRepo: true, changeCount: 4, agentChanges: 3, commiteroAvailable: true, terminalAvailable: true, musicAvailable: true, hasRemote: true)
        func ctx(_ p: AppProfile, _ name: String?) -> QuickContext { var c = base; c.profile = p; c.frontAppName = name; return c }
        let rows: [(String, QuickContext, NSImage?)] = [
            ("en reposo, sin proyecto", QuickContext(), nil),
            ("otra app (tus acciones de siempre)", base, nil),
            ("Xcode", ctx(.editor, "Xcode"), icon("com.apple.dt.Xcode")),
            ("Terminal", ctx(.terminal, "Terminal"), icon("com.apple.Terminal")),
            ("Safari", ctx(.browser, "Safari"), icon("com.apple.Safari")),
            ("Spotify", ctx(.music, "Spotify"), icon("com.spotify.client")),
            ("Finder", ctx(.finder, "Finder"), icon("com.apple.finder")),
        ]
        let view = VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 5) {
                    Text(r.0).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                    QuickDock(store: store, music: store.music, plugins: store.plugins, summary: { "" }, contextOverride: r.1, iconOverride: r.2, hideOverflow: true)
                }
            }
        }
        .padding(18).frame(width: 420, alignment: .leading).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black)).padding(14).background(Color(hex: 0x1A1B22))
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// Herramienta de diseno: imprime las rejillas de las mascotas en ASCII para dibujar atuendos encima con exactitud.
enum MascotGrids {
    static func hex(_ c: Color) -> UInt32 {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        func b(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return b(n.redComponent) << 16 | b(n.greenComponent) << 8 | b(n.blueComponent)
    }

    static func dump() {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var legend: [UInt32: Character] = [:]
        func ch(_ h: UInt32) -> Character { if let c = legend[h] { return c }; let c = legend.count < letters.count ? letters[legend.count] : "?"; legend[h] = c; return c }
        func grid(_ title: String, _ w: Int, _ hgt: Int, _ cells: [(Int, Int, UInt32)]) {
            var rows = Array(repeating: Array(repeating: Character("."), count: w), count: hgt)
            for (x, y, h) in cells where x >= 0 && x < w && y >= 0 && y < hgt { rows[y][x] = ch(h) }
            print("== \(title) \(w)x\(hgt)")
            print("    " + (0..<w).map { String($0 % 10) }.joined())
            for (y, r) in rows.enumerated() { print(String(format: "%2d  ", y) + String(r)) }
        }
        grid("claude block idle", 16, 16, Sprite.block(.idle, tick: 3).map { ($0.x, $0.y, hex($0.c)) })
        grid("codex cloud", CodexAvatar.width, CodexAvatar.height, CodexAvatar.cells(legs: .stand, face: .prompt(cursor: true)).map { ($0.x, $0.y, hex($0.c)) })
        print("== leyenda")
        for (h, c) in legend.sorted(by: { $0.value < $1.value }) { print("\(c) = #" + String(h, radix: 16, uppercase: true)) }
    }
}
