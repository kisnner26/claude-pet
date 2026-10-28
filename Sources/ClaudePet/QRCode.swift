import AppKit
import CoreImage.CIFilterBuiltins

/// Código QR de un texto, con modulos nitidos y margen para que la camara lo lea desde el monitor.
enum QRCode {
    static func image(_ text: String, side: CGFloat) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scale = max(1, Int(side / out.extent.width))
        let big = out.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let rep = NSCIImageRep(ciImage: big)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        // fondo blanco con margen: un QR sobre fondo oscuro no se lee
        let pad: CGFloat = 8
        let framed = NSImage(size: NSSize(width: rep.size.width + pad * 2, height: rep.size.height + pad * 2))
        framed.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: framed.size).fill(); img.draw(at: NSPoint(x: pad, y: pad), from: .zero, operation: .sourceOver, fraction: 1); framed.unlockFocus()
        return framed
    }
}
