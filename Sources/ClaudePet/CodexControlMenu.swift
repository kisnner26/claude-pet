import SwiftUI

struct CodexControlMenu: View {
    @ObservedObject var store: PetStore
    private var statusText: String { store.peer?.state.label.lowercased() ?? "en reposo" }

    var body: some View {
        Group {
            if !store.claudePresent {
                Text("modo solo: codex tiene el escenario")
            } else if store.collaborationActive {
                Text("modo dúo: intercambio de paquetes activo")
            } else {
                Text("codex: \(statusText)")
            }
            Picker("aspecto de codex", selection: $store.codexSkin) {
                ForEach(CodexSkin.allCases, id: \.self) { skin in
                    Text(skin.title).tag(skin)
                }
            }
            Toggle("gestos automáticos", isOn: $store.codexGesturesEnabled)
            Divider()
            ForEach(CodexGesture.allCases, id: \.self) { gesture in
                Button(gesture.title) { store.triggerCodex(gesture) }
            }
            Divider()
            Menu("probar estado de codex") {
                ForEach(PetState.allCases, id: \.self) { state in
                    Button(state.label.capitalized) { store.previewCodex(state) }
                }
            }
        }
    }
}
