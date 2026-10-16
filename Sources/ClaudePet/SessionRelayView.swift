import SwiftUI

/// Selección explícita de un chat local para crear un contexto portable.
struct SessionRelayView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var relay: SessionRelayController

    @State private var source: Agent = .claude
    @State private var sessions: [LocalAgentSession] = []
    @State private var selectedSessionID = ""
    @State private var loading = true
    @State private var manual = false
    @State private var workspace = ""
    @State private var context = ""
    @State private var preview: SessionCapsule?
    @State private var prompt = ""
    @State private var last: SessionCapsule?
    @State private var savedURL: URL?
    @State private var error: String?

    init(store: PetStore) {
        self.store = store
        _relay = ObservedObject(wrappedValue: store.relay)
    }

    var body: some View {
        ZStack {
            GlassBackground()
            Color.black.opacity(0.32)
            VStack(alignment: .leading, spacing: 18) {
                header
                if let capsule = preview {
                    previewContent(capsule)
                } else {
                    editor
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(Color(red: 1, green: 0.58, blue: 0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(.white.opacity(0.12))
                footer
            }
            .padding(24)
        }
        .frame(width: 560, height: 590)
        .environment(\.colorScheme, .dark)
        .onAppear(perform: refresh)
        .onChange(of: source) { _ in
            selectedSessionID = sessions.first(where: { $0.agent == source })?.id ?? ""
            error = nil
        }
        .onChange(of: selectedSessionID) { _ in workspace = "" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("continuar en otro agente")
                .font(.title2.weight(.semibold))
            Text("elige un chat local. la app detectará su proyecto y preparará el contexto.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                caption("1 · dirección")
                Picker("agente de origen", selection: $source) {
                    Text("claude → codex").tag(Agent.claude)
                    Text("codex → claude").tag(Agent.codex)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if manual { manualEditor } else { sessionPicker }
            Spacer(minLength: 0)
        }
    }

    private var sessionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("2 · conversación")
            if loading {
                ProgressView("buscando chats locales…")
            } else if sourceSessions.isEmpty {
                Text("no encontré chats locales de \(source.rawValue). puedes usar el modo manual.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("chat de \(source.rawValue)", selection: $selectedSessionID) {
                    ForEach(sourceSessions) { session in
                        Text("\(session.project) · \(session.title)").tag(session.id)
                    }
                }
                .labelsHidden()
                if let selected = sourceSessions.first(where: { $0.id == selectedSessionID }) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.project).font(.headline)
                        Text(workspace.isEmpty ? selected.workspace : workspace)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("última actividad: \(selected.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("cambiar carpeta del proyecto…") {
                            if let path = relay.chooseProject(suggested: workspace.isEmpty ? selected.workspace : workspace) {
                                workspace = path
                                error = nil
                            }
                        }
                        .font(.callout)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("leeré los mensajes visibles de ese chat; no necesitas elegir carpeta ni escribir un resumen.")
                .font(.callout).foregroundStyle(.secondary)
            Button("no encuentro mi chat · usar contexto manual") {
                manual = true
                error = nil
            }
            .font(.callout)
        }
    }

    private var manualEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("volver a chats locales") { manual = false; error = nil }
                .font(.callout)
            caption("2 · carpeta del proyecto")
            HStack(spacing: 10) {
                Text(workspace.isEmpty ? "ninguna carpeta elegida" : workspace)
                    .font(.callout.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("elegir carpeta…") {
                    if let path = relay.chooseProject(suggested: workspace) { workspace = path; error = nil }
                }
            }
            Text("elige la carpeta con código, no una carpeta vacía para guardar relevos.")
                .font(.caption).foregroundStyle(.secondary)
            caption("3 · resumen del chat")
            TextField("objetivo, decisiones, trabajo hecho y siguiente paso…", text: $context, axis: .vertical)
                .lineLimit(5...8)
                .textFieldStyle(.roundedBorder)
            Text("solo si no aparece el chat local que quieres continuar.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sourceSessions: [LocalAgentSession] { sessions.filter { $0.agent == source } }

    private func previewContent(_ capsule: SessionCapsule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                caption("revisar antes de continuar")
                Spacer()
                Text("\(capsule.source.rawValue) → \(capsule.source.other.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(capsule.project)
                .font(.headline)
            Text(capsule.workspace)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ScrollView {
                Text(prompt)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            Text("se copiará el texto y se abrirá \(capsule.source.other.rawValue). pégalo allí con cmd+v.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let savedURL {
                Text("guardado en \(savedURL.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if preview != nil {
                Button("editar") {
                    preview = nil
                    savedURL = nil
                    error = nil
                }
            } else if let last {
                Button("usar último: \(last.project)") {
                    do {
                        let item = try SessionCapsuleStore.latest()
                        source = item.capsule.source
                        workspace = item.capsule.workspace
                        context = item.capsule.task
                        manual = true
                        preview = item.capsule
                        prompt = SessionCapsulePrompt.build(item.capsule, destination: item.capsule.source.other)
                        savedURL = item.url
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let capsule = preview {
                Button(savedURL == nil ? "guardar, copiar y abrir \(capsule.source.other.rawValue)" : "copiar y abrir \(capsule.source.other.rawValue)", systemImage: "arrow.up.right") {
                    do {
                        if savedURL == nil { savedURL = try relay.saveAndContinue(capsule, prompt: prompt) }
                        else { relay.copyAndContinue(capsule) }
                        last = capsule
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.35, green: 0.58, blue: 0.96))
            } else {
                Button(manual ? "revisar relevo" : "ver contexto detectado", systemImage: "arrow.right") { prepare() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.35, green: 0.58, blue: 0.96))
                    .disabled(loading || (!manual && selectedSessionID.isEmpty))
            }
        }
        .controlSize(.large)
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func prepare() {
        do {
            let selected = sessions.first { $0.id == selectedSessionID && $0.agent == source }
            let path = manual ? workspace : (workspace.isEmpty ? selected?.workspace ?? "" : workspace)
            let text: String
            if manual { text = context }
            else {
                guard let selected else { throw LocalAgentSessionError.noMessages }
                text = try LocalAgentSessionReader.transcript(selected)
            }
            let result = try relay.prepare(source: source, workspace: path, context: text,
                                           state: source == .claude ? store.state : store.codexState)
            preview = result.0
            prompt = result.1
            savedURL = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func refresh() {
        last = try? SessionCapsuleStore.latest().capsule
        Task.detached {
            let found = LocalAgentSessionReader.recent(for: .claude) + LocalAgentSessionReader.recent(for: .codex)
            await MainActor.run {
                sessions = found
                selectedSessionID = found.first(where: { $0.agent == source })?.id ?? ""
                loading = false
            }
        }
    }
}
