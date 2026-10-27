import SwiftUI

/// Brillo de color del fondo de la isla segun lo que pasa: la isla "se enciende" con el estado.
enum IslandGlow {
    struct Glow: Equatable { let hex: UInt32; let strength: Double }

    /// El estado que manda: mareo, permiso, error, terminado y trabajando, en ese orden. nil = sin brillo.
    static func glow(state: PetState, codex: PetState, reason: IslandReason, asking: Bool, dizzy: Bool) -> Glow? {
        if dizzy { return Glow(hex: 0xC25AA0, strength: 0.34) }
        if asking || state == .waiting || codex == .waiting { return Glow(hex: 0xE7B45B, strength: 0.34) }
        if state == .error || codex == .error { return Glow(hex: 0xD85C5C, strength: 0.32) }
        if reason == .finished { return Glow(hex: 0x6CCB8A, strength: 0.34) }
        let working: Set<PetState> = [.thinking, .tool, .starting]
        if working.contains(state) || working.contains(codex) { return Glow(hex: 0x5270E8, strength: 0.16) }
        return nil
    }
}

struct IslandGlowView: View {
    let glow: IslandGlow.Glow?
    var body: some View {
        Circle()
            .fill(Color(hex: glow?.hex ?? 0x000000))
            .frame(width: 280, height: 280)
            .blur(radius: 48)
            .opacity(glow?.strength ?? 0)
            .offset(x: -110, y: -150)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Pista de atajo de teclado dentro de un boton.
struct IslandKeyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 8, weight: .medium, design: .monospaced))
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.18)))
    }
}

/// Aviso de la mascota mareada por demasiados toques, con cuenta atras.
struct IslandDizzyNotice: View {
    let seconds: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("demasiados toques").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            Text("dame un segundo: vuelvo al trabajo en \(seconds) \(seconds == 1 ? "segundo" : "segundos").")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tarjeta de "terminó": proyecto, ultimo paso y dos botones.
struct IslandFinishedCard: View {
    @ObservedObject var store: PetStore
    var onDismiss: () -> Void
    var body: some View {
        let agent = store.state == .done ? "claude code" : "codex"
        let step = store.recentIslandSteps.last
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.terminalProject.isEmpty ? "proyecto" : store.terminalProject).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                Text("\(agent) terminó").font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
            }
            Text(step.map { $0.label } ?? "tarea completada").font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            HStack(spacing: 8) {
                IslandActionButton(title: "abrir terminal", fill: .white, ink: .black) { store.focusTerminal(); onDismiss() }
                if CommiteroLauncher.available(), !store.mission.workspace.isEmpty {
                    IslandActionButton(title: "commitear", fill: Color(hex: 0x2966ED), ink: .white) { CommiteroLauncher.launch(workspace: store.mission.workspace); onDismiss() }
                }
                IslandActionButton(title: "ok", fill: Color.white.opacity(0.12), ink: .white) { onDismiss() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Zona para soltar archivos: borde discontinuo y, tras soltar, una barra que se llena mientras la mascota "traga".
struct IslandDropZone: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let now = ProcessInfo.processInfo.systemUptime
            let progress = model.swallowStart.map { min(1, max(0, (now - $0) / 0.7)) }
            VStack(spacing: 6) {
                if let progress {
                    Text("copiando referencia").font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(width: 200, height: 4)
                        Capsule().fill(Color(hex: 0x6CCB8A)).frame(width: 200 * progress, height: 4)
                    }
                } else {
                    Text("suelta tus archivos").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.8))
                    Text("pdf · imágenes · código · documentos").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }
}
