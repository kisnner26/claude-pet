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
        write(companion, to: dir + "/companero.png")
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

    // MARK: escena con las dos mascotas como ventanas independientes (como en pantalla)

    static let sceneSize = CGSize(width: 520, height: 270)

    /// Dibuja a Claude y a Codex cada una en su ventana (posiciones distintas) y, si hay `elapsed`, el partido entre ambas.
    static func scene(elapsed: Double?, info: CompanionInfo, look: Int, reduce: Bool = false, label: String? = nil) -> some View {
        let claudeFrame = CGRect(x: 290, y: 30, width: 128, height: 128)    // coordenadas de pantalla: origen abajo a la izquierda
        let codexFrame = CGRect(x: 80, y: 30, width: 128, height: 152)
        let geo = GameLayout.make(claude: claudeFrame, codex: codexFrame)
        return Canvas { gc, sz in
            func tl(_ r: CGRect) -> CGPoint { CGPoint(x: r.minX, y: sz.height - r.maxY) }
            let game = elapsed.flatMap { FootballChoreography.frame(elapsed: $0, reduceMotion: reduce) }
            let cue = PeerCue(state: info.codex, greet: false, cheer: false, concern: false, game: game, companion: true, lookX: look)
            let co = tl(claudeFrame)
            for p in Sprite.block(info.claude, tick: Int((elapsed ?? 0.25) * 8), cue: cue) {
                gc.fill(Path(CGRect(x: co.x + StageMetrics.petX + CGFloat(p.x) * 7, y: co.y + StageMetrics.petY + CGFloat(p.y) * 7, width: 7, height: 7)), with: .color(p.c))
            }
            var g1 = gc
            let cx = tl(codexFrame)
            g1.translateBy(x: cx.x, y: cx.y)
            CodexRenderer.draw(&g1, now: Date(timeIntervalSinceReferenceDate: 100.1 + (elapsed ?? 0)), info: info, game: game,
                               reduceMotion: reduce, animate: true, facing: 1)
            if let e = elapsed, let geo {
                var g2 = gc
                let o = tl(geo.stageFrame)
                g2.translateBy(x: o.x, y: o.y)
                GameRenderer.draw(&g2, elapsed: e, reduceMotion: reduce, geo: geo)
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .background(Color(hex: 0x1C1B1A))
        .overlay(alignment: .topLeading) {
            if let label { Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(Color.white.opacity(0.45)).padding(8) }
        }
    }

    private static let calm = CompanionInfo(codex: .idle, claude: .idle, codexCheer: false, codexConcern: false, claudeDone: false)

    static var football: some View {
        let frames: [Double] = [1.0, 1.55, 2.6, 3.3, 5.0, 10.8]
        return VStack(spacing: 3) {
            HStack(spacing: 3) { ForEach(frames.prefix(3), id: \.self) { scene(elapsed: $0, info: calm, look: 0) } }
            HStack(spacing: 3) { ForEach(frames.suffix(3), id: \.self) { scene(elapsed: $0, info: calm, look: 0) } }
        }.background(Color.black)
    }

    /// Hoja de revision del partido: normal arriba, reducir movimiento abajo (`ClaudePet --snapshot-football`).
    static func footballSheet(to path: String) {
        let times: [Double] = [0.6, 2.0, 3.0, 3.8, 4.8, 6.4, 7.3, 8.4, 9.0, 10.3, 11.2]
        let view = VStack(spacing: 2) {
            ForEach([false, true], id: \.self) { reduce in
                HStack(spacing: 2) { ForEach(times.prefix(4), id: \.self) { scene(elapsed: $0, info: calm, look: 0, reduce: reduce) } }
                HStack(spacing: 2) { ForEach(times.dropFirst(4).prefix(4), id: \.self) { scene(elapsed: $0, info: calm, look: 0, reduce: reduce) } }
                HStack(spacing: 2) { ForEach(times.suffix(3), id: \.self) { scene(elapsed: $0, info: calm, look: 0, reduce: reduce) } }
            }
        }.background(Color.black)
        write(view, to: path)
    }

    /// Codex junto a Claude en distintas situaciones (cada uno en su propia ventana).
    static var companion: some View {
        func i(_ codex: PetState, claude: PetState = .idle, cheer: Bool = false, done: Bool = false) -> CompanionInfo {
            CompanionInfo(codex: codex, claude: claude, codexCheer: cheer, codexConcern: false, claudeDone: done)
        }
        let cases: [(String, CompanionInfo, Int)] = [
            ("reposo", i(.idle), 0), ("codex piensa", i(.thinking), -1), ("codex teclea", i(.tool), -1),
            ("codex pide permiso", i(.waiting), -1), ("codex termina", i(.done, cheer: true), 0), ("codex falla", i(.error), 0),
            ("claude piensa", i(.idle, claude: .thinking), 0), ("claude espera", i(.idle, claude: .waiting), 0),
            ("claude termina", i(.idle, claude: .done, done: true), 0),
        ]
        return VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { c in scene(elapsed: nil, info: cases[r * 3 + c].1, look: cases[r * 3 + c].2, label: cases[r * 3 + c].0) } }
            }
        }.background(Color.black)
    }
}
