import Foundation

/// `ClaudePet --selftest-drop`: formato de las referencias de archivos soltados.
enum FileDropSelfTest {
    static func run() -> Bool {
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
        print(failures == 0 ? "ARCHIVOS OK" : "ARCHIVOS FALLOS: \(failures)")
        return failures == 0
    }
}
