import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var webScout: NativeWebScoutController
    @ObservedObject private var music: MusicController

    init(store: PetStore) {
        self.store = store
        _webScout = ObservedObject(wrappedValue: store.webScout)
        _music = ObservedObject(wrappedValue: store.music)
    }

    var body: some View {
        statusSection
        Section {
            Button("abrir tablero", systemImage: "rectangle.3.group") { AppController.shared.showMissionDashboard() }
            Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                AppController.shared.toggleWindow()
            }
            Button(store.alertsAreSnoozed ? "reactivar avisos" : "silenciar avisos 15 min", systemImage: store.alertsAreSnoozed ? "bell" : "bell.slash") {
                store.alertsAreSnoozed ? store.wakeAlerts() : store.snoozeAlerts()
            }
            pomodoroItem
            if store.musicPlayer, let n = music.nowPlaying {
                Menu(n.title, systemImage: "music.note") {
                    Text(n.artist.isEmpty ? n.app.title : "\(n.artist) · \(n.app.title)")
                    Button(n.isPlaying ? "pausar" : "reproducir", systemImage: n.isPlaying ? "pause.fill" : "play.fill") { music.send(.playPause) }
                    Button("siguiente", systemImage: "forward.fill") { music.send(.next) }
                    Button("anterior", systemImage: "backward.fill") { music.send(.previous) }
                }
            }
        }
        Section {
            Menu("proyecto", systemImage: "folder") { projectMenu }
            Menu("mascotas", systemImage: "pawprint") { petsMenu }
            Menu("web scout", systemImage: "scope") { webScoutMenu }
            Menu("más", systemImage: "ellipsis.circle") { moreMenu }
        }
        Section {
            Button("ajustes…", systemImage: "gearshape") { AppController.shared.showSettings() }
                .keyboardShortcut(",")
            Button("salir", systemImage: "power") { NSApp.terminate(nil) }
        }
    }

    /// Lo que pasa ahora, en tres lineas como maximo; los avisos solo aparecen cuando hay algo que avisar.
    @ViewBuilder private var statusSection: some View {
        Section("en vivo") {
            Label(store.state == .idle ? "claude: en reposo" : "claude: \(store.state.label.lowercased()) · \(store.sessionSummary)", systemImage: stateSymbol)
            Label("codex: \(store.codexPresent ? store.codexState.label.lowercased() : "en reposo")", systemImage: "sparkles")
            if store.contextReading != nil { Label("\(store.contextLabel) · \(store.contextPressureLabel)", systemImage: "circle.dotted") }
            if let warning = store.safetyAlert { Label(warning.title, systemImage: "exclamationmark.triangle.fill") }
            if store.pendingAttentionCount > 0 { Label(store.attentionLabel, systemImage: "hand.raised.fill") }
            if !store.bridgeOK || !store.busOK { Label("puente local no disponible", systemImage: "link.badge.plus") }
            if store.reviewReady { Button("abrir diff listo para revisión", systemImage: "arrow.left.arrow.right") { store.openReview() } }
        }
    }

    @ViewBuilder private var pomodoroItem: some View {
        if store.pomodoro.phase == .idle {
            Button("empezar pomodoro (25 min)", systemImage: "timer") { store.pomodoro.start(now: ProcessInfo.processInfo.systemUptime) }
        } else {
            Button("parar pomodoro", systemImage: "stop.fill") { store.pomodoro.stop() }
        }
    }

    @ViewBuilder private var projectMenu: some View {
        if store.terminalTargetAvailable { Button("saltar a la terminal de claude", systemImage: "macwindow") { store.focusTerminal() } }
        if !store.mission.changes.isEmpty { Button("abrir cambios del proyecto", systemImage: "doc.text.magnifyingglass") { store.openLatestDiff() } }
        Button("commitear este proyecto…", systemImage: "arrow.triangle.branch") {
            if !CommiteroLauncher.launch(workspace: store.mission.workspace) { NSSound.beep() }
        }
        .disabled(!CommiteroLauncher.available() || store.mission.workspace.isEmpty)
        Divider()
        Button("copiar resumen local", systemImage: "doc.on.clipboard") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.mission.shareSummary, forType: .string)
        }
        if store.contextReading != nil {
            Button("copiar estado de contexto", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(store.contextLabel) · presión \(store.contextPressureLabel) · modelo \(store.contextModelLabel)", forType: .string)
            }
        }
        Button("actualizar todo", systemImage: "arrow.triangle.2.circlepath") { store.refreshTelemetryNow(); store.mission.refreshGit() }
        Divider()
        Menu("operaciones", systemImage: "scope") { MissionControlMenu(control: store.mission) }
        Menu("traspaso claude y codex", systemImage: "arrow.left.arrow.right") { HandoffMenu(store: store, handoff: store.handoff, control: store.mission) }
    }

    @ViewBuilder private var petsMenu: some View {
        Button("partido ahora", systemImage: "soccerball") { store.trigger("football") }
            .disabled(!store.pairNear || !store.animationsEnabled)
        Menu("acciones de claude") {
            Button("saludo") { store.trigger("greet") }
            Button("celebración") { store.trigger("cheer") }
            Button("preocupación") { store.trigger("concern") }
        }
        Menu("acciones de codex") {
            ForEach(CodexGesture.allCases, id: \.self) { gesture in Button(gesture.title) { store.triggerCodex(gesture) } }
        }
        Menu("control de codex", systemImage: "cpu") { CodexControlMenu(store: store) }
        Divider()
        Button("abrir la isla ahora", systemImage: "rectangle.topthird.inset.filled") { store.layout = .island; store.userHidden = false }
        Button("volver a mascotas flotantes", systemImage: "rectangle.inset.filled") { store.layout = .floating; store.userHidden = false }
    }

    @ViewBuilder private var webScoutMenu: some View {
        Picker("mascota", selection: $webScout.agent) { ForEach(WebScoutAgent.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        Divider()
        Button("marcar selección", systemImage: "highlighter") { webScout.markSelection() }
        Button("auditar controles visibles", systemImage: "viewfinder") { webScout.auditVisibleControls() }
        Button(webScout.isCrawling ? "detener claudwler" : "iniciar claudwler", systemImage: webScout.isCrawling ? "stop.fill" : "point.3.filled.connected.trianglepath.dotted") {
            webScout.isCrawling ? webScout.stopCrawler() : webScout.startCrawler()
        }
        Toggle("verificar enlaces rotos en red", isOn: $webScout.verifyLinks)
        Button("abrir informe visual", systemImage: "chart.bar.doc.horizontal") { webScout.openReport() }.disabled(!webScout.hasReport)
        Button("copiar informe para Claude Code", systemImage: "doc.on.clipboard") { webScout.copyReport() }.disabled(!webScout.hasReport)
        if webScout.canNavigate {
            Divider()
            Button("problema anterior", systemImage: "chevron.left") { webScout.previousFinding() }
            Button("problema siguiente", systemImage: "chevron.right") { webScout.nextFinding() }
        }
        Button("limpiar marcas", systemImage: "xmark") { webScout.clear() }.disabled(!webScout.hasFindings)
        Divider()
        Button("autorizar accesibilidad", systemImage: "lock.open") { webScout.requestAccess() }
        Text(webScout.status)
    }

    @ViewBuilder private var moreMenu: some View {
        Button("abrir registro de decisiones", systemImage: "list.bullet.rectangle") { if let url = AuditLog.ensureFile() { NSWorkspace.shared.open(url) } }
        Button("copiar auditoría en markdown", systemImage: "doc.on.clipboard") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AuditLog.markdown(), forType: .string)
        }
        Divider()
        Button(store.demoMode ? "detener demo" : "ver demo de la isla", systemImage: store.demoMode ? "stop.fill" : "play.fill") {
            store.demoMode ? store.stopDemo() : store.startDemo()
        }
        Menu("herramientas de prueba", systemImage: "wrench.and.screwdriver") { previewMenu }
    }

    private var stateSymbol: String {
        switch store.state {
        case .idle: return "moon"
        case .starting, .thinking: return "brain"
        case .tool: return "hammer"
        case .waiting: return "hand.raised"
        case .done: return "checkmark.circle"
        case .error: return "xmark.octagon"
        }
    }




    @ViewBuilder private var previewMenu: some View {
        Menu("probar Claude") {
            ForEach(PetState.allCases, id: \.self) { state in
                Button(state.label.capitalized) { store.preview(state) }
            }
        }
        Menu("probar Codex") {
            ForEach(PetState.allCases, id: \.self) { state in
                Button(state.label.capitalized) { store.previewCodex(state) }
            }
        }
    }

}
