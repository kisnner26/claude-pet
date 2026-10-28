import SwiftUI
import AppKit

struct PluginTextSetting: View {
    let pluginID: String
    let def: PluginSetting
    @ObservedObject var host: PluginHost
    @State private var text = ""

    var body: some View {
        SRow(title: def.title, detail: def.detail) {
            TextField(def.defaultValue ?? "", text: $text)
                .textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 220)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.08))).overlay(Capsule().stroke(SettingsTheme.line, lineWidth: 1))
                .onSubmit { host.setSetting(pluginID, key: def.key, value: text) }
        }
        .onAppear { text = host.registry.settingValue(pluginID, def) }
        .onDisappear { host.setSetting(pluginID, key: def.key, value: text) }
    }
}

struct PluginCard: View {
    let row: PluginRow
    @ObservedObject var host: PluginHost

    private var m: PluginManifest { row.plugin.manifest }
    private var tint: Color {
        switch row.status { case .enabled: return SettingsTheme.green; case .needsApproval: return SettingsTheme.amber; case .invalid: return SettingsTheme.red; case .disabled: return SettingsTheme.codexLight }
    }
    private var statusText: String {
        switch row.status { case .enabled: return "activo"; case .disabled: return "desactivado"; case .needsApproval: return "pide permisos nuevos"; case .invalid: return "no válido" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 20)).foregroundStyle(SettingsTheme.duoDiagonal)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(m.name).font(.system(size: 16, weight: .bold))
                        Text("v\(m.version)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                        SBadge(text: statusText, color: tint)
                    }
                    Text("de \(m.author)").font(.system(size: 11.5)).foregroundStyle(SettingsTheme.mute)
                    Text(m.description).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if row.status != .invalid {
                    Toggle(m.name, isOn: Binding(get: { row.status == .enabled }, set: { host.setEnabled(row.id, $0) })).labelsHidden().toggleStyle(GlassToggleStyle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

            if !m.permissions.isEmpty {
                FlowBadges(items: m.permissions).padding(.horizontal, 20).padding(.bottom, 10)
            }
            if !row.plugin.problems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(row.plugin.problems, id: \.self) { Text("• \($0)").font(.system(size: 11.5)).foregroundStyle(SettingsTheme.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            if case .needsApproval(let fresh) = row.status {
                SRow(title: "esta versión pide permisos nuevos", detail: fresh.compactMap { PluginPermission(rawValue: $0)?.title }.joined(separator: " · ")) {
                    SButton(title: "revisar", symbol: "checkmark.shield", prominent: true) { host.setEnabled(row.id, true) }
                }
            }
            if row.status == .enabled {
                ForEach(m.settings) { def in
                    SDivider()
                    switch def.type {
                    case "toggle":
                        SToggle(title: def.title, detail: def.detail, isOn: Binding(get: { host.registry.settingValue(row.id, def) == "true" }, set: { host.setSetting(row.id, key: def.key, value: $0 ? "true" : "false") }))
                    case "choice":
                        SMenu(title: def.title, detail: def.detail, selection: Binding(get: { host.registry.settingValue(row.id, def) }, set: { host.setSetting(row.id, key: def.key, value: $0) }), options: (def.options ?? []).map { ($0, $0) })
                    default:
                        PluginTextSetting(pluginID: row.id, def: def, host: host)
                    }
                }
                ForEach(m.actions) { a in
                    SDivider()
                    SRow(title: a.title, detail: "acción · " + (a.places ?? ["menu"]).joined(separator: " y ")) {
                        SButton(title: "probar", symbol: "play.fill") { host.run(row.id, a, name: m.name) }
                    }
                }
            }
            SDivider()
            HStack(spacing: 8) {
                if let h = m.homepage, let url = URL(string: h) { SButton(title: "web", symbol: "arrow.up.right") { NSWorkspace.shared.open(url) } }
                SButton(title: "mostrar carpeta", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([row.plugin.dir]) }
                Spacer()
                SButton(title: "quitar", symbol: "trash", destructive: true) { confirmRemove() }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RadialGradient(colors: [tint.opacity(row.status == .enabled ? 0.16 : 0.07), .clear], center: .topLeading, startRadius: 4, endRadius: 320))
        })
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(SettingsTheme.cardBorder, lineWidth: 1))
    }

    private func confirmRemove() {
        let alert = NSAlert()
        alert.messageText = "¿quitar «\(m.name)»?"
        alert.informativeText = "se borra su carpeta y sus ajustes. esto no se puede deshacer."
        alert.addButton(withTitle: "quitar"); alert.addButton(withTitle: "cancelar"); alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { host.uninstall(row.id) }
    }
}

/// Insignias de permisos en varias filas.
struct FlowBadges: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { p in
                SBadge(text: p, color: SettingsTheme.mute).help(PluginPermission(rawValue: p)?.title ?? p)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PluginsPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var host: PluginHost

    init(store: PetStore) {
        self.store = store
        _host = ObservedObject(wrappedValue: store.plugins)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "añadir") {
                SRow(title: "instalar un plugin", detail: "elige la carpeta del plugin, la que contiene plugin.json. no se activa solo: te enseñamos lo que pide antes.") {
                    SButton(title: "instalar desde carpeta…", symbol: "plus", prominent: true) { pick() }
                }
                SDivider()
                SRow(title: "carpeta de plugins", detail: PluginRegistry.defaultRoot.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    HStack(spacing: 8) {
                        SButton(title: "abrir", symbol: "folder") {
                            try? FileManager.default.createDirectory(at: PluginRegistry.defaultRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                            NSWorkspace.shared.open(PluginRegistry.defaultRoot)
                        }
                        SButton(title: "recargar", symbol: "arrow.clockwise") { host.reload() }
                    }
                }
            }
            if let e = host.lastError {
                SCard { SRow(title: "no se pudo instalar", detail: e) { SBadge(text: "error", color: SettingsTheme.red) } }
            }
            if host.rows.isEmpty {
                SCard(title: "instalados", footer: "los plugins son carpetas con un plugin.json. añaden acciones al menú y a la isla, ajustes propios y reaccionan a eventos. commitero es el ejemplo de referencia.") {
                    SRow(title: "todavía no hay ninguno", detail: "copia uno a la carpeta de plugins o instálalo desde aquí.") { EmptyView() }
                }
            } else {
                ForEach(host.rows) { PluginCard(row: $0, host: host) }
            }
            SCard(title: "crea el tuyo", footer: "un plugin puede ser un script de shell de cinco líneas. se ejecutan con tus mismos privilegios en el Mac, sin caja de arena: activa solo los de autores en los que confíes.") {
                SRow(title: "guía y ejemplos", detail: "manifiesto, permisos, eventos y tres ejemplos listos para copiar.") {
                    SButton(title: "abrir guía", symbol: "arrow.up.right") { if let u = URL(string: "https://github.com/kisnner26/claude-pet/blob/main/docs/PLUGINS.md") { NSWorkspace.shared.open(u) } }
                }
            }
        }
        .onAppear { host.reload() }
    }

    private func pick() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "elige la carpeta del plugin (la que tiene plugin.json)"
        if panel.runModal() == .OK, let url = panel.url { host.install(from: url) }
    }
}
