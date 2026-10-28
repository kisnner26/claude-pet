import SwiftUI
import AppKit

extension IslandSnapshot {
    /// `ClaudePet --snapshot-rage <ruta.png>`: la mascota enfadada en cuatro momentos (gigante, caminando, patada, vuelta), claude y codex.
    @MainActor static func rage(to path: String) {
        let screen = CGSize(width: 900, height: 560), target = CGRect(x: 560, y: 150, width: 280, height: 300)
        func cell(_ agent: IslandAgentTab, _ t: TimeInterval) -> some View {
            ZStack {
                Color(hex: 0x1B1F2A)
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x2B3142)).frame(width: target.width, height: target.height).position(x: target.midX, y: target.midY)
                RageOverlay(store: PetStore.shared, agent: agent, start: 0, screen: screen, target: target, fixedTime: t)
            }.frame(width: screen.width, height: screen.height).clipped()
        }
        let times: [TimeInterval] = [0.7, 1.5, 2.3, 3.6]
        let view = VStack(spacing: 6) {
            ForEach([IslandAgentTab.claude, .codex], id: \.self) { a in
                HStack(spacing: 6) { ForEach(times, id: \.self) { t in cell(a, t).scaleEffect(0.5).frame(width: screen.width / 2, height: screen.height / 2) } }
            }
        }.background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
