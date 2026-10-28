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
