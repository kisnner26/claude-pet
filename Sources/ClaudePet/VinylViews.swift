import SwiftUI
import AppKit

/// Un disco de vinilo con la portada de etiqueta. Gira mientras suena y un brazo de tocadiscos baja sobre el surco.
struct VinylDisc: View {
    let cover: NSImage?
    let seed: String
    let tint: Color
    let playing: Bool
    /// Latido del bombo, 0...1: el disco se hincha un poco en cada pulso.
    var beat: Double = 0
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !playing)) { ctx in
                disc.rotationEffect(.degrees(playing ? (ctx.date.timeIntervalSinceReferenceDate * 200).truncatingRemainder(dividingBy: 360) : 0))
            }
            arm
        }
        .frame(width: size * 1.25, height: size)
        .scaleEffect(1 + 0.07 * beat)
        .accessibilityHidden(true)
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color(hex: 0x0B0B0E))
            ForEach([0.9, 0.78, 0.66, 0.54], id: \.self) { f in Circle().stroke(Color.white.opacity(0.07), lineWidth: 0.6).frame(width: size * f, height: size * f) }
            // brillo del vinilo: dos destellos opuestos
            Circle().trim(from: 0.04, to: 0.14).stroke(Color.white.opacity(0.22), lineWidth: 1.4).frame(width: size * 0.84, height: size * 0.84)
            Circle().trim(from: 0.54, to: 0.64).stroke(Color.white.opacity(0.16), lineWidth: 1.4).frame(width: size * 0.84, height: size * 0.84)
            CoverArt(cover: cover, seed: seed, size: size * 0.4).clipShape(Circle())
            Circle().fill(Color.black).frame(width: size * 0.06, height: size * 0.06)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(tint.opacity(0.55), lineWidth: 1))
        .shadow(color: tint.opacity(0.35), radius: 4)
        .offset(x: -size * 0.1)
    }

    /// El brazo descansa fuera del disco y baja al empezar la musica.
    private var arm: some View {
        Capsule().fill(Color.white.opacity(0.7)).frame(width: size * 0.5, height: 2)
            .overlay(alignment: .leading) { Circle().fill(tint).frame(width: 4, height: 4) }
            .rotationEffect(.degrees(playing ? -32 : 48), anchor: .trailing)      // girado hacia abajo: apoyado en el surco; hacia arriba: en reposo
            .offset(x: size * 0.18, y: -size * 0.12)
            .animation(.easeInOut(duration: 0.7), value: playing)
    }
}

/// Resplandor detras de la mascota con el color de la portada: late con el bombo o, sin escucha, respira despacio.
struct MusicGlow: View {
    @ObservedObject var music: MusicController
    let store: PetStore
    var body: some View {
        if music.isPlaying, let hex = store.musicAccent {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
                let now = ProcessInfo.processInfo.systemUptime
                let pulse = store.musicPulse(at: now)
                let beat = pulse?.listening == true ? MusicDance.envelope(beatAge: pulse?.beatAge ?? 9) * (0.4 + 0.6 * (pulse?.bass ?? 0)) : 0.0
                let calm = 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 1.6)
                Circle().fill(Color(hex: hex)).frame(width: 96, height: 96).blur(radius: 26)
                    .opacity(0.16 + 0.34 * beat + (pulse?.listening == true ? 0 : 0.08 * calm))
                    .scaleEffect(1 + 0.18 * beat)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
