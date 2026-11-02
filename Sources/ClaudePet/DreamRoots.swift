import Foundation

/// Para saber si un archivo que cita una nota sigue existiendo hay que saber donde esta el proyecto. El cerebro solo guarda su nombre,
/// asi que se busca: primero en los perimetros que ya configuraste y luego en las carpetas donde suele vivir el codigo.
enum DreamRoots {
    static func candidateParents(home: String) -> [String] {
        ["Documents", "Documents/pc-acceso", "Developer", "dev", "code", "Projects", "src", "Sites", "GitHub", "Desktop"].map { home + "/" + $0 }
    }

    static func root(for project: String, perimeterRoots: [String], home: String = NSHomeDirectory(), isDirectory: (String) -> Bool = { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &d) && d.boolValue }) -> String? {
        let name = BrainStore.clean(project: project)
        guard name != "global" else { return nil }
        for root in perimeterRoots where BrainStore.clean(project: (root as NSString).lastPathComponent) == name && isDirectory(root) { return root }
        for parent in candidateParents(home: home) {
            let path = parent + "/" + name
            if isDirectory(path) { return path }
        }
        return nil
    }
}

/// Los nombres y rutas de un proyecto, para comprobar de golpe todo lo que citan las notas sin recorrer el disco cada vez.
struct ProjectFileIndex {
    var paths = Set<String>()       // rutas relativas
    var names = Set<String>()       // nombres de archivo

    static let skipped: Set<String> = [".git", "node_modules", ".build", "build", "DerivedData", "Pods", ".venv", "venv", "dist", "target", ".next"]

    static func build(root: String, limit: Int = 25_000) -> ProjectFileIndex {
        var index = ProjectFileIndex()
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: root) else { return index }
        var seen = 0
        while let relative = walker.nextObject() as? String {
            let name = (relative as NSString).lastPathComponent
            if skipped.contains(name) || name.hasPrefix(".") { walker.skipDescendants(); continue }
            seen += 1
            if seen > limit { break }
            index.names.insert(name)
            index.paths.insert(relative)
        }
        return index
    }

    /// Una ruta citada sigue existiendo si esta el archivo (por nombre) o la ruta completa, o si es absoluta y existe.
    func exists(_ mentioned: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        if mentioned.hasPrefix("/") { return fileExists(mentioned) }
        if mentioned.hasPrefix("~/") { return fileExists(NSHomeDirectory() + String(mentioned.dropFirst(1))) }
        let clean = mentioned.hasPrefix("./") ? String(mentioned.dropFirst(2)) : mentioned
        if clean.contains("/") {
            let trimmed = clean.hasSuffix("/") ? String(clean.dropLast()) : clean
            return paths.contains(trimmed) || paths.contains { $0.hasSuffix("/" + trimmed) }
        }
        return names.contains(clean)
    }
}
