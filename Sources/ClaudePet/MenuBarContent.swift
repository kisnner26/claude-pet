import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var webScout: NativeWebScoutController

    init(store: PetStore) {
        self.store = store
        _webScout = ObservedObject(wrappedValue: store.webScout)
    }

    var body: some View {
        Section("en vivo") {
            Label("claude: \(store.state.label.lowercased())", systemImage: stateSymbol)
            if store.state != .idle { Label(store.sessionSummary, systemImage: "briefcase") }
            if !store.mission.workspace.isEmpty { Label(store.workspaceLabel, systemImage: "folder") }
            if store.state != .idle { Label("desde hace \(store.stateDurationLabel)", systemImage: "timer") }
            if store.contextReading != nil { Label("\(store.contextLabel) · \(store.contextPressureLabel) · \(store.contextModelLabel)", systemImage: "circle.dotted") }
            if store.contextReading != nil {
                Button("copiar estado de contexto", systemImage: "doc.on.clipboard") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(store.contextLabel) · presión \(store.contextPressureLabel) · modelo \(store.contextModelLabel)", forType: .string)
                }
            }
            if store.codexContextReading != nil { Label("\(store.codexContextLabel) · \(store.codexContextModelLabel)", systemImage: "circle.dotted") }
            if store.codexContextReading != nil {
                Button("copiar estado de contexto de codex", systemImage: "doc.on.clipboard") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(store.codexContextLabel) · modelo \(store.codexContextModelLabel)", forType: .string)
                }
            }
            if store.terminalTargetAvailable {
                Button("saltar a terminal de claude", systemImage: "macwindow") { store.focusTerminal() }
            }
            Label("codex: \(store.codexPresent ? store.codexState.label.lowercased() : "en reposo")", systemImage: "sparkles")
            if store.codexPresent && store.codexState != .idle { Label("codex desde hace \(store.codexStateDurationLabel)", systemImage: "timer") }
            if let warning = store.safetyAlert {
                Label(warning.title, systemImage: "exclamationmark.triangle.fill")
            }
            if !store.bridgeOK {
                Label("puente local no disponible", systemImage: "link.badge.plus")
            }
            if !store.busOK {
                Label("pet bus no disponible", systemImage: "dot.radiowaves.left.and.right")
            }
            if store.reviewReady {
                Button("abrir diff listo para revisión", systemImage: "arrow.left.arrow.right") { store.openReview() }
            }
            if !store.mission.changes.isEmpty {
                Button("abrir cambios del proyecto", systemImage: "doc.text.magnifyingglass") { store.openLatestDiff() }
            }
            if store.pendingAttentionCount > 0 {
                Label(store.attentionLabel, systemImage: "hand.raised.fill")
            }
        }

        Section {
            Button("abrir tablero", systemImage: "rectangle.3.group") { AppController.shared.showMissionDashboard() }
            Button("copiar resumen local", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.mission.shareSummary, forType: .string)
            }
            Button("actualizar contexto ahora", systemImage: "arrow.clockwise") { store.refreshTelemetryNow() }
            Button("actualizar todo", systemImage: "arrow.triangle.2.circlepath") {
                store.refreshTelemetryNow(); store.mission.refreshGit()
            }
            Button("abrir registro de decisiones", systemImage: "list.bullet.rectangle") {
                if let url = AuditLog.ensureFile() { NSWorkspace.shared.open(url) }
            }
            Button("copiar auditoría en markdown", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AuditLog.markdown(), forType: .string)
            }
            Button(store.demoMode ? "detener demo" : "ver demo de la isla", systemImage: store.demoMode ? "stop.fill" : "play.fill") {
                store.demoMode ? store.stopDemo() : store.startDemo()
            }
            Menu("web scout nativo", systemImage: "scope") {
                Picker("mascota", selection: $webScout.agent) {
                    ForEach(WebScoutAgent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Button("marcar selección", systemImage: "highlighter") { webScout.markSelection() }
                Button("auditar controles visibles", systemImage: "viewfinder") { webScout.auditVisibleControls() }
                Button(webScout.isCrawling ? "detener claudwler" : "iniciar claudwler",
                       systemImage: webScout.isCrawling ? "stop.fill" : "point.3.filled.connected.trianglepath.dotted") {
                    webScout.isCrawling ? webScout.stopCrawler() : webScout.startCrawler()
                }
                Toggle("verificar enlaces rotos en red", isOn: $webScout.verifyLinks)
                Button("abrir informe visual", systemImage: "chart.bar.doc.horizontal") { webScout.openReport() }
                    .disabled(!webScout.hasReport)
                Button("copiar informe para Claude Code", systemImage: "doc.on.clipboard") { webScout.copyReport() }
                    .disabled(!webScout.hasReport)
                if webScout.canNavigate {
                    Divider()
                    Button("problema anterior", systemImage: "chevron.left") { webScout.previousFinding() }
                    Button("problema siguiente", systemImage: "chevron.right") { webScout.nextFinding() }
                }
                Button("limpiar marcas", systemImage: "xmark") { webScout.clear() }
                    .disabled(!webScout.hasFindings)
                Divider()
                Button("autorizar accesibilidad", systemImage: "lock.open") { webScout.requestAccess() }
                Text(webScout.status)
            }
            Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                AppController.shared.toggleWindow()
            }
            Button("abrir isla ahora", systemImage: "rectangle.topthird.inset.filled") {
                store.layout = .island; store.userHidden = false
            }
            Button("volver a mascotas flotantes", systemImage: "rectangle.inset.filled") {
                store.layout = .floating; store.userHidden = false
            }
        }

        Section {
            Menu("mascotas", systemImage: "pawprint") {
                Picker("modo", selection: $store.layout) {
                    ForEach(PetLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if store.layout == .island {
                    Toggle("responder permisos desde la isla", isOn: $store.islandPermissions)
                    Toggle("atajos globales de la isla", isOn: $store.globalShortcutsEnabled)
                    Picker("pantalla de la isla", selection: $store.islandScreenPreference) { ForEach(IslandScreenPreference.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if store.islandScreenPreference == .fixed {
                        Picker("elegir pantalla", selection: $store.islandFixedScreenID) {
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                Text(screen.localizedName + (screen.safeAreaInsets.top > 0 ? " (con notch)" : "")).tag(IslandController.screenID(screen))
                            }
                        }
                    }
                    Picker("contenido compacto", selection: $store.islandCompactMode) { ForEach(IslandCompactMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle("reloj en la isla", isOn: $store.islandShowClock)
                    Picker("ubicación", selection: $store.islandPlacement) { ForEach(IslandPlacement.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("zona de activación", selection: $store.islandActivationWidth) { ForEach([120.0, 180, 240, 320, 400], id: \.self) { Text("\(Int($0)) pt").tag($0) } }
                    Picker("plegar al salir el cursor", selection: $store.islandCloseDelay) {
                        Text("rápido").tag(0.6); Text("normal").tag(1.2); Text("lento").tag(2.5); Text("solo a los 60 s").tag(0.0)
                    }
                    Picker("retraso al asomar", selection: $store.islandActivationDelay) { ForEach([0.0, 0.15, 0.3, 0.5, 1.0], id: \.self) { Text($0 == 0 ? "inmediato" : String(format: "%.2f s", $0)).tag($0) } }
                }
                Menu("resumen semanal", systemImage: "chart.bar") {
                    let recap = ActivityStats.shared.recap()
                    Text("nivel \(recap.level) · racha \(recap.streak) · \(recap.sessions) sesiones")
                    Button("copiar resumen") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(recap.markdown(showProject: true), forType: .string) }
                    Button("guardar imagen para compartir…") {
                        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "mi-semana.png"
                        if panel.runModal() == .OK, let url = panel.url, let data = RecapCard.png(recap, showProject: false) { try? data.write(to: url) }
                    }
                    Button("borrar estadísticas") { ActivityStats.shared.reset() }
                }
                Menu("foco y pomodoro", systemImage: "moon") {
                    Toggle("modo foco", isOn: $store.focusManual)
                    Picker("foco desde las", selection: $store.focusStart) { Text("sin horario").tag(-1); ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Picker("foco hasta las", selection: $store.focusEnd) { Text("sin horario").tag(-1); ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Divider()
                    if store.pomodoro.phase == .idle {
                        Button("empezar pomodoro (25 min)") { store.pomodoro.start(now: ProcessInfo.processInfo.systemUptime) }
                    } else {
                        if store.pomodoro.isPaused { Button("reanudar") { store.pomodoro.resume(now: ProcessInfo.processInfo.systemUptime) } }
                        else { Button("pausar") { store.pomodoro.pause(now: ProcessInfo.processInfo.systemUptime) } }
                        Button("parar pomodoro") { store.pomodoro.stop() }
                        Text("ciclos completados: \(store.pomodoro.completed)")
                    }
                }
                Toggle("bailar con la música", isOn: $store.danceToMusic)
                Menu("guardarropa", systemImage: "tshirt") {
                    ForEach(Outfit.allCases) { outfit in
                        Toggle(outfit.title, isOn: Binding(get: { store.wardrobe.contains(outfit) }, set: { _ in store.toggleOutfit(outfit) }))
                    }
                    Divider()
                    Toggle("atuendos de temporada", isOn: $store.seasonalOutfits)
                }
                Menu("sonido", systemImage: "speaker.wave.2") {
                    Toggle("sonidos de la isla", isOn: $store.soundsEnabled)
                    Picker("volumen", selection: $store.soundVolume) { ForEach([0.15, 0.3, 0.4, 0.6, 0.8, 1.0], id: \.self) { Text("\(Int($0 * 100)) %").tag($0) } }
                    Button("probar sonido de terminado") { SoundEngine.shared.enabled = store.soundsEnabled; SoundEngine.shared.volume = Float(store.soundVolume); SoundEngine.shared.play(.done) }
                }
                Menu("puntos de restauración") {
                    Toggle("crear uno antes de permitir cambios", isOn: $store.autoRestorePoints)
                    Button("crear punto ahora") {
                        if RestorePoints.create(workspace: store.mission.workspace, label: "manual") == nil { NSSound.beep() }
                        store.refreshRestorePoints()
                    }
                    if store.restorePoints.isEmpty { Text("sin puntos en este proyecto") }
                    ForEach(store.restorePoints.prefix(10)) { point in
                        Button("restaurar \(point.at.formatted(date: .omitted, time: .shortened)) · \(point.label)") { RestoreDialog.confirm(store: store, point: point) }
                    }
                }
                .onAppear { store.refreshRestorePoints() }
                if !store.approvalRules.isEmpty {
                    Menu("reglas de aprobación (\(store.approvalRules.count))") {
                        ForEach(store.approvalRules) { rule in
                            Button("revocar: \(rule.title) · \(rule.scope.rawValue)") { ApprovalRules.shared.revoke(id: rule.id) }
                        }
                        Divider()
                        Button("revocar todas") { ApprovalRules.shared.revokeAll() }
                    }
                }
                Toggle("aparición automática", isOn: $store.autoVisibility)
            Toggle("mantener mascotas visibles", isOn: $store.pinSession)
            Toggle("mostrar claude", isOn: Binding(get: { !store.muteClaude }, set: { store.muteClaude = !$0 }))
            Toggle("mostrar codex", isOn: Binding(get: { !store.muteCodex }, set: { store.muteCodex = !$0 }))
                Toggle("burbuja de actividad", isOn: $store.showBubble)
                Divider()
                Menu("animaciones", systemImage: "figure.run") { animationMenu }
                Menu("aspecto", systemImage: "paintpalette") { appearanceMenu }
                Menu("codex", systemImage: "cpu") { CodexControlMenu(store: store) }
            }
            Menu("operaciones", systemImage: "scope") { MissionControlMenu(control: store.mission) }
            Menu("traspaso claude y codex", systemImage: "arrow.left.arrow.right") {
                HandoffMenu(store: store, handoff: store.handoff, control: store.mission)
            }
            Menu("privacidad y avisos", systemImage: "lock.shield") { protectionMenu }
        }

        Section {
            Menu("herramientas de prueba", systemImage: "wrench.and.screwdriver") { previewMenu }
            Divider()
            Button("salir", systemImage: "power") { NSApp.terminate(nil) }
        }
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

    @ViewBuilder private var animationMenu: some View {
        Toggle("activar animaciones", isOn: $store.animationsEnabled)
        Toggle("partido automático", isOn: $store.footballEnabled)
            .disabled(!store.animationsEnabled)
        Divider()
        Button("partido ahora", systemImage: "soccerball") { store.trigger("football") }
            .disabled(!store.pairNear)
        Menu("acciones de claude") {
            Button("saludo") { store.trigger("greet") }
            Button("celebración") { store.trigger("cheer") }
            Button("preocupación") { store.trigger("concern") }
        }
        Menu("acciones de codex") {
            ForEach(CodexGesture.allCases, id: \.self) { gesture in
                Button(gesture.title) { store.triggerCodex(gesture) }
            }
        }
    }

    @ViewBuilder private var appearanceMenu: some View {
        Picker("claude", selection: $store.skin) {
            ForEach(Skin.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker("codex", selection: $store.codexSkin) {
            ForEach(CodexSkin.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }

    @ViewBuilder private var protectionMenu: some View {
        Toggle("ver detalle local de Claude", isOn: $store.showDetail)
        Toggle("avisar si parecen bloqueados", isOn: $store.stallWatch)
        Picker("avisos visuales", selection: $store.alertDisplayMode) {
            ForEach(AlertDisplayMode.allCases) { Text($0.rawValue).tag($0) }
        }
        Button(store.alertsAreSnoozed ? "reactivar avisos" : "silenciar avisos 15 min", systemImage: store.alertsAreSnoozed ? "bell" : "bell.slash") {
            store.alertsAreSnoozed ? store.wakeAlerts() : store.snoozeAlerts()
        }
        Toggle("bloquear herramientas si el proyecto cambia", isOn: $store.blockOnChange)
        Divider()
        Toggle("compartir nombre del proyecto", isOn: $store.shareProject)
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
