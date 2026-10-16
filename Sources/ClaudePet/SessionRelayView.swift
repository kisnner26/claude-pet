import SwiftUI

struct SessionRelayView: View {
    @StateObject private var model: SessionRelayModel
    init(store: PetStore) { _model = StateObject(wrappedValue: SessionRelayModel(relay: store.relay)) }

    var body: some View {
        ZStack {
            GlassBackground()
            Color.black.opacity(0.32)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.capsule == nil ? "¿qué chat quieres continuar?" : "contexto listo para continuar")
                        .font(.title2.bold())
                    Text(model.capsule == nil ? "elige el origen y la conversación." : model.summary)
                        .font(.callout).foregroundStyle(.secondary)
                }
                if model.capsule != nil { preview } else { selection }
                if model.busy { ProgressView(model.capsule == nil ? "leyendo sesiones…" : "preparando destino…").controlSize(.small) }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(Color(red: 1, green: 0.65, blue: 0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let status = model.status {
                    Label(status, systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                footer
            }
            .padding(24)
            .padding(.top, 16)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 640, idealHeight: 690)
        .environment(\.colorScheme, .dark)
        .task { await model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .relayPresented)) { _ in
            Task { await model.reload() }
        }
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("dirección del relevo", selection: $model.source) {
                Text("claude → codex").tag(Agent.claude)
                Text("codex → claude").tag(Agent.codex)
            }.pickerStyle(.segmented).labelsHidden().disabled(model.busy)
            if model.manual {
                Button("volver a mis chats") { model.manual = false }
                Text("carpeta con el código").font(.headline)
                project
                TextField("objetivo, trabajo hecho y siguiente paso", text: $model.context, axis: .vertical)
                    .lineLimit(6...12).textFieldStyle(.roundedBorder)
                Spacer(minLength: 0)
            } else {
                HStack {
                    TextField("buscar por chat o proyecto", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                    Button("actualizar", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                        .disabled(model.busy)
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if model.visibleSessions.isEmpty && !model.busy {
                            Text(model.query.isEmpty ? "no hay chats locales disponibles de este agente." : "no hay coincidencias. prueba con otro nombre.")
                                .foregroundStyle(.secondary).padding(.vertical, 30)
                        }
                        ForEach(model.visibleSessions) { session in
                            Button { model.selectedID = session.id } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: model.selectedID == session.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.selectedID == session.id ? Color.accentColor : .secondary)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title).font(.body).lineLimit(2).multilineTextAlignment(.leading)
                                        HStack {
                                            Text(session.project).lineLimit(1)
                                            Spacer()
                                            Text(session.modifiedAt, format: .dateTime.day().month().hour().minute())
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.selectedID == session.id ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedID == session.id ? .isSelected : [])
                            .disabled(model.busy)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if let selected = model.selected {
                    Text("seleccionado: \(selected.title)").font(.callout).lineLimit(1)
                    project
                }
                HStack {
                    Text("\(model.visibleSessions.count) chats · lectura local").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("pegar contexto manual", action: model.enterManual)
                        .font(.callout).disabled(model.busy)
                }
            }
        }
    }

    private var project: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("proyecto").font(.caption).foregroundStyle(.secondary)
                Text(model.projectPath.isEmpty ? "elige la carpeta del código" : model.projectPath)
                    .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    .help(model.projectPath)
            }
            Spacer(minLength: 0)
            Button("cambiar…", action: model.chooseProject).disabled(model.busy)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(model.capsule?.project ?? "") · \(model.source.rawValue) → \(model.source.other.rawValue)").font(.headline)
            Text("puedes editar este texto antes de copiarlo.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $model.prompt)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("contexto que se copiará al otro agente")
            Text("al abrir la app de \(model.source.other.rawValue), elige el proyecto o modo de código y pega con cmd+v.")
                .font(.callout).foregroundStyle(.secondary)
            if model.savedURL != nil { Button("mostrar archivo guardado", action: model.reveal).font(.callout) }
        }
    }

    private var footer: some View {
        HStack {
            if model.capsule != nil { Button("volver", action: model.back).disabled(model.busy) }
            else { Button("último relevo", action: model.useLatest).disabled(model.busy) }
            Spacer()
            if model.capsule != nil {
                Button("solo copiar") { Task { await model.complete(open: false) } }
                    .disabled(model.busy || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("copiar y abrir \(model.source.other.rawValue)") { Task { await model.complete(open: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("preparar contexto") { Task { await model.prepare() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canPrepare)
            }
        }.controlSize(.large)
    }
}

extension Notification.Name {
    static let relayPresented = Notification.Name("local.claudepet.relayPresented")
}
