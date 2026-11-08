import AppKit
import SwiftUI

/// El sprite de claude pet como icono de 8 bits para botones del sistema (la tecla de la tira de control de la Touch Bar).
/// Cada celda es un cuadro de 1,5 pt (3 px en pantalla retina): ni un solo pixel borroso.
@MainActor enum PixelIcon {
    static let cell: CGFloat = 1.5

    static func claude() -> NSImage {
        let px = Sprite.pixels(.idle, tick: 0)
        guard let minX = px.map(\.x).min(), let maxX = px.map(\.x).max(), let minY = px.map(\.y).min(), let maxY = px.map(\.y).max() else { return NSImage() }
        let size = NSSize(width: CGFloat(maxX - minX + 1) * cell, height: CGFloat(maxY - minY + 1) * cell)
        return NSImage(size: size, flipped: true) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.shouldAntialias = false
            for p in px {
                NSColor(p.c).setFill()
                NSRect(x: CGFloat(p.x - minX) * cell, y: CGFloat(p.y - minY) * cell, width: cell, height: cell).fill()
            }
            return true
        }
    }

    /// Para revisarlo a ojo: el icono ampliado sobre el negro de la barra.
    static func snapshot(to path: String) {
        let icon = claude()
        let scale: CGFloat = 12
        let view = Image(nsImage: icon).interpolation(.none).resizable().frame(width: icon.size.width * scale, height: icon.size.height * scale).padding(24).background(Color.black)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    /// El sprite sin escalar (una celda = un pixel, fondo transparente) de cada estado, para componer iconos con otras herramientas.
    static func dumpSprites(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, state, tick) in [("idle0", PetState.idle, 0), ("idle40", .idle, 40), ("thinking", .thinking, 0), ("tool", .tool, 0), ("done", .done, 0)] as [(String, PetState, Int)] {
            let px = Sprite.pixels(state, tick: tick)
            guard let minX = px.map(\.x).min(), let maxX = px.map(\.x).max(), let minY = px.map(\.y).min(), let maxY = px.map(\.y).max() else { continue }
            let w = maxX - minX + 1, h = maxY - minY + 1
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            guard let data = rep.bitmapData else { continue }
            for i in 0..<(rep.bytesPerRow * h) { data[i] = 0 }
            for p in px {
                let c = NSColor(p.c).usingColorSpace(.sRGB) ?? .clear
                let o = (p.y - minY) * rep.bytesPerRow + (p.x - minX) * 4
                data[o] = UInt8((c.redComponent * 255).rounded()); data[o + 1] = UInt8((c.greenComponent * 255).rounded())
                data[o + 2] = UInt8((c.blueComponent * 255).rounded()); data[o + 3] = UInt8((c.alphaComponent * 255).rounded())
            }
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: dir + "/" + name + ".png")) }
        }
    }
}
