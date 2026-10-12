import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: PetStore

    private var connectionLabel: String {
        store.bridgeOK ? "puente local activo" : "puente local no disponible"
    }

    private var companionLabel: String {
        store.peer.map { "pet bus: \($0.id) presente" }
            ?? (store.busOK ? "pet bus: sin otras mascotas" : "pet bus no disponible")
    }

    var body: some View {
        Section("en vivo") {
            Label("claude: \(store.state.label.lowercased())", systemImage: stateSymbol)
            Label(connectionLabel, systemImage: store.bridgeOK ? "link" : "link.badge.plus")
            Label(store.claudePresent ? "claude code en uso" : "claude code en reposo", systemImage: "curlybraces")
            Label(store.codexPresent ? "codex en uso" : "codex en reposo", systemImage: "sparkles")
            Label(companionLabel, systemImage: "dot.radiowaves.left.and.right")
            if let warning = store.safetyAlert {
                Label(warning.title, systemImage: "exclamationmark.triangle.fill")
            }
            if store.reviewReady {
                Button("abrir diff listo para revisión", systemImage: "arrow.left.arrow.right") { store.openReview() }
            }
        }

        Section("ahora") {
            Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                AppController.shared.toggleWindow()
            }
            Toggle("aparición automática", systemImage: "figure.walk.arrival", isOn: $store.autoVisibility)
            Toggle("burbuja de actividad", systemImage: "text.bubble", isOn: $store.showBubble)
            Button("abrir tablero operativo", systemImage: "rectangle.3.group") { AppController.shared.showMissionDashboard() }
            Menu("operaciones", systemImage: "scope") { MissionControlMenu(control: store.mission) }
            Menu("codex", systemImage: "cpu") { CodexControlMenu(store: store) }
        }

        Section("experiencia") {
            Menu("animaciones", systemImage: "figure.run") { animationMenu }
            Menu("aspecto", systemImage: "paintpalette") { appearanceMenu }
        }

        Section("protección") {
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
