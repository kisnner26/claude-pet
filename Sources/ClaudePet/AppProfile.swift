import Foundation

/// Familias de apps para las que el dock cambia de herramientas, como la Touch Bar.
enum AppProfile: String, CaseIterable {
    case editor, terminal, devtools, browser, music, chat, meeting, writing, design, media, game, finder, other

    var title: String {
        switch self {
        case .editor: return "editor de código"
        case .terminal: return "terminal"
        case .devtools: return "herramientas de desarrollo"
        case .browser: return "navegador"
        case .music: return "música"
        case .chat: return "mensajes y correo"
        case .meeting: return "videollamadas"
        case .writing: return "notas y documentos"
        case .design: return "diseño"
        case .media: return "vídeo y fotos"
        case .game: return "juegos"
        case .finder: return "Finder"
        case .other: return "otras apps"
        }
    }

    var examples: String {
        switch self {
        case .editor: return "Xcode, VS Code, Cursor, JetBrains, Zed, Sublime, Nova, Android Studio"
        case .terminal: return "Terminal, iTerm, Ghostty, Warp, kitty, Alacritty, WezTerm, Tabby"
        case .devtools: return "GitHub Desktop, Tower, Fork, Sourcetree, Docker, Postman, Insomnia, TablePlus, Proxyman"
        case .browser: return "Safari, Chrome, Arc, Firefox, Edge, Brave, Vivaldi, Zen"
        case .music: return "Spotify, Apple Music, Tidal, Podcasts"
        case .chat: return "Slack, Discord, Mensajes, Telegram, WhatsApp, Signal, Mail, Outlook, Linear"
        case .meeting: return "Zoom, Teams, FaceTime, Meet, Webex, Around"
        case .writing: return "Notas, Notion, Obsidian, Word, Pages, Excel, Keynote, Bear, Things"
        case .design: return "Figma, Sketch, Photoshop, Illustrator, Affinity, Pixelmator, Blender"
        case .media: return "Final Cut, DaVinci, Premiere, QuickTime, IINA, VLC, Fotos, OBS"
        case .game: return "Steam, Epic Games, juegos de la App Store"
        case .finder: return "Finder"
        case .other: return "cualquier otra: tus acciones de siempre"
        }
    }

    private static let exact: [String: AppProfile] = {
        var m: [String: AppProfile] = [:]
        func add(_ p: AppProfile, _ ids: [String]) { for id in ids { m[id] = p } }
        add(.editor, ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview",
                      "com.sublimetext.4", "com.sublimetext.3", "com.panic.Nova", "com.github.atom", "org.vim.MacVim", "com.google.android.studio", "com.vscodium", "com.apple.TextEdit",
                      "com.barebones.bbedit", "com.macromates.TextMate", "org.gnu.Emacs", "com.positron.app", "ai.warp.editor", "dev.kiro.desktop", "com.trae.app", "com.jetbrains.fleet"])
        add(.terminal, ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
                        "org.tabby", "com.raphaelamorim.rio", "com.cmux.app", "app.cmux"])
        add(.devtools, ["com.github.GitHubClient", "com.fournova.Tower3", "com.fournova.Tower2", "com.gitup.GitUp", "com.sourcetreeapp.Sourcetree", "com.atlassian.sourcetree", "com.docker.docker",
                        "com.postmanlabs.mac", "com.insomnia.app", "com.tinyapp.TablePlus", "com.sequel-ace.sequel-ace", "com.proxyman.NSProxy", "com.charlesproxy.charles", "com.apple.dt.Instruments",
                        "com.apple.Console", "com.apple.ActivityMonitor", "com.apple.simulator", "com.apple.CoreSimulator.SimulatorTrampoline", "com.github.GitHubDesktop", "com.electron.github-desktop",
                        "com.orbstack.OrbStack", "com.mongodb.compass", "com.getpaw.Paw", "dev.kaleidoscope.app", "com.kaleidoscope.Kaleidoscope", "com.devtoys.app"])
        add(.browser, ["com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
                       "com.operasoftware.Opera", "app.zen-browser.zen", "org.chromium.Chromium", "com.duckduckgo.macos.browser", "ai.perplexity.comet", "com.kagi.kagimacOS", "com.sigmaos.sigmaos.macos", "org.torproject.torbrowser"])
        add(.music, ["com.spotify.client", "com.apple.Music", "com.tidal.desktop", "com.apple.podcasts", "com.apple.iTunes", "com.amazon.music", "org.videolan.vlc.audio", "com.audirvana.Audirvana-Plus", "com.apple.Logic10", "com.apple.garageband10"])
        add(.chat, ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "org.whispersystems.signal-desktop", "com.apple.mail",
                    "com.readdle.smartemail-Mac", "com.microsoft.Outlook", "com.google.Gmail", "com.linear", "com.superhuman.electron", "com.mimestream.Mimestream", "com.facebook.archon", "com.apple.iChat", "im.riot.app", "chat.element.desktop"])
        add(.meeting, ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.around.app", "com.loom.desktop", "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
                       "com.skype.skype", "com.bluejeans.BlueJeans", "com.gotomeeting.GoToMeeting", "so.cal.meet", "com.pop.pop", "com.tuple.app"])
        add(.writing, ["com.apple.Notes", "notion.id", "md.obsidian", "com.apple.reminders", "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.apple.iWork.Pages", "com.apple.iWork.Numbers",
                       "com.apple.iWork.Keynote", "net.shinyfrog.bear", "com.culturedcode.ThingsMac", "com.apple.iBooksX", "com.apple.Preview", "com.readdle.PDFExpert-Mac", "com.agiletortoise.Drafts-OSX",
                       "com.todoist.mac.Todoist", "com.microsoft.onenote.mac", "abnerworks.Typora", "com.ulyssesapp.mac", "com.reflect.ReflectDesktop", "com.apple.freeform", "com.apple.TextEdit.rich", "org.zotero.zotero", "com.goodnotes.GoodNotes"])
        add(.design, ["com.figma.Desktop", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x", "com.seriflabs.affinitydesigner2", "com.seriflabs.affinityphoto2", "com.seriflabs.affinitypublisher2",
                      "org.blenderfoundation.blender", "com.canva.CanvaDesktop", "com.framer.app", "com.principle.app", "io.penpot.desktop", "com.apple.Image_Capture", "com.apple.Digital-Color-Meter"])
        add(.media, ["com.apple.FinalCut", "com.blackmagic-design.DaVinciResolve", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "com.apple.Photos", "com.apple.TV", "com.obsproject.obs-studio",
                     "com.apple.iMovieApp", "com.apple.Motion", "com.apple.Compressor", "com.apple.PhotoBooth", "com.lightroom.app", "com.apple.Music.video", "io.mpv", "com.hnc.Discord.screen"])
        add(.game, ["com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher", "com.riotgames.RiotGames.RiotClient", "com.blizzard.battle.net", "com.mojang.minecraft.launcher", "com.GOGGalaxy", "com.apple.GameCenter", "com.apple.Chess"])
        m["com.apple.finder"] = .finder
        return m
    }()

    /// Familias por prefijo del identificador (`com.jetbrains.*`, `com.adobe.*`).
    private static let prefixes: [(String, AppProfile)] = [
        ("com.jetbrains.", .editor), ("com.adobe.", .design), ("com.blackmagic-design.", .media), ("com.seriflabs.", .design), ("com.valvesoftware.", .game),
        ("com.atlassian.", .devtools), ("com.microsoft.", .writing), ("com.google.android.", .editor), ("com.apple.dt.", .devtools),
    ]

    /// Por categoria declarada por la propia app (`LSApplicationCategoryType`): sirve para las apps que no conocemos por nombre.
    static func profile(category: String?) -> AppProfile {
        switch category ?? "" {
        case "public.app-category.developer-tools": return .devtools
        case "public.app-category.social-networking": return .chat
        case "public.app-category.productivity", "public.app-category.education", "public.app-category.reference", "public.app-category.business", "public.app-category.finance": return .writing
        case "public.app-category.graphics-design", "public.app-category.photography": return .design
        case "public.app-category.video", "public.app-category.entertainment": return .media
        case "public.app-category.music": return .music
        case let c where c.hasPrefix("public.app-category.") && c.contains("games"): return .game
        default: return .other
        }
    }

    /// Por identificador de paquete: exacto o por familia. Si no se reconoce, por la categoria de la app. nil o desconocido = `.other`.
    static func classify(bundleID: String?, category: String? = nil) -> AppProfile {
        guard let id = bundleID, !id.isEmpty else { return .other }
        if let p = exact[id] { return p }
        if let hit = prefixes.first(where: { id.hasPrefix($0.0) }) { return hit.1 }
        return profile(category: category)
    }

    /// Lo que mas hace falta en cada app, en orden. El dock lo muestra primero y rellena con tus acciones.
    var priority: [QuickAction] {
        switch self {
        case .editor: return [.openInEditor, .changes, .commit, .terminal, .copyBranch]
        case .terminal: return [.terminal, .copyCd, .commit, .changes, .copyBranch]
        case .devtools: return [.commit, .openRepoWeb, .copyBranch, .terminal, .changes]
        case .browser: return [.openRepoWeb, .summary, .music, .snooze, .mission]
        case .music: return [.musicPrev, .music, .musicNext, .snooze, .mission]
        case .chat: return [.summary, .openRepoWeb, .snooze, .changes, .pomodoro]
        case .meeting: return [.snooze, .focus, .summary, .mission, .pomodoro]
        case .writing: return [.summary, .pomodoro, .focus, .snooze, .folder]
        case .design: return [.music, .pomodoro, .snooze, .summary, .mission]
        case .media: return [.snooze, .music, .pomodoro, .focus, .summary]
        case .game: return [.snooze, .music, .focus, .mission, .settings]
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
