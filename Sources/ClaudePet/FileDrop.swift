import AppKit
import SwiftUI

/// Soltar archivos sobre la isla: la mascota "se los traga" y deja `@ruta` en el portapapeles, listo para pegar en la sesion.
/// Nunca abre ni lee los archivos: solo usa sus rutas.
enum FileDrop {
    static let maxFiles = 10
    static let maxPath = 1024

    /// `@/ruta/archivo`, entre comillas si la ruta tiene espacios. nil si no es un archivo local valido.
    static func reference(for url: URL) -> String? {
        guard url.isFileURL else { return nil }
        let path = url.path.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        guard !path.isEmpty, path == url.path, path.count <= maxPath, path.hasPrefix("/") else { return nil }
        return path.contains(where: { $0.isWhitespace }) ? "@\"\(path)\"" : "@\(path)"
    }

    /// Las referencias de varios archivos separadas por espacios, con tope de `maxFiles`. Sin duplicados.
    static func text(for urls: [URL]) -> String? {
        var seen = Set<String>(), out: [String] = []
        for url in urls {
            guard let ref = reference(for: url), seen.insert(ref).inserted else { continue }
            out.append(ref)
            if out.count == maxFiles { break }
        }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    /// Copia las referencias al portapapeles y devuelve el texto copiado. nil si no habia archivos validos.
    @discardableResult
    static func deliver(_ urls: [URL], to pasteboard: NSPasteboard = .general) -> String? {
        guard let text = text(for: urls) else { return nil }
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        return text
    }

    /// La mascota convertida en caja de carton, abierta mientras espera el archivo.
    static func boxPixels(open: Bool) -> [Px] {
        let card = Color(hex: 0xC9A06B), dark = Color(hex: 0x9C7A4A), tape = Color(hex: 0xE8D9B5)
        var out: [Px] = []
        for y in 6...13 { for x in 2...13 { out.append(Px(x: x, y: y, c: card)) } }
        for x in 2...13 { out.append(Px(x: x, y: 13, c: dark)) }
        for y in 6...13 { out.append(Px(x: 13, y: y, c: dark)) }
        for y in 6...9 { out.append(Px(x: 7, y: y, c: tape)); out.append(Px(x: 8, y: y, c: tape)) }
        if open {
            // solapas abiertas hacia arriba y una sombra dentro
            for x in 2...6 { out.append(Px(x: x, y: 4, c: card)); out.append(Px(x: x, y: 5, c: dark)) }
            for x in 9...13 { out.append(Px(x: x, y: 4, c: card)); out.append(Px(x: x, y: 5, c: dark)) }
        } else {
            for x in 2...13 { out.append(Px(x: x, y: 5, c: dark)) }
        }
        return out
    }
}

/// Contenedor plano (NSView) que recibe los archivos soltados y deja que SwiftUI dibuje dentro.
/// SwiftUI administra el registro de arrastre de su propia vista, asi que el destino va fuera de ella.
final class DropContainerView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onFiles: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func files(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let n = files(sender).count
        IslandController.log("draggingEntered archivos=\(n)")
        guard n > 0 else { return [] }
        onHover(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { IslandController.log("draggingExited"); onHover(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(sender)
        IslandController.log("performDragOperation archivos=\(urls.count)")
        onHover(false)
        guard !urls.isEmpty else { return false }
        onFiles(urls)
        return true
    }
}
