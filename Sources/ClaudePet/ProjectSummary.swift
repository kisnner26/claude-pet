import Foundation

/// Borrador de `CLAUDE.md` generado de forma local y extractiva (sin modelo): mira la carpeta, no inventa nada.
/// Cabe en unos 1500 tokens y nunca toca un `CLAUDE.md` existente.
enum ProjectSummary {
    static let tokenBudget = 1_500
    static let draftName = "CLAUDE.md.borrador"

    private static let noise: Set<String> = ["node_modules", ".git", ".build", "build", "dist", "target", "Pods", "venv", ".venv", "__pycache__",
                                             "DerivedData", ".next", ".swiftpm", "vendor", ".gradle", ".idea", ".vscode", "coverage", ".claude", ".DS_Store"]
    private static let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++", "py": "Python", "js": "JavaScript", "jsx": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript",
        "rs": "Rust", "go": "Go", "java": "Java", "kt": "Kotlin", "rb": "Ruby", "php": "PHP", "c": "C", "h": "C/C++", "cpp": "C++", "cs": "C#",
        "sh": "Shell", "html": "HTML", "css": "CSS", "dart": "Dart", "lua": "Lua", "ex": "Elixir", "scala": "Scala", "zig": "Zig"]

    struct Scan {
        var languageFiles: [String: Int] = [:]
        var topDirs: [String: Int] = [:]
        var topFiles: [String] = []
        var scanned = 0
    }

    static func generate(folder: URL, maxFiles: Int = 4_000) -> String {
        let fm = FileManager.default
        let name = folder.standardizedFileURL.lastPathComponent
        var scan = Scan()
        scanTree(folder, fm: fm, into: &scan, maxFiles: maxFiles)

        var sections: [(priority: Int, text: String)] = []
        let head = "# \(name)\n\n> borrador generado de forma local a partir de los archivos del proyecto, sin modelo. Revísalo, corrige lo que falte y renómbralo a CLAUDE.md.\n"

        let langs = scan.languageFiles.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4)
        if !langs.isEmpty {
            sections.append((1, "## lenguajes\n" + langs.map { "- \($0.key) (\($0.value) archivos)" }.joined(separator: "\n") + "\n"))
        }
        let commands = detectCommands(folder, fm: fm)
        if !commands.isEmpty { sections.append((0, "## comandos\n" + commands.map { "- `\($0.0)`\($0.1.isEmpty ? "" : " — \($0.1)")" }.joined(separator: "\n") + "\n")) }

        let dirs = scan.topDirs.sorted { $0.key < $1.key }.prefix(14)
        if !dirs.isEmpty {
            sections.append((2, "## estructura\n" + dirs.map { "- `\($0.key)/` (\($0.value) archivos)" }.joined(separator: "\n") + "\n"))
        }
        let conventions = detectConventions(folder, fm: fm, files: scan.topFiles)
        if !conventions.isEmpty { sections.append((3, "## convenciones visibles\n" + conventions.map { "- \($0)" }.joined(separator: "\n") + "\n")) }
        let docs = documentation(folder, fm: fm, files: scan.topFiles)
        if !docs.isEmpty { sections.append((4, "## documentación existente\n" + docs.map { "- `\($0)`" }.joined(separator: "\n") + "\n")) }
        let todo = "## a completar a mano\n- qué hace el proyecto en una frase\n- decisiones de arquitectura que no se ven en los archivos\n- cosas que nunca hay que hacer\n"
        sections.append((5, todo))

        // se respeta el orden de lectura (comandos primero) y, si no cabe, caen las secciones menos utiles
        var chosen = sections
        func render() -> String { head + "\n" + chosen.sorted { $0.priority < $1.priority }.map(\.text).joined(separator: "\n") }
        while TokenEstimate.tokens(render()) > tokenBudget, let drop = chosen.filter({ $0.priority >= 2 && $0.priority < 5 }).max(by: { $0.priority < $1.priority }) {
            chosen.removeAll { $0.priority == drop.priority }
        }
        var text = render()
        if TokenEstimate.tokens(text) > tokenBudget {
            let limit = Int(Double(tokenBudget) * 3.5)
            text = String(text.prefix(limit))
            if let cut = text.lastIndex(of: "\n") { text = String(text[...cut]) }
        }
        return text
    }

    /// Escribe el borrador junto al proyecto sin pisar nada: `CLAUDE.md.borrador`, o `CLAUDE.md.borrador.2`, etc.
    @discardableResult
    static func writeDraft(_ text: String, in folder: URL) throws -> URL {
        let fm = FileManager.default
        var target = folder.appendingPathComponent(draftName)
        var n = 2
        while fm.fileExists(atPath: target.path) { target = folder.appendingPathComponent("\(draftName).\(n)"); n += 1 }
        try Data(text.utf8).write(to: target, options: [.withoutOverwriting])
        return target
    }

    // MARK: recorrido

    private static func scanTree(_ root: URL, fm: FileManager, into scan: inout Scan, maxFiles: Int) {
        let rootPath = root.standardizedFileURL.path
        guard let top = try? fm.contentsOfDirectory(atPath: rootPath) else { return }
        for entry in top.sorted() where !noise.contains(entry) && !entry.hasPrefix(".") {
            var isDir: ObjCBool = false
            let path = rootPath + "/" + entry
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                var count = 0
                walk(path, fm: fm, depth: 0, scan: &scan, count: &count, maxFiles: maxFiles)
                if count > 0 { scan.topDirs[entry] = count }
            } else {
                scan.topFiles.append(entry)
                countLanguage(entry, &scan)
            }
        }
    }

    private static func walk(_ path: String, fm: FileManager, depth: Int, scan: inout Scan, count: inout Int, maxFiles: Int) {
        guard depth < 6, scan.scanned < maxFiles, let items = try? fm.contentsOfDirectory(atPath: path) else { return }
        for item in items.sorted() where !noise.contains(item) && !item.hasPrefix(".") {
            if scan.scanned >= maxFiles { return }
            var isDir: ObjCBool = false
            let full = path + "/" + item
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue { walk(full, fm: fm, depth: depth + 1, scan: &scan, count: &count, maxFiles: maxFiles) }
            else { count += 1; scan.scanned += 1; countLanguage(item, &scan) }
        }
    }

    private static func countLanguage(_ file: String, _ scan: inout Scan) {
        let ext = (file as NSString).pathExtension.lowercased()
        if let lang = languages[ext] { scan.languageFiles[lang, default: 0] += 1 }
    }

    // MARK: comandos

    private static func read(_ url: URL, limit: Int = 256 * 1024) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url), let d = try? h.read(upToCount: limit) else { return nil }
        try? h.close()
        return String(decoding: d, as: UTF8.self)
    }

    static func detectCommands(_ folder: URL, fm: FileManager) -> [(String, String)] {
        var out: [(String, String)] = []
        func has(_ n: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(n).path) }

        if let pkg = read(folder.appendingPathComponent("Package.swift")) {
            out.append(("swift build", "compila"))
            if pkg.contains(".testTarget") || has("Tests") { out.append(("swift test", "pruebas")) }
            for exe in matches(#"\.executableTarget\(\s*name:\s*"([^"]+)""#, in: pkg).prefix(2) { out.append(("swift run \(exe)", "ejecuta")) }
        }
        if let json = read(folder.appendingPathComponent("package.json")), let data = json.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let scripts = obj["scripts"] as? [String: Any] {
            let runner = has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn" : "npm"
            for key in ["dev", "start", "build", "test", "lint", "typecheck", "format"] where scripts[key] is String {
                out.append(("\(runner) \(key == "test" || key == "start" ? "" : "run ")\(key)".replacingOccurrences(of: "  ", with: " "), ""))
            }
        }
        if let make = read(folder.appendingPathComponent("Makefile")) ?? read(folder.appendingPathComponent("makefile")) {
            let targets = matches(#"(?m)^([A-Za-z][A-Za-z0-9_-]*)\s*:(?!=)"#, in: make)
            var seen = Set<String>()
            for t in targets where seen.insert(t).inserted && out.count < 14 { out.append(("make \(t)", "")); if seen.count >= 6 { break } }
        }
        if has("Cargo.toml") { out.append(("cargo build", "compila")); out.append(("cargo test", "pruebas")) }
        if has("go.mod") { out.append(("go build ./...", "compila")); out.append(("go test ./...", "pruebas")) }
        if has("pyproject.toml") || has("requirements.txt") || has("setup.py") {
            if has("tests") || has("test") { out.append(("pytest", "pruebas")) }
        }
        if let items = try? fm.contentsOfDirectory(atPath: folder.appendingPathComponent("tests").path) {
            let scripts = items.sorted().filter { $0.hasSuffix(".sh") }
            for s in scripts.prefix(3) { out.append(("tests/\(s)", "script de pruebas")) }
            if scripts.count > 3 { out.append(("tests/*.sh", "\(scripts.count - 3) scripts más")) }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.0).inserted }
    }

    // MARK: convenciones

    static func detectConventions(_ folder: URL, fm: FileManager, files: [String]) -> [String] {
        var out: [String] = []
        let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        let known: [(String, String)] = [(".swiftlint.yml", "SwiftLint"), (".swiftformat", "SwiftFormat"), (".editorconfig", "EditorConfig"),
                                         (".prettierrc", "Prettier"), ("ruff.toml", "Ruff"), ("rustfmt.toml", "rustfmt"), (".clang-format", "clang-format")]
        for (file, label) in known where names.contains(file) { out.append("formato/lint: \(label) (`\(file)`)") }
        if names.contains(where: { $0.hasPrefix(".eslintrc") || $0.hasPrefix("eslint.config") }) { out.append("lint: ESLint") }
        if names.contains(where: { $0.hasPrefix("prettier.config") }) { out.append("formato: Prettier") }
        if names.contains("CONTRIBUTING.md") { out.append("hay guía de contribución (`CONTRIBUTING.md`)") }
        if names.contains(".github") { out.append("hay flujos de CI en `.github/`") }
        if let prefixes = commitPrefixes(folder) { out.append("commits con prefijo: \(prefixes)") }
        return out
    }

    /// Prefijos de los ultimos commits, solo si la mayoria los usa. Lee `git log` local; sin git, nada.
    static func commitPrefixes(_ folder: URL) -> String? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", folder.path, "log", "-60", "--format=%s"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let subjects = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard subjects.count >= 5 else { return nil }
        var counts: [String: Int] = [:]
        var prefixed = 0
        for s in subjects {
            guard let colon = s.firstIndex(of: ":"), s.distance(from: s.startIndex, to: colon) <= 20 else { continue }
            var head = String(s[..<colon])
            if let paren = head.firstIndex(of: "(") { head = String(head[..<paren]) }
            guard !head.isEmpty, head.allSatisfy({ $0.isLetter && $0.isLowercase }) else { continue }
            counts[head, default: 0] += 1; prefixed += 1
        }
        guard Double(prefixed) / Double(subjects.count) >= 0.5 else { return nil }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(5).map { "`\($0.key):`" }.joined(separator: ", ")
    }

    static func documentation(_ folder: URL, fm: FileManager, files: [String]) -> [String] {
        var out = files.filter { ["README.md", "ARCHITECTURE.md", "CONTRIBUTING.md", "AGENTS.md", "CHANGELOG.md"].contains($0) }
        if let docs = try? fm.contentsOfDirectory(atPath: folder.appendingPathComponent("docs").path) {
            out += docs.filter { $0.hasSuffix(".md") }.sorted().prefix(8).map { "docs/\($0)" }
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    // MARK: linea de comandos

    /// `ClaudePet --project-summary [carpeta] [--write]`
    static func cli(_ args: [String], cwd: String) -> Int32 {
        var folder = cwd
        var write = false
        for a in args { if a == "--write" { write = true } else if !a.hasPrefix("--") { folder = a } }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            FileHandle.standardError.write(Data("no existe esa carpeta\n".utf8)); return 1
        }
        let url = URL(fileURLWithPath: folder)
        let text = generate(folder: url)
        if write {
            do {
                let out = try writeDraft(text, in: url)
                print("borrador escrito en \(out.lastPathComponent) (≈\(TokenEstimate.tokens(text)) tokens). CLAUDE.md no se ha tocado.")
            } catch { FileHandle.standardError.write(Data("no se pudo escribir el borrador\n".utf8)); return 1 }
        } else {
            print(text, terminator: "")
        }
        return 0
    }
}
