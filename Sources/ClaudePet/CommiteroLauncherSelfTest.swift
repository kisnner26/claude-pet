import Foundation

/// `ClaudePet --selftest-commitero`: busqueda del comando y validacion de la carpeta que se le pasa.
enum CommiteroLauncherSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failures += 1 } }
        let root = NSTemporaryDirectory() + "claudepet-commitero-\(getpid())"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: root + "/bin1", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: root + "/bin2", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: root + "/home/.local/bin", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }
        func make(_ path: String, executable: Bool) {
            fm.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: executable ? 0o755 : 0o644])
        }
        let home = root + "/home"

        check("sin el comando en ninguna carpeta no hay resultado", CommiteroLauncher.find(path: root + "/bin1", home: home, extra: []) == nil)
        make(root + "/bin1/commitero", executable: false)
        check("un archivo sin permiso de ejecucion se ignora", CommiteroLauncher.find(path: root + "/bin1", home: home, extra: []) == nil)
        make(root + "/bin2/commitero", executable: true)
        check("encuentra el comando en PATH", CommiteroLauncher.find(path: root + "/bin1:" + root + "/bin2", home: home, extra: []) == root + "/bin2/commitero")
        make(root + "/home/.local/bin/commitero", executable: true)
        check("tambien busca en ~/.local/bin aunque no este en PATH", CommiteroLauncher.find(path: "/usr/bin", home: home, extra: [home + "/.local/bin"]) == root + "/home/.local/bin/commitero")
        check("el orden respeta PATH primero", CommiteroLauncher.find(path: root + "/bin2", home: home, extra: [home + "/.local/bin"]) == root + "/bin2/commitero")
        make(root + "/propio", executable: true)
        check("un ajuste del usuario tiene prioridad", CommiteroLauncher.find(path: root + "/bin2", home: home, override: root + "/propio", extra: []) == root + "/propio")
        check("un ajuste invalido se ignora y cae a la busqueda", CommiteroLauncher.find(path: root + "/bin2", home: home, override: root + "/no-existe", extra: []) == root + "/bin2/commitero")
        try? fm.createDirectory(atPath: root + "/bin1/commitero-dir/commitero", withIntermediateDirectories: true)
        check("una carpeta llamada commitero no cuenta", CommiteroLauncher.find(path: root + "/bin1/commitero-dir", home: home, extra: []) == nil)
        check("las carpetas de busqueda no se repiten", CommiteroLauncher.searchDirectories(path: "/opt/homebrew/bin:/usr/bin", home: home).filter { $0 == "/opt/homebrew/bin" }.count == 1)
        check("la app de barra de menus busca en homebrew aunque su PATH sea corto", CommiteroLauncher.environmentPath(home: home).contains("/opt/homebrew/bin"))

        check("solo se lanza con carpetas absolutas y existentes", CommiteroLauncher.isLaunchableWorkspace(root) && !CommiteroLauncher.isLaunchableWorkspace("relativa/ruta") && !CommiteroLauncher.isLaunchableWorkspace(root + "/no-existe"))
        check("una ruta que parece una opcion no se acepta", !CommiteroLauncher.isLaunchableWorkspace("--help") && !CommiteroLauncher.isLaunchableWorkspace("-x"))
        check("un archivo no es una carpeta valida", !CommiteroLauncher.isLaunchableWorkspace(root + "/propio"))

        print(failures == 0 ? "COMMITERO OK" : "COMMITERO FALLOS: \(failures)")
        return failures == 0
    }
}
