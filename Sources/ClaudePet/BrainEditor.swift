import SwiftUI
import AppKit

extension Notification.Name { static let brainChanged = Notification.Name("claudepet.brainChanged") }

/// El panel de la isla no puede recibir teclado, asi que escribir o editar una nota abre esta ventana pequena.
@MainActor
final class BrainEditorWindow {
    static var current: NSWindow?

    static func present(project: String, note: BrainNote?) {
        current?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 270), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = note == nil ? "nueva nota del cerebro" : "editar nota del cerebro"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .floating
        window.contentView = NSHostingView(rootView: BrainEditorView(project: project, note: note, close: { window.close() }))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        current = window
    }
}

private struct BrainEditorView: View {
    let project: String
    let note: BrainNote?
    let close: () -> Void
    @State private var text: String
    @State private var kind: BrainKind
    @State private var global = false
    @State private var error: String?

    init(project: String, note: BrainNote?, close: @escaping () -> Void) {
        self.project = project; self.note = note; self.close = close
        _text = State(initialValue: note?.text ?? "")
        _kind = State(initialValue: note?.kind ?? .hecho)
    }

    private var scopeName: String { global ? "global" : BrainStore.clean(project: project) }
    private var left: Int { BrainStore.maxText - text.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(note == nil ? "algo que sus próximas sesiones deben saber" : "editando una nota de \(note!.agent)").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            TextEditor(text: $text)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                .frame(height: 96)
                .onChange(of: text) { new in if new.count > BrainStore.maxText { text = String(new.prefix(BrainStore.maxText)) } }
            HStack {
                Picker("tipo", selection: $kind) { ForEach(BrainKind.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                Text("\(left)").font(.system(size: 10, design: .monospaced)).foregroundStyle(left < 20 ? Color.orange : Color.secondary)
            }
            if note == nil {
                Picker("ámbito", selection: $global) {
                    Text("este proyecto · \(BrainStore.clean(project: project))").tag(false)
                    Text("global · todos los proyectos").tag(true)
                }.pickerStyle(.radioGroup).font(.system(size: 11))
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Color.red) }
            Spacer(minLength: 0)
            HStack {
                if let note { Button("olvidar", role: .destructive) { BrainStore.shared.forget(id: note.short, project: project); finish() } }
                Spacer()
                Button("cancelar", action: close).keyboardShortcut(.cancelAction)
                Button("guardar", action: save).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 270)
    }

    private func save() {
        let result: Result<BrainNote, BrainError>
        if let note { result = BrainStore.shared.update(id: note.short, project: project, kind: kind.rawValue, text: text) }
        else { result = BrainStore.shared.add(agent: "tu", kind: kind.rawValue, text: text, project: global ? "global" : project) }
        switch result {
        case .success: finish()
        case .failure(.secret): error = "parece una clave o un token: el cerebro no guarda secretos"
        case .failure(.empty): error = "la nota está vacía"
        case .failure: error = "no se pudo guardar"
        }
    }

    private func finish() { NotificationCenter.default.post(name: .brainChanged, object: nil); close() }
}
