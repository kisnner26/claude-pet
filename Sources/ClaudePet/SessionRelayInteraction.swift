import AppKit

/// Acciones visibles del relevo. Se inyectan para comprobar el flujo completo sin diálogos de prueba.
@MainActor
struct SessionRelayInteraction {
    var chooseWorkspace: (String) -> String?
    var editContext: (Agent, String, String) -> String?
    var preview: (String, String, String) -> Bool
    var showSaved: (URL, Agent) -> Void
    var inform: (String, String) -> Void
    var reveal: (URL) -> Void
    var copy: (String) -> Void
    var open: (Agent) -> Void
    var launch: ((Agent) async throws -> Void)? = nil

    static let live = SessionRelayInteraction(
        chooseWorkspace: { suggested in
            let panel = NSOpenPanel()
            panel.message = "elige la carpeta del proyecto con código; el relevo se guardará aparte en ~/.claude-pet/handoff/"
            panel.prompt = "elegir proyecto"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            if !suggested.isEmpty { panel.directoryURL = URL(fileURLWithPath: suggested) }
            NSApp.activate(ignoringOtherApps: true)
            return panel.runModal() == .OK ? panel.url?.path : nil
        },
        editContext: { source, project, initial in
            let alert = NSAlert()
            alert.messageText = "contexto de \(source.displayName) para \(project)"
            alert.informativeText = "pega un resumen del chat: objetivo, decisiones, trabajo hecho y próximo paso. la mascota no puede leer el historial de codex ni claude desde esta carpeta."
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 180))
            scroll.hasVerticalScroller = true
            let editor = NSTextView(frame: scroll.bounds)
            editor.string = initial
            editor.isEditable = true
            editor.font = NSFont.systemFont(ofSize: 13)
            scroll.documentView = editor
            alert.accessoryView = scroll
            alert.window.initialFirstResponder = editor
            alert.addButton(withTitle: "previsualizar")
            alert.addButton(withTitle: "cancelar")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn ? editor.string : nil
        },
        preview: { text, title, action in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = "comprueba el contexto antes de usarlo en el otro agente."
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 230))
            scroll.hasVerticalScroller = true
            let view = NSTextView(frame: scroll.bounds)
            view.string = text
            view.isEditable = false
            view.isSelectable = true
            view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            scroll.documentView = view
            alert.accessoryView = scroll
            alert.addButton(withTitle: action)
            alert.addButton(withTitle: "cancelar")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        },
        showSaved: { url, destination in
            let alert = NSAlert()
            alert.messageText = "relevo guardado"
            alert.informativeText = "archivo: \(url.path)\n\nel contexto también quedó copiado para pegarlo en \(destination.displayName)."
            alert.addButton(withTitle: "mostrar archivo")
            alert.addButton(withTitle: "cerrar")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        },
        inform: { title, text in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        copy: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        open: { agent in
            let bundle = agent == .claude ? AppPresence.claudeBundle : AppPresence.codexBundle
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        },
        launch: { agent in
            let bundle = agent == .claude ? AppPresence.claudeBundle : AppPresence.codexBundle
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                throw NSError(domain: "SessionRelay", code: 1, userInfo: [NSLocalizedDescriptionKey: "no encontré la app de \(agent.rawValue). el contexto quedó copiado; abre tu agente y pégalo allí."])
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    )
}
