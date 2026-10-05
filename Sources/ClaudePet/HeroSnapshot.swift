import SwiftUI
import AppKit

/// `ClaudePet --snapshot-hero <carpeta>`: renderiza las imagenes del README con el mismo codigo
/// de dibujo que usa la app (sprites, burbuja y escenario del partido).
@MainActor
enum HeroSnapshot {
    static func run(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        write(hero, to: dir + "/hero.png")
        write(states, to: dir + "/estados.png")
        write(football, to: dir + "/futbol.png")
    }

    private static func write<V: View>(_ view: V, to path: String) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func sprite(_ s: PetState, tick: Int, skin: Skin, unit u: CGFloat, cue: PeerCue? = nil) -> some View {
        Canvas { gc, _ in
            let px = skin == .block ? Sprite.block(s, tick: tick, cue: cue) : Sprite.classic(s, tick: tick, cue: cue)
            for p in px { gc.fill(Path(CGRect(x: CGFloat(p.x) * u, y: CGFloat(p.y) * u, width: u, height: u)), with: .color(p.c)) }
        }.frame(width: 16 * u, height: 16 * u)
    }

    private static let backdrop = LinearGradient(colors: [Color(hex: 0x2A2927), Color(hex: 0x141312)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static var hero: some View {
        VStack(spacing: 6) {
            BubbleCard(activity: Activity(title: "Editando PetStore.swift", subtitle: "mostrar la tarea exacta  desktop", origin: ""), state: .tool, flat: true)
                .scaleEffect(1.25).frame(width: 440, height: 90)
            sprite(.tool, tick: 3, skin: .block, unit: 14)
        }
        .frame(width: 720, height: 420)
        .background(backdrop)
    }

    static var states: some View {
        let order: [(PetState, Int, String)] = [(.idle, 0, "inactivo"), (.starting, 6, "iniciando"), (.thinking, 9, "pensando"),
                                                (.tool, 3, "herramienta"), (.waiting, 0, "aprobacion"), (.done, 0, "listo"), (.error, 1, "error")]
        return VStack(spacing: 14) {
            ForEach(Skin.allCases, id: \.self) { skin in
                HStack(spacing: 8) {
                    ForEach(order, id: \.2) { st, tk, name in
                        VStack(spacing: 4) {
                            sprite(st, tick: tk, skin: skin, unit: 9)
                            Text(name).font(.system(size: 11, design: .monospaced)).foregroundColor(Pal.cream.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(backdrop)
    }

    static var football: some View {
        let frames: [Double] = [1.0, 2.5, 3.3, 5.0, 7.3, 10.8]
        func cell(_ t: Double) -> some View {
            Canvas { gc, _ in
                let g = FootballChoreography.frame(elapsed: t, reduceMotion: false)
                let cue = PeerCue(state: .idle, greet: false, cheer: false, concern: false, game: g)
                for p in Sprite.block(.idle, tick: Int(t * 8), cue: cue) {
                    gc.fill(Path(CGRect(x: StageMetrics.petX + CGFloat(p.x) * 7, y: StageMetrics.petY + CGFloat(p.y) * 7, width: 7, height: 7)), with: .color(p.c))
                }
                var g2 = gc
                StageRenderer.draw(&g2, elapsed: t, reduceMotion: false, mirrored: false)
            }
            .frame(width: StageMetrics.width, height: StageMetrics.height)
            .background(Color(hex: 0x1C1B1A))
        }
        return VStack(spacing: 3) {
            HStack(spacing: 3) { ForEach(frames.prefix(3), id: \.self) { cell($0) } }
            HStack(spacing: 3) { ForEach(frames.suffix(3), id: \.self) { cell($0) } }
        }.background(Color.black)
    }
}
