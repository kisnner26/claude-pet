import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: PetStore

    var body: some View {
        Section("en vivo") {
            Label("claude: \(store.state.label.lowercased())", systemImage: stateSymbol)
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
        }

        Section {
            Button("abrir tablero", systemImage: "rectangle.3.group") { AppController.shared.showMissionDashboard() }
            Button(store.userHidden ? "mostrar mascotas" : "ocultar mascotas", systemImage: store.userHidden ? "eye" : "eye.slash") {
                AppController.shared.toggleWindow()
            }
        }

        Section {
            Menu("mascotas", systemImage: "pawprint") {
                Toggle("aparición automática", isOn: $store.autoVisibility)
                Toggle("burbuja de actividad", isOn: $store.showBubble)
                Divider()
                Menu("animaciones", systemImage: "figure.run") { animationMenu }
                Menu("aspecto", systemImage: "paintpalette") { appearanceMenu }
                Menu("codex", systemImage: "cpu") { CodexControlMenu(store: store) }
            }
            Menu("operaciones", systemImage: "scope") { MissionControlMenu(control: store.mission) }
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
