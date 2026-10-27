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
            if store.state != .idle { Label("desde hace \(store.stateDurationLabel)", systemImage: "timer") }
            Label("codex: \(store.codexPresent ? store.codexState.label.lowercased() : "en reposo")", systemImage: "sparkles")
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
