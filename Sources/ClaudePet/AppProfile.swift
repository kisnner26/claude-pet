import Foundation

/// Familias de apps para las que el dock cambia de herramientas, como la Touch Bar.
enum AppProfile: String, CaseIterable {
    case editor, terminal, browser, music, chat, writing, design, finder, other

    var title: String {
        switch self {
        case .editor: return "editor de código"
        case .terminal: return "terminal"
        case .browser: return "navegador"
        case .music: return "música"
        case .chat: return "mensajes y correo"
        case .writing: return "notas y documentos"
        case .design: return "diseño"
        case .finder: return "Finder"
        case .other: return "otras apps"
        }
    }

    var examples: String {
        switch self {
        case .editor: return "Xcode, VS Code, Cursor, JetBrains, Zed, Sublime, Nova"
        case .terminal: return "Terminal, iTerm, Ghostty, Warp, kitty, Alacritty, WezTerm"
        case .browser: return "Safari, Chrome, Arc, Firefox, Edge, Brave"
        case .music: return "Spotify, Apple Music"
        case .chat: return "Slack, Discord, Mensajes, Telegram, WhatsApp, Mail, Teams, Zoom"
        case .writing: return "Notas, Notion, Obsidian, Word, Pages, Recordatorios"
        case .design: return "Figma, Sketch, Photoshop, Illustrator"
        case .finder: return "Finder"
        case .other: return "cualquier otra: tus acciones de siempre"
        }
    }

    private static let exact: [String: AppProfile] = {
        var m: [String: AppProfile] = [:]
        for id in ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview",
                   "com.sublimetext.4", "com.sublimetext.3", "com.panic.Nova", "com.github.atom", "org.vim.MacVim", "com.google.android.studio", "com.vscodium"] { m[id] = .editor }
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper"] { m[id] = .terminal }
        for id in ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
                   "com.operasoftware.Opera", "app.zen-browser.zen"] { m[id] = .browser }
        for id in ["com.spotify.client", "com.apple.Music"] { m[id] = .music }
        for id in ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "com.microsoft.teams2", "us.zoom.xos", "com.apple.FaceTime",
                   "com.apple.mail", "com.readdle.smartemail-Mac", "com.microsoft.Outlook"] { m[id] = .chat }
        for id in ["com.apple.Notes", "notion.id", "md.obsidian", "com.apple.reminders", "com.microsoft.Word", "com.apple.iWork.Pages", "net.shinyfrog.bear", "com.culturedcode.ThingsMac"] { m[id] = .writing }
        for id in ["com.figma.Desktop", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x"] { m[id] = .design }
        m["com.apple.finder"] = .finder
        return m
    }()

    /// Por identificador de paquete: exacto o por familia (`com.jetbrains.*`, `com.adobe.*`). nil o desconocido = `.other`.
    static func classify(bundleID: String?) -> AppProfile {
        guard let id = bundleID, !id.isEmpty else { return .other }
        if let p = exact[id] { return p }
        if id.hasPrefix("com.jetbrains.") { return .editor }
        if id.hasPrefix("com.adobe.") { return .design }
        return .other
    }

    /// Lo que mas hace falta en cada app, en orden. El dock lo muestra primero y rellena con tus acciones.
    var priority: [QuickAction] {
        switch self {
        case .editor: return [.openInEditor, .changes, .commit, .terminal, .restorePoint]
        case .terminal: return [.terminal, .copyCd, .commit, .changes, .restorePoint]
        case .browser: return [.openRepoWeb, .summary, .music, .snooze, .mission]
        case .music: return [.musicPrev, .music, .musicNext, .snooze, .mission]
        case .chat: return [.summary, .openRepoWeb, .snooze, .changes, .pomodoro]
        case .writing: return [.summary, .pomodoro, .snooze, .music, .folder]
        case .design: return [.music, .pomodoro, .snooze, .summary, .mission]
        case .finder: return [.folder, .copyPath, .restorePoint, .perimeter, .mission]
        case .other: return []
        }
    }
}

/// Direccion web de un remoto de git. Nunca conserva credenciales: un `https://usuario:token@...` pierde el token.
enum GitRemote {
    static let hosts: Set<String> = ["github.com", "gitlab.com", "bitbucket.org", "codeberg.org"]

    static func webURL(from remote: String) -> String? {
        let r = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, r.count < 300, !r.contains(where: { $0.isNewline || $0 == "\0" || $0 == " " }) else { return nil }
        var host = "", path = ""
        if let at = r.firstIndex(of: "@"), let colon = r[at...].firstIndex(of: ":"), !r.contains("://") {      // git@github.com:owner/repo.git
            host = String(r[r.index(after: at)..<colon]); path = String(r[r.index(after: colon)...])
        } else if let comps = URLComponents(string: r), let h = comps.host, ["https", "http", "ssh", "git"].contains(comps.scheme ?? "") {
            host = h; path = comps.path
        } else { return nil }
        host = host.lowercased()
        guard hosts.contains(host) else { return nil }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard path.range(of: "^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+){1,3}$", options: .regularExpression) != nil, !path.contains("..") else { return nil }
        return "https://\(host)/\(path)"
    }
}

enum ShellQuote {
    /// Entre comillas simples, apto para pegar en un shell. nil si la ruta lleva saltos de linea o caracteres nulos.
    static func single(_ s: String) -> String? {
        guard !s.isEmpty, !s.contains(where: { $0.isNewline || $0 == "\0" }) else { return nil }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ProjectOpener {
    /// Que abrir en cada editor: Xcode prefiere el workspace, luego el paquete y luego el proyecto; el resto abre la carpeta.
    static func target(bundleID: String, workspace: String, entries: [String]) -> String {
        guard bundleID == "com.apple.dt.Xcode" else { return workspace }
        let sorted = entries.sorted()
        for pattern in [".xcworkspace", "Package.swift", ".xcodeproj"] {
            if let hit = sorted.first(where: { pattern.hasPrefix(".") ? $0.hasSuffix(pattern) : $0 == pattern }), !hit.hasPrefix(".") { return workspace + "/" + hit }
        }
        return workspace
    }
}
