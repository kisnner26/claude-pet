import SwiftUI
import AppKit

/// Boton redondo de cristal que, al pasar el cursor, se expande y muestra su nombre. Sin cursor es solo un icono: no satura.
struct DockButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var badge: Int?
    /// Solo para capturas: fuerza el estado expandido.
    var previewHover = false
    let action: () -> Void
    @State private var hovering = false
    private var hover: Bool { hovering || previewHover }

    var body: some View {
        Button(action: action) {
            HStack(spacing: hover ? 6 : 0) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).frame(width: 15)
                if hover { Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize().transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading))) }
            }
            .foregroundColor(.white.opacity(hover || prominent ? 1 : 0.85))
            .padding(.horizontal, hover ? 11 : 6.5).frame(height: 28)
            .background(Capsule().fill(prominent ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE0824F), Color(hex: 0x8E6BE0)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(hover ? 0.18 : 0.09))))
            .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0.25 : 0.1), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.black)
                        .padding(.horizontal, 3.5).frame(minWidth: 12, minHeight: 12).background(Capsule().fill(Color.white)).offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(DockButtonStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hover)
        .help(title).accessibilityLabel(title)
    }
}

private struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1).animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Acceso rapido de la isla: hasta cinco acciones segun el contexto, y el resto en el menu "+".
struct QuickDock: View {
    @ObservedObject var store: PetStore
    @ObservedObject var music: MusicController
    @ObservedObject var plugins: PluginHost
    @ObservedObject private var front = FrontAppTracker.shared
    @ObservedObject private var remotes = GitRemoteCache.shared
    let summary: () -> String
    /// Solo para capturas: contexto fijo en vez del real.
    var contextOverride: QuickContext?
    var iconOverride: NSImage?
    /// Las capturas no pueden dibujar el menu nativo del +.
    var hideOverflow = false
    /// En la pagina de herramientas: todas las acciones disponibles en una rejilla, sin el menu "+".
    var showAll = false

    private var workspace: String { store.mission.workspace }

    private var context: QuickContext {
        if let o = contextOverride { return o }
        return QuickContext(hasWorkspace: !workspace.isEmpty, isRepo: store.mission.git.available, changeCount: store.mission.git.affected, agentChanges: store.mission.changes.count,
                     commiteroAvailable: CommiteroLauncher.available(), terminalAvailable: store.terminalTargetAvailable,
                     musicAvailable: store.musicPlayer && music.nowPlaying != nil, musicPlaying: music.isPlaying,
                     pomodoroRunning: store.pomodoro.phase != .idle, alertsSnoozed: store.alertsAreSnoozed,
                     hasPerimeter: store.perimeters.contains { $0.root == workspace },
                     profile: store.quickAppAware ? front.profile : .other, frontAppName: front.name, hasRemote: !workspace.isEmpty && remotes.webURL(for: workspace) != nil, branch: store.mission.git.branch, focusOn: store.focusManual, labAvailable: LabLauncher.shared.available)
    }

    var body: some View {
        let c = context
        let layout = QuickActions.layout(order: store.quickActions, context: c, appAware: store.quickAppAware)
        let extra = plugins.actions(place: "island")
        if showAll {
            let all = QuickActions.layout(order: QuickActions.allOrdered, context: c, appAware: store.quickAppAware)
            let every = all.visible + all.overflow
            // filas de tres: sin LazyVGrid, para que tambien se pueda dibujar en las capturas
            let items: [(String, String, Int?, Bool, () -> Void)] = every.map { a in
                let d = QuickActions.descriptor(a, c)
                return (d.title, d.symbol, d.badge, d.prominent, { perform(a) })
            } + extra.map { item in
                (item.action.title, item.action.symbol ?? "puzzlepiece.extension", nil, false, { plugins.run(item.plugin.id, item.action, name: item.plugin.manifest.name) })
            }
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 6) {
                        ForEach(Array(items[start..<min(start + 3, items.count)].enumerated()), id: \.offset) { _, it in
                            toolChip(it.0, it.1, badge: it.2, prominent: it.3, action: it.4)
                        }
                        ForEach(0..<(3 - min(3, items.count - start)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
        } else {
        HStack(spacing: 6) {
            if store.quickAppAware, c.profile != .other, let icon = iconOverride ?? front.icon { appBadge(icon, c.profile) }
            ForEach(layout.visible) { a in
                let d = QuickActions.descriptor(a, c)
                DockButton(title: d.title, symbol: d.symbol, prominent: d.prominent, badge: d.badge) { perform(a) }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if !hideOverflow, !layout.overflow.isEmpty || !extra.isEmpty {
                Menu {
                    ForEach(layout.overflow) { a in
                        let d = QuickActions.descriptor(a, c)
                        Button(d.title, systemImage: d.symbol) { perform(a) }
                    }
                    if !extra.isEmpty {
                        if !layout.overflow.isEmpty { Divider() }
                        ForEach(extra, id: \.action.id) { item in
                            Button(item.action.title, systemImage: item.action.symbol ?? "puzzlepiece.extension") { plugins.run(item.plugin.id, item.action, name: item.plugin.manifest.name) }
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.06))).overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("más acciones")
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: layout.visible)
        }
    }

    private func toolChip(_ title: String, _ symbol: String, badge: Int?, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 16)
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if let badge, badge > 0 { Text("\(badge)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.black).padding(.horizontal, 4).background(Capsule().fill(Color.white)) }
            }
            .foregroundColor(.white.opacity(0.9)).padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(prominent ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE0824F).opacity(0.8), Color(hex: 0x8E6BE0).opacity(0.8)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8))
        }.buttonStyle(.plain)
    }

    /// La app donde estas: explica por que las herramientas han cambiado.
    private func appBadge(_ icon: NSImage, _ profile: AppProfile) -> some View {
        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18)
            .padding(4).background(Circle().fill(Color.white.opacity(0.07))).overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .help("acceso rápido para \(profile.title): \(front.name ?? "")").accessibilityLabel("acceso rápido para \(profile.title)")
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private func perform(_ a: QuickAction) {
        switch a {
        case .commit: if !CommiteroLauncher.launch(workspace: workspace) { NSSound.beep() }
        case .terminal: store.focusTerminal()
        case .changes: store.openLatestDiff()
        case .music: music.send(.playPause)
        case .mission: AppController.shared.showMissionDashboard()
        case .summary:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(summary(), forType: .string); plugins.show("resumen copiado")
        case .folder: NSWorkspace.shared.open(URL(fileURLWithPath: workspace))
        case .restorePoint:
            if RestorePoints.create(workspace: workspace, label: "manual") != nil { plugins.show("punto de restauración creado") } else { NSSound.beep() }
            store.refreshRestorePoints()
        case .pomodoro:
            let now = ProcessInfo.processInfo.systemUptime
            if store.pomodoro.phase == .idle { store.pomodoro.start(now: now); plugins.show("pomodoro de 25 min en marcha") } else { store.pomodoro.stop() }
        case .snooze:
            if store.alertsAreSnoozed { store.wakeAlerts() } else { store.snoozeAlerts(); plugins.show("avisos silenciados 15 min") }
        case .relay: AppController.shared.showRelay()
        case .perimeter:
            if !store.perimeters.contains(where: { $0.root == workspace }) { _ = PerimeterStore.shared.upsert(Perimeter(root: workspace)) }
            AppController.shared.showSettings(page: .perimetro)
        case .settings: AppController.shared.showSettings()
        case .openInEditor:
            guard let url = front.appURL, let bid = front.bundleID else { NSSound.beep(); return }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: workspace)) ?? []
            let target = ProjectOpener.target(bundleID: bid, workspace: workspace, entries: entries)
            NSWorkspace.shared.open([URL(fileURLWithPath: target)], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
            plugins.show("abriendo el proyecto en \(front.name ?? "el editor")")
        case .openRepoWeb:
            if let web = remotes.webURL(for: workspace), let u = URL(string: web) { NSWorkspace.shared.open(u) } else { NSSound.beep() }
        case .copyCd:
            guard let q = ShellQuote.single(workspace) else { NSSound.beep(); return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("cd " + q, forType: .string); plugins.show("«cd» copiado")
        case .copyPath:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(workspace, forType: .string); plugins.show("ruta copiada")
        case .musicPrev: music.send(.previous)
        case .musicNext: music.send(.next)
        case .copyBranch:
            let b = store.mission.git.branch
            guard !b.isEmpty else { NSSound.beep(); return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(b, forType: .string); plugins.show("rama copiada")
        case .labGalaxy, .labCity, .labRadar:
            let tool: LabTool = a == .labGalaxy ? .galaxy : a == .labCity ? .city : .radar
            let ws = workspace
            Task { @MainActor in
                plugins.show("abriendo \(tool.title)…")
                if case .failure(let why) = await LabLauncher.shared.open(tool, workspace: ws) { plugins.show(why) }
            }
        case .focus:
            store.focusManual.toggle(); plugins.show(store.focusManual ? "modo foco activado" : "modo foco apagado")
        }
    }
}
