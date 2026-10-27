import Foundation
import AppKit

/// `ClaudePet --selftest-drop`: formato de las referencias de archivos soltados.
/// Arrastre simulado: lo justo de NSDraggingInfo para probar el destino sin raton ni ventanas.
private final class FakeDrag: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
    var numberOfValidItemsForDrop = 0
    var animatesToDestination = false
    var draggingFormation: NSDraggingFormation = .default
}

enum FileDropSelfTest {
    @MainActor static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        check("un archivo se convierte en @ruta", FileDrop.reference(for: URL(fileURLWithPath: "/Users/x/a.swift")) == "@/Users/x/a.swift")
        check("una ruta con espacios va entre comillas", FileDrop.reference(for: URL(fileURLWithPath: "/Users/x/mi carpeta/a b.txt")) == "@\"/Users/x/mi carpeta/a b.txt\"")
        check("una url web se rechaza", FileDrop.reference(for: URL(string: "https://example.com/a.txt")!) == nil)
        check("una ruta de mas de 1024 caracteres se rechaza", FileDrop.reference(for: URL(fileURLWithPath: "/" + String(repeating: "a", count: 1100))) == nil)
        check("una ruta con salto de linea se rechaza", FileDrop.reference(for: URL(fileURLWithPath: "/tmp/a\nrm -rf")) == nil)
        let two = [URL(fileURLWithPath: "/a/1.txt"), URL(fileURLWithPath: "/a/2.txt")]
        check("varios archivos se separan por espacios", FileDrop.text(for: two) == "@/a/1.txt @/a/2.txt")
        check("los duplicados se ignoran", FileDrop.text(for: two + two) == "@/a/1.txt @/a/2.txt")
        check("se acota a 10 archivos", FileDrop.text(for: (0..<30).map { URL(fileURLWithPath: "/a/\($0).txt") })?.split(separator: " ").count == 10)
        check("sin archivos validos no hay texto", FileDrop.text(for: [URL(string: "https://x.com")!]) == nil && FileDrop.text(for: []) == nil)
        check("la caja cabe en la rejilla y cambia al abrirse", FileDrop.boxPixels(open: true).allSatisfy { (0..<16).contains($0.x) && (0..<16).contains($0.y) } && FileDrop.boxPixels(open: true).count != FileDrop.boxPixels(open: false).count)
        // el destino de arrastre de la isla, con un arrastre simulado
        let container = DropContainerView(frame: NSRect(x: 0, y: 0, width: 720, height: 320))
        var hover: [Bool] = [], received: [URL] = []
        container.onHover = { hover.append($0) }
        container.onFiles = { received = $0 }
        let board = NSPasteboard(name: NSPasteboard.Name("claudepet-selftest-drag"))
        defer { board.releaseGlobally() }
        let file = URL(fileURLWithPath: "/tmp/informe de prueba.txt")
        board.clearContents(); board.writeObjects([file as NSURL])
        check("un archivo arrastrado encima activa la caja y se acepta como copia", container.draggingEntered(FakeDrag(pasteboard: board)) == .copy && hover == [true])
        check("salir del destino apaga la caja", { container.draggingExited(FakeDrag(pasteboard: board)); return hover == [true, false] }())
        board.clearContents(); board.writeObjects([file as NSURL])
        check("soltar entrega los archivos y apaga la caja", container.performDragOperation(FakeDrag(pasteboard: board)) && received == [file] && hover.last == false)
        board.clearContents(); board.setString("solo texto", forType: .string)
        hover = []
        check("un arrastre de texto se rechaza y no activa la caja", container.draggingEntered(FakeDrag(pasteboard: board)) == [] && hover.isEmpty)
        check("soltar texto no entrega nada", !container.performDragOperation(FakeDrag(pasteboard: board)))
        // entregar: deja la referencia en el portapapeles
        let clip = NSPasteboard(name: NSPasteboard.Name("claudepet-selftest-clip"))
        defer { clip.releaseGlobally() }
        check("entregar copia @ruta al portapapeles", FileDrop.deliver([file], to: clip) == "@\"/tmp/informe de prueba.txt\"" && clip.string(forType: .string) == "@\"/tmp/informe de prueba.txt\"")
        check("entregar sin archivos validos no toca el portapapeles", FileDrop.deliver([URL(string: "https://x.com")!], to: clip) == nil && clip.string(forType: .string) == "@\"/tmp/informe de prueba.txt\"")

        print(failures == 0 ? "ARCHIVOS OK" : "ARCHIVOS FALLOS: \(failures)")
        return failures == 0
    }
}
