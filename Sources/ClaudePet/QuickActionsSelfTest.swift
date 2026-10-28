import Foundation

enum QuickActionsSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { if !ok { failures += 1; print("FALLO \(name)") } }

        var c = QuickContext()
        check("sin nada: solo lo que siempre vale", QuickAction.allCases.filter { QuickActions.available($0, c) }.sorted { $0.rawValue < $1.rawValue } == [.focus, .mission, .pomodoro, .relay, .settings, .snooze, .summary].sorted { $0.rawValue < $1.rawValue })
        c.hasWorkspace = true; c.isRepo = true
        check("con repo: carpeta, punto de restauracion y perimetro", [.folder, .restorePoint, .perimeter].allSatisfy { QuickActions.available($0, c) } && !QuickActions.available(.commit, c))
        c.changeCount = 3; c.agentChanges = 2
        check("commitear exige commitero, repo, proyecto y cambios", !QuickActions.available(.commit, c) && { var d = c; d.commiteroAvailable = true; return QuickActions.available(.commit, d) }() && { var d = c; d.commiteroAvailable = true; d.isRepo = false; return !QuickActions.available(.commit, d) }() && { var d = c; d.commiteroAvailable = true; d.changeCount = 0; return !QuickActions.available(.commit, d) }())
        check("cambios y terminal dependen de su contexto", QuickActions.available(.changes, c) && !QuickActions.available(.terminal, c) && { var d = c; d.terminalAvailable = true; return QuickActions.available(.terminal, d) }())
        check("musica solo si hay algo que controlar", !QuickActions.available(.music, c) && { var d = c; d.musicAvailable = true; return QuickActions.available(.music, d) }())
        check("punto de restauracion no sin repo", { var d = QuickContext(); d.hasWorkspace = true; return !QuickActions.available(.restorePoint, d) }())

        // descriptores que cambian con el estado
        check("musica: icono segun suene o no", QuickActions.descriptor(.music, QuickContext(musicPlaying: true)).symbol == "pause.fill" && QuickActions.descriptor(.music, QuickContext()).symbol == "play.fill")
        check("pomodoro y avisos: cambian de icono", QuickActions.descriptor(.pomodoro, QuickContext(pomodoroRunning: true)).symbol == "stop.fill" && QuickActions.descriptor(.snooze, QuickContext(alertsSnoozed: true)).title == "reactivar avisos" && QuickActions.descriptor(.perimeter, QuickContext(hasPerimeter: false)).title == "fijar perímetro")
        check("insignia de cambios y commit destacado", QuickActions.descriptor(.changes, QuickContext(agentChanges: 7)).badge == 7 && QuickActions.descriptor(.commit, QuickContext(changeCount: 2)).prominent)
        check("todas las acciones tienen titulo, icono y cuando", QuickAction.allCases.allSatisfy { let d = QuickActions.descriptor($0, QuickContext()); return !d.title.isEmpty && !d.symbol.isEmpty && !d.when.isEmpty })

        // layout
        var full = QuickContext(hasWorkspace: true, isRepo: true, changeCount: 4, agentChanges: 3, commiteroAvailable: true, terminalAvailable: true, musicAvailable: true)
        let order = QuickActions.allOrdered
        let l = QuickActions.layout(order: order, context: full)
        check("tope de cinco visibles, el resto al menu +", l.visible.count == QuickActions.maxVisible && l.visible == [.commit, .terminal, .changes, .music, .mission] && l.overflow.first == .summary && l.overflow.count == QuickActions.allOrdered.filter { QuickActions.available($0, full) }.count - 5)
        check("respeta el orden del usuario", QuickActions.layout(order: [.mission, .commit], context: full).visible == [.mission, .commit])
        full.changeCount = 0; full.agentChanges = 0; full.musicAvailable = false
        check("lo no disponible desaparece y no deja huecos", QuickActions.layout(order: QuickActions.defaultEnabled, context: full).visible == [.terminal, .mission])
        check("sin acciones activadas, dock vacio", QuickActions.layout(order: [], context: full) == (visible: [], overflow: []))
        check("nunca se repite una accion", Set(l.visible + l.overflow).count == (l.visible + l.overflow).count)

        // persistencia
        check("decode: nil usa los de fabrica", QuickActions.decode(nil) == QuickActions.defaultEnabled)
        check("decode: ordena y valida", QuickActions.decode("mission,commit,commit,raro,terminal") == [.mission, .commit, .terminal])
        check("decode: texto sin nada valido vuelve a fabrica, pero vacio significa ninguno", QuickActions.decode("raro,otro") == QuickActions.defaultEnabled && QuickActions.decode("").isEmpty)
        check("encode y decode son inversos", QuickActions.decode(QuickActions.encode(QuickActions.allOrdered)) == QuickActions.allOrdered)
        check("allOrdered contiene todas una vez", QuickActions.allOrdered.count == QuickAction.allCases.count && Set(QuickActions.allOrdered).count == QuickAction.allCases.count)

        // perfiles por app
        check("clasifica editores, terminales y navegadores", AppProfile.classify(bundleID: "com.apple.dt.Xcode") == .editor && AppProfile.classify(bundleID: "com.microsoft.VSCode") == .editor && AppProfile.classify(bundleID: "com.jetbrains.intellij") == .editor
              && AppProfile.classify(bundleID: "com.googlecode.iterm2") == .terminal && AppProfile.classify(bundleID: "com.apple.Terminal") == .terminal && AppProfile.classify(bundleID: "com.apple.Safari") == .browser && AppProfile.classify(bundleID: "company.thebrowser.Browser") == .browser)
        check("clasifica musica, mensajes, notas, diseno y Finder", AppProfile.classify(bundleID: "com.spotify.client") == .music && AppProfile.classify(bundleID: "com.tinyspeck.slackmacgap") == .chat && AppProfile.classify(bundleID: "com.apple.mail") == .chat
              && AppProfile.classify(bundleID: "md.obsidian") == .writing && AppProfile.classify(bundleID: "com.figma.Desktop") == .design && AppProfile.classify(bundleID: "com.adobe.Photoshop") == .design && AppProfile.classify(bundleID: "com.apple.finder") == .finder)
        let cases: [(String, AppProfile)] = [("com.github.GitHubClient", .devtools), ("com.docker.docker", .devtools), ("com.postmanlabs.mac", .devtools), ("us.zoom.xos", .meeting), ("com.microsoft.teams2", .meeting),
                                             ("com.apple.FinalCut", .media), ("com.colliderli.iina", .media), ("com.valvesoftware.steam", .game), ("com.microsoft.Excel", .writing), ("org.blenderfoundation.blender", .design),
                                             ("org.whispersystems.signal-desktop", .chat), ("com.tidal.desktop", .music), ("org.tabby", .terminal), ("com.apple.TextEdit", .editor), ("com.brave.Browser", .browser)]
        for (id, p) in cases { check("clasifica \(id)", AppProfile.classify(bundleID: id) == p) }
        check("una app desconocida se clasifica por su categoria", AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.developer-tools") == .devtools
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.productivity") == .writing
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.social-networking") == .chat
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.graphics-design") == .design
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.video") == .media
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.games") == .game
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.action-games") == .game
              && AppProfile.classify(bundleID: "com.empresa.rara", category: "public.app-category.utilities") == .other)
        check("lo conocido gana a la categoria", AppProfile.classify(bundleID: "com.apple.Safari", category: "public.app-category.games") == .browser)
        check("cada familia tiene ejemplos, titulo y acciones que existen", AppProfile.allCases.allSatisfy { !$0.title.isEmpty && !$0.examples.isEmpty && ($0 == .other || !$0.priority.isEmpty) })
        var ctx = QuickContext(hasWorkspace: true, isRepo: true, profile: .meeting); ctx.branch = "main"
        check("en una videollamada lo primero es silenciar los avisos", QuickActions.layout(order: QuickActions.defaultEnabled, context: ctx).visible.first == .snooze)
        check("copiar rama solo con rama conocida", QuickActions.available(.copyBranch, ctx) && !QuickActions.available(.copyBranch, QuickContext(hasWorkspace: true, isRepo: true)))
        check("el modo foco siempre esta disponible", QuickActions.available(.focus, QuickContext()))
        check("lo desconocido o vacio es 'otras apps'", AppProfile.classify(bundleID: nil) == .other && AppProfile.classify(bundleID: "") == .other && AppProfile.classify(bundleID: "com.empresa.rara") == .other && AppProfile.classify(bundleID: "com.jetbrainsfake.x") == .other)
        check("cada perfil tiene titulo, ejemplos y, salvo 'otras', cinco prioridades distintas", AppProfile.allCases.allSatisfy { !$0.title.isEmpty && !$0.examples.isEmpty } && AppProfile.allCases.filter { $0 != .other }.allSatisfy { Set($0.priority).count == $0.priority.count && $0.priority.count == 5 } && AppProfile.other.priority.isEmpty)

        let repo = QuickContext(hasWorkspace: true, isRepo: true, changeCount: 2, agentChanges: 2, commiteroAvailable: true, terminalAvailable: true, musicAvailable: true, profile: .editor, frontAppName: "Xcode", hasRemote: true)
        check("en un editor manda 'abrir en <editor>'", QuickActions.layout(order: QuickActions.defaultEnabled, context: repo).visible.first == .openInEditor && QuickActions.descriptor(.openInEditor, repo).title == "abrir en Xcode")
        var term = repo; term.profile = .terminal; term.frontAppName = "Terminal"
        check("en una terminal manda la terminal y el cd", Array(QuickActions.layout(order: QuickActions.defaultEnabled, context: term).visible.prefix(2)) == [.terminal, .copyCd])
        var br = repo; br.profile = .browser
        check("en el navegador sale el repo web, solo con remoto", QuickActions.layout(order: [], context: br).visible.first == .openRepoWeb && !QuickActions.layout(order: [], context: { var d = br; d.hasRemote = false; return d }()).visible.contains(.openRepoWeb))
        var mus = repo; mus.profile = .music
        check("en la musica: anterior, pausa y siguiente", Array(QuickActions.layout(order: QuickActions.defaultEnabled, context: mus).visible.prefix(3)) == [.musicPrev, .music, .musicNext])
        var fin = repo; fin.profile = .finder
        check("en Finder: carpeta y ruta", Array(QuickActions.layout(order: [], context: fin).visible.prefix(2)) == [.folder, .copyPath])
        check("abrir en el editor exige estar en uno y conocer su nombre", !QuickActions.available(.openInEditor, { var d = repo; d.profile = .browser; return d }()) && !QuickActions.available(.openInEditor, { var d = repo; d.frontAppName = nil; return d }()) && !QuickActions.available(.openInEditor, { var d = repo; d.hasWorkspace = false; return d }()))
        check("sin 'segun la app' manda el orden del usuario", QuickActions.layout(order: QuickActions.defaultEnabled, context: repo, appAware: false).visible == [.commit, .terminal, .changes, .music, .mission])
        check("el perfil nunca repite ni pasa de cinco", { let l = QuickActions.layout(order: QuickActions.allOrdered, context: repo); return l.visible.count == 5 && Set(l.visible + l.overflow).count == (l.visible + l.overflow).count }())
        check("la musica de perfil desaparece si no suena nada", !QuickActions.layout(order: [], context: { var d = mus; d.musicAvailable = false; return d }()).visible.contains(.musicNext))

        // remoto de git: nunca credenciales, solo hosts conocidos
        check("remoto ssh y https", GitRemote.webURL(from: "git@github.com:kisnner26/claude-pet.git") == "https://github.com/kisnner26/claude-pet" && GitRemote.webURL(from: "https://github.com/kisnner26/claude-pet.git") == "https://github.com/kisnner26/claude-pet"
              && GitRemote.webURL(from: "ssh://git@gitlab.com/grupo/sub/repo.git") == "https://gitlab.com/grupo/sub/repo" && GitRemote.webURL(from: "https://codeberg.org/a/b") == "https://codeberg.org/a/b")
        check("el remoto pierde usuario y token", GitRemote.webURL(from: "https://usuario:ghp_SECRETO123@github.com/a/b.git") == "https://github.com/a/b" && !(GitRemote.webURL(from: "https://x-access-token:abc@github.com/a/b.git") ?? "").contains("abc"))
        check("remotos raros se rechazan", ["", "no es una url", "https://evil.com/a/b", "https://github.com.evil.com/a/b", "file:///tmp/repo", "git@github.com:solo-uno", "https://github.com/a/../b", "https://github.com/a/b c", "javascript:alert(1)", "git@evil.com:a/b.git", "https://github.com/"].allSatisfy { GitRemote.webURL(from: $0) == nil })

        // comillas de shell
        check("comillas simples", ShellQuote.single("/Users/x/mi proyecto") == "'/Users/x/mi proyecto'" && ShellQuote.single("/tmp/it's") == "'/tmp/it'\\''s'" && ShellQuote.single("/tmp/$(rm -rf ~)") == "'/tmp/$(rm -rf ~)'")
        check("comillas: rechaza saltos de linea y vacio", ShellQuote.single("/tmp/a\nb") == nil && ShellQuote.single("") == nil && ShellQuote.single("/tmp/a\0b") == nil)

        // que abrir en cada editor
        check("Xcode prefiere workspace, luego paquete, luego proyecto", ProjectOpener.target(bundleID: "com.apple.dt.Xcode", workspace: "/p", entries: ["Package.swift", "App.xcodeproj", "App.xcworkspace"]) == "/p/App.xcworkspace"
              && ProjectOpener.target(bundleID: "com.apple.dt.Xcode", workspace: "/p", entries: ["Package.swift", "App.xcodeproj"]) == "/p/Package.swift" && ProjectOpener.target(bundleID: "com.apple.dt.Xcode", workspace: "/p", entries: ["App.xcodeproj"]) == "/p/App.xcodeproj"
              && ProjectOpener.target(bundleID: "com.apple.dt.Xcode", workspace: "/p", entries: ["README.md"]) == "/p")
        check("el resto de editores abren la carpeta", ProjectOpener.target(bundleID: "com.microsoft.VSCode", workspace: "/p", entries: ["App.xcworkspace"]) == "/p" && ProjectOpener.target(bundleID: "com.apple.dt.Xcode", workspace: "/p", entries: [".xcodeproj", ".xcworkspace"]) == "/p")
        check("las descripciones de las acciones nuevas existen", [QuickAction.openInEditor, .openRepoWeb, .copyCd, .copyPath, .musicPrev, .musicNext].allSatisfy { let d = QuickActions.descriptor($0, QuickContext(frontAppName: "X")); return !d.title.isEmpty && !d.symbol.isEmpty && !d.when.isEmpty })

        print(failures == 0 ? "ACCESO OK" : "ACCESO \(failures) FALLOS")
        return failures == 0
    }
}
