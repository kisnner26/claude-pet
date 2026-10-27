import SwiftUI
import AppKit

/// Portada de la cancion; sin imagen, un degradado propio que sale del titulo.
struct CoverArt: View {
    let cover: NSImage?
    let seed: String
    var body: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover).resizable().scaledToFill()
            } else {
                let h = Double(seed.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % 360) / 360   // estable entre arranques
                LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.75), Color(hue: (h + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 22, weight: .medium)).foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// Reproductor de la isla: portada, titulo, barra que se arrastra para saltar, controles y volumen.
struct MusicPanelContent: View {
    let now: NowPlaying
    let cover: NSImage?
    /// En vivo la posicion se interpola; en las capturas se fija.
    var fixedPosition: Double?
    var position: (TimeInterval) -> Double = { _ in 0 }
    var onToggle: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    var onSeek: (Double) -> Void = { _ in }
    var onVolume: (Int) -> Void = { _ in }
    @State private var scrub: Double?
    @State private var volume: Double = 50

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CoverArt(cover: cover, seed: now.title)
            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text([now.artist, now.album].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                }
                progress
                controls
            }
        }
        .onAppear { volume = Double(now.volume) }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let pos = fixedPosition ?? position(ProcessInfo.processInfo.systemUptime)
            let f = now.duration > 0 ? (scrub ?? pos / now.duration) : 0
            HStack(spacing: 7) {
                Text(MusicScript.clock(scrub.map { $0 * now.duration } ?? pos)).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 30, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white).frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, f)))))
                    }
                    .frame(height: 4).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { scrub = max(0, min(1, Double($0.location.x / max(1, geo.size.width)))) }
                        .onEnded { v in let f = max(0, min(1, Double(v.location.x / max(1, geo.size.width)))); scrub = nil; onSeek(f) })
                }.frame(height: 14)
                Text(MusicScript.clock(now.duration)).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 30, alignment: .leading)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: onPrevious) { Image(systemName: "backward.fill").font(.system(size: 13)) }.buttonStyle(.plain)
            Button(action: onToggle) {
                Image(systemName: now.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    .frame(width: 30, height: 30).background(Circle().fill(Color.white))
            }.buttonStyle(.plain)
            Button(action: onNext) { Image(systemName: "forward.fill").font(.system(size: 13)) }.buttonStyle(.plain)
            Spacer(minLength: 6)
            Image(systemName: volume < 1 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: max(3, geo.size.width * CGFloat(volume / 100)))
                }
                .frame(height: 4).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { volume = max(0, min(100, Double($0.location.x / max(1, geo.size.width)) * 100)) }
                    .onEnded { _ in onVolume(Int(volume.rounded())) })
            }.frame(width: 64, height: 14)
            Text(now.app.title).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.4)).fixedSize()
        }
        .foregroundColor(.white)
    }
}

/// El panel conectado al controlador real.
struct MusicPanelView: View {
    @ObservedObject var music: MusicController
    var body: some View {
        if let now = music.nowPlaying {
            MusicPanelContent(now: now, cover: music.cover, position: { music.position(at: $0) },
                              onToggle: { music.send(.playPause) }, onPrevious: { music.send(.previous) }, onNext: { music.send(.next) },
                              onSeek: { music.seek(toFraction: $0) }, onVolume: { music.send(.volume($0)) })
                .id(now.trackID)
        }
    }
}

/// Notas que suben de la mascota mientras suena algo; cuantas, segun el volumen.
struct MusicNotesLayer: View {
    @ObservedObject var music: MusicController
    var body: some View {
        if music.isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                FxCanvas(pixels: MusicFx.notes(at: ctx.date.timeIntervalSinceReferenceDate, level: Double(music.nowPlaying?.volume ?? 50) / 100,
                                               trackAge: ProcessInfo.processInfo.systemUptime - music.trackChangedAt), unit: 3)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-music <ruta.png>`: el reproductor con una cancion de ejemplo, parado y sonando.
    @MainActor static func music(to path: String) {
        let sample = NowPlaying(app: .spotify, isPlaying: true, title: "Taxi Cab", artist: "twenty one pilots", album: "Vessel", position: 74, duration: 262, volume: 70, artworkURL: nil)
        var paused = sample; paused.isPlaying = false; paused.app = .appleMusic; paused.title = "Heathens"; paused.album = "Suicide Squad"
        let view = VStack(alignment: .leading, spacing: 22) {
            MusicPanelContent(now: sample, cover: nil, fixedPosition: 74)
            MusicPanelContent(now: paused, cover: nil, fixedPosition: 190)
        }
        .padding(22).frame(width: 420).background(Color.black)
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

extension IslandSnapshot {
    /// `ClaudePet --snapshot-permission <ruta.png>`: la tarjeta de permiso con el aviso del perimetro (no persiste nada).
    @MainActor static func fence(to path: String) {
        let root = "/Users/demo/mi-app"
        PerimeterStore.shared.storagePath = nil      // la captura nunca escribe tu archivo real
        PerimeterStore.shared.upsert(Perimeter(root: root, allow: ["Sources/Auth"], mode: .ask))
        let inside = PermissionAsk(id: "a", session: "s", tool: "Edit", project: "mi-app", detail: root + "/Sources/Auth/Login.swift", canAlways: true, at: Date())
        let outside = PermissionAsk(id: "b", session: "s", tool: "Edit", project: "mi-app", detail: root + "/Sources/Billing/Charge.swift", canAlways: true, at: Date())
        let secret = PermissionAsk(id: "c", session: "s", tool: "Write", project: "mi-app", detail: root + "/Sources/Auth/.env", canAlways: false, at: Date())
        let view = VStack(spacing: 14) {
            PermissionCardView(store: PetStore.shared, ask: inside)
            PermissionCardView(store: PetStore.shared, ask: outside)
            PermissionCardView(store: PetStore.shared, ask: secret)
        }
        .padding(18).frame(width: 440).background(Color.black)
        let r = ImageRenderer(content: view); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
