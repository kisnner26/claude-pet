import SwiftUI

/// Un relevo es un contexto portable, no una importación del historial nativo.
struct SessionRelayView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var relay: SessionRelayController

    @State private var source: Agent = .claude
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("continuar en otro agente")
                .font(.title2.weight(.semibold))
            Text("guarda el contexto de tu tarea y pásalo al otro agente en tres pasos.")
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

            VStack(alignment: .leading, spacing: 8) {
                caption("2 · proyecto")
                HStack(spacing: 10) {
                    Text(workspace.isEmpty ? "ninguna carpeta elegida" : workspace)
                        .font(.callout.monospaced())
                        .foregroundStyle(workspace.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("elegir carpeta…") {
                        if let path = relay.chooseProject(suggested: workspace) {
                            workspace = path
                            error = nil
                        }
                    }
                }
                Text("elige donde está el código; el relevo se guarda aparte, no en esta carpeta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("3 · contexto del chat")
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
                    if context.isEmpty {
                        Text("objetivo, decisiones, trabajo hecho y siguiente paso…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $context)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(height: 132)
                Text("pega un resumen: la app no puede leer el historial de chats desde la carpeta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

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
                Button("revisar relevo", systemImage: "arrow.right") { prepare() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.35, green: 0.58, blue: 0.96))
            }
        }
        .controlSize(.large)
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func prepare() {
        do {
            let result = try relay.prepare(source: source, workspace: workspace, context: context,
                                           state: source == .claude ? store.state : store.codexState)
            preview = result.0
            prompt = result.1
            savedURL = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func refresh() {
        if workspace.isEmpty { workspace = store.mission.workspace }
        last = try? SessionCapsuleStore.latest().capsule
    }
}
