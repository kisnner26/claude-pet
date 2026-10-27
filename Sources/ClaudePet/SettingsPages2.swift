import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: permisos

struct PermisosPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "responder desde la isla") {
                SToggle(title: "permisos desde la isla", detail: "permitir, denegar o responder preguntas sin ir a la terminal.", isOn: $store.islandPermissions)
                SDivider()
                SToggle(title: "bloquear si el proyecto cambia", detail: "si algo toca el proyecto mientras decides, la petición se detiene.", isOn: $store.blockOnChange)
            }
            restoreCard
            rulesCard
        }
        .onAppear { store.refreshRestorePoints() }
    }

    private var restoreCard: some View {
        SCard(title: "puntos de restauración", footer: "un punto guarda el estado del proyecto para poder volver atrás tras un cambio que no te gustó.") {
            SToggle(title: "crear uno antes de permitir cambios", isOn: $store.autoRestorePoints)
            SDivider()
            SRow(title: "crear un punto ahora", detail: store.mission.workspace.isEmpty ? "no hay un proyecto activo" : store.workspaceLabel) {
                SButton(title: "crear", symbol: "plus") {
                    if RestorePoints.create(workspace: store.mission.workspace, label: "manual") == nil { NSSound.beep() }
                    store.refreshRestorePoints()
                }
            }
            if store.restorePoints.isEmpty {
                SDivider()
                SRow(title: "sin puntos en este proyecto") { EmptyView() }
            }
            ForEach(Array(store.restorePoints.prefix(6))) { point in
                SDivider()
                SRow(title: point.label, detail: point.at.formatted(date: .abbreviated, time: .shortened)) {
                    SButton(title: "restaurar", symbol: "arrow.uturn.backward") { RestoreDialog.confirm(store: store, point: point) }
                }
            }
        }
    }

    private var rulesCard: some View {
        SCard(title: "reglas de aprobación (\(store.approvalRules.count))", footer: "las crea el botón “siempre” de la isla. nunca se crean para acciones de riesgo alto.") {
            if store.approvalRules.isEmpty {
                SRow(title: "ninguna regla activa") { EmptyView() }
            }
            ForEach(Array(store.approvalRules.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { SDivider() }
                SRow(title: rule.title, detail: rule.scope.rawValue) {
                    SButton(title: "revocar", destructive: true) { ApprovalRules.shared.revoke(id: rule.id) }
                }
            }
            if store.approvalRules.count > 1 {
                SDivider()
                SRow(title: "revocar todas") { SButton(title: "revocar", destructive: true) { ApprovalRules.shared.revokeAll() } }
            }
        }
    }
}

// MARK: privacidad

struct PrivacidadPage: View {
    @ObservedObject var store: PetStore
    private let dataDir = NSHomeDirectory() + "/.claude-pet"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "compartir") {
                SToggle(title: "incluir el nombre del proyecto", detail: "al copiar o compartir el resumen semanal.", isOn: $store.shareProject)
            }
            SCard(title: "tus datos", footer: "no hay cuentas. ajustes, estadísticas, reglas y registro de decisiones viven en esta carpeta, con permisos solo para ti.") {
                SRow(title: "carpeta de datos", detail: "~/.claude-pet") {
                    SButton(title: "mostrar en Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dataDir)]) }
                }
                SDivider()
                SRow(title: "registro de decisiones", detail: "cada permiso que permitiste o denegaste, con fecha.") {
                    SButton(title: "abrir", symbol: "doc.text") {
                        let url = URL(fileURLWithPath: AuditLog.path)
                        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) } else { NSSound.beep() }
                    }
                }
                SDivider()
                SRow(title: "borrar estadísticas", detail: "reinicia nivel, racha y el resumen semanal.") {
                    SButton(title: "borrar", symbol: "trash", destructive: true) { ActivityStats.shared.reset(); store.refreshWeeklyRecap() }
                }
            }
        }
    }
}

// MARK: guardarropa

struct GuardarropaPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "atuendos", footer: "subes de nivel con la actividad de la semana: sesiones, herramientas y racha.") {
                ForEach(Array(Outfit.allCases.enumerated()), id: \.element.id) { index, outfit in
                    let unlocked = Evolution.isUnlocked(outfit, level: store.weeklyRecap.level)
                    if index > 0 { SDivider() }
                    SRow(title: outfit.title, detail: unlocked ? nil : "se desbloquea en el nivel \(Evolution.unlockLevel(outfit))") {
                        Toggle("", isOn: Binding(get: { store.wardrobe.contains(outfit) }, set: { _ in store.toggleOutfit(outfit) }))
                            .labelsHidden().toggleStyle(.switch).tint(SettingsTheme.blue).disabled(!unlocked)
                    }
                }
            }
            SCard(title: "temporadas") {
                SToggle(title: "atuendos de temporada", detail: "se viste solo en fechas señaladas.", isOn: $store.seasonalOutfits)
            }
        }
        .onAppear { store.refreshWeeklyRecap() }
    }
}

// MARK: sonidos

struct SonidosPage: View {
    @ObservedObject var store: PetStore
    @State private var replaced: Set<SoundCue> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "general") {
                SToggle(title: "sonidos de la isla", isOn: $store.soundsEnabled)
                SDivider()
                SSlider(title: "volumen general", value: $store.soundVolume, range: 0...1, step: 0.05) { "\(Int($0 * 100)) %" }
                SDivider()
                SToggle(title: "bailar con la música", detail: "la mascota baila mientras suena algo en tu Mac.", isOn: $store.danceToMusic)
            }
            SCard(title: "por categoría", footer: "el volumen de cada categoría se multiplica por el general. en modo foco solo suenan las alertas.") {
                ForEach(Array(SoundCue.Category.allCases.enumerated()), id: \.element) { index, category in
                    if index > 0 { SDivider() }
                    categoryRow(category)
                }
            }
            SCard(title: "cada sonido") {
                ForEach(Array(SoundCue.allCases.enumerated()), id: \.element) { index, cue in
                    if index > 0 { SDivider() }
                    SRow(title: cue.rawValue, detail: replaced.contains(cue) ? "reemplazado por tu archivo" : cue.category.rawValue) {
                        HStack(spacing: 8) {
                            if replaced.contains(cue) { SBadge(text: "tuyo", color: SettingsTheme.green) }
                            SButton(title: "probar", symbol: "play.fill") { play(cue) }
                        }
                    }
                }
            }
            SCard(title: "tus propios sonidos", footer: "deja un archivo con el nombre del sonido (por ejemplo done.wav o permission.m4a) en la carpeta. máximo \(Int(SoundOverrides.maxSeconds)) s y 1 MB; wav, aiff, caf o m4a.") {
                SRow(title: "carpeta de sonidos", detail: SoundOverrides.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    HStack(spacing: 8) {
                        SButton(title: "abrir", symbol: "folder") {
                            try? FileManager.default.createDirectory(atPath: SoundOverrides.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(URL(fileURLWithPath: SoundOverrides.directory))
                        }
                        SButton(title: "comprobar", symbol: "arrow.clockwise") { refresh() }
                    }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func categoryRow(_ category: SoundCue.Category) -> some View {
        let binding = Binding<Double>(get: { store.categoryVolume(category) }, set: { store.soundCategoryVolumes[category] = $0 })
        return SRow(title: category.rawValue) {
            HStack(spacing: 12) {
                Slider(value: binding, in: 0...1, step: 0.05).tint(SettingsTheme.blue).frame(width: 170)
                Text("\(Int(binding.wrappedValue * 100)) %").font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsTheme.mute).frame(width: 46, alignment: .trailing)
            }
        }
    }

    private func play(_ cue: SoundCue) {
        store.applySound(to: SoundEngine.shared)
        SoundEngine.shared.enabled = true
        SoundEngine.shared.play(cue)
    }

    private func refresh() { replaced = Set(SoundCue.allCases.filter { SoundOverrides.file(for: $0) != nil }) }
}

// MARK: foco

struct FocoPage: View {
    @ObservedObject var store: PetStore
    private var hours: [(Int, String)] { [(-1, "sin horario")] + (0..<24).map { ($0, String(format: "%02d:00", $0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "modo foco", footer: "con el foco activo solo suenan las alertas importantes.") {
                SToggle(title: "activar ahora", isOn: $store.focusManual)
                SDivider()
                SMenu(title: "foco desde las", selection: $store.focusStart, options: hours)
                SDivider()
                SMenu(title: "foco hasta las", selection: $store.focusEnd, options: hours)
            }
            SCard(title: "pomodoro") {
                SRow(title: store.pomodoro.phase == .idle ? "parado" : store.pomodoro.phase.rawValue, detail: "ciclos completados: \(store.pomodoro.completed)") {
                    HStack(spacing: 8) {
                        if store.pomodoro.phase == .idle {
                            SButton(title: "empezar 25 min", symbol: "play.fill", prominent: true) { store.pomodoro.start(now: ProcessInfo.processInfo.systemUptime) }
                        } else {
                            if store.pomodoro.isPaused {
                                SButton(title: "reanudar", symbol: "play.fill") { store.pomodoro.resume(now: ProcessInfo.processInfo.systemUptime) }
                            } else {
                                SButton(title: "pausar", symbol: "pause.fill") { store.pomodoro.pause(now: ProcessInfo.processInfo.systemUptime) }
                            }
                            SButton(title: "parar", symbol: "stop.fill", destructive: true) { store.pomodoro.stop() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: atajos

struct ShortcutRow: View {
    @ObservedObject var store: PetStore
    let action: GlobalShortcut
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        SRow(title: ShortcutMap.title(action), detail: problem ?? "control + opción + letra") {
            HStack(spacing: 8) {
                Text("⌃ ⌥").font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsTheme.mute)
                TextField("", text: $text)
                    .textFieldStyle(.plain).multilineTextAlignment(.center).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 34, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(problem == nil ? 0.08 : 0.0)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(problem == nil ? SettingsTheme.line : SettingsTheme.red, lineWidth: 1))
            }
        }
        .onAppear { text = current }
        .onChange(of: text) { new in apply(new) }
    }

    private var current: String { String(store.shortcutMap.key(for: action)).uppercased() }

    private func apply(_ new: String) {
        guard !new.isEmpty else { return }
        let last = String(new.suffix(1))
        if new != last.uppercased() { text = last.uppercased(); return }
        var map = store.shortcutMap
        switch map.set(action, to: last) {
        case nil: store.shortcutMap = map; problem = nil
        case .notAKey?: problem = "solo letras o números sin acento"; text = current
        case .taken(let other)?: problem = "ya la usa: \(ShortcutMap.title(other))"; text = current
        }
    }
}

struct AtajosPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "global") {
                SToggle(title: "atajos globales de la isla", detail: "funcionan desde cualquier app; macOS puede pedirte permiso de accesibilidad.", isOn: $store.globalShortcutsEnabled)
            }
            SCard(title: "combinaciones", footer: "si una letra ya está en uso te lo dice y no cambia nada.") {
                ForEach(Array(GlobalShortcut.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { SDivider() }
                    ShortcutRow(store: store, action: action)
                }
                SDivider()
                SRow(title: "volver a las letras de siempre") {
                    SButton(title: "restablecer", symbol: "arrow.counterclockwise") { store.shortcutMap = .standard }
                }
            }
        }
    }
}

// MARK: copia y restauracion

struct CopiaPage: View {
    @ObservedObject var store: PetStore
    @State private var message: String?
    @State private var needsRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "copia de seguridad", footer: "el archivo solo contiene ajustes conocidos. al importar se comprueba cada valor y los que no son válidos se descartan.") {
                SRow(title: "exportar ajustes", detail: "guarda un .json con todo lo que has configurado.") {
                    SButton(title: "exportar…", symbol: "square.and.arrow.up") { export() }
                }
                SDivider()
                SRow(title: "importar ajustes", detail: "desde un archivo exportado antes, aquí o en otro Mac.") {
                    SButton(title: "importar…", symbol: "square.and.arrow.down") { importFile() }
                }
            }
            if let message {
                SCard {
                    SRow(title: message) {
                        if needsRestart {
                            SButton(title: AppRelauncher.canRelaunch ? "reiniciar ahora" : "reinicia la app", symbol: "arrow.clockwise", prominent: true) { AppRelauncher.relaunch() }
                        }
                    }
                }
            }
            SCard(title: "empezar de cero") {
                SRow(title: "restablecer todos los ajustes", detail: "no borra estadísticas, reglas ni puntos de restauración.") {
                    SButton(title: "restablecer…", symbol: "arrow.counterclockwise", destructive: true) { reset() }
                }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "claude-pet-ajustes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try SettingsBackup.export(from: .standard).write(to: url, options: .atomic); message = "ajustes exportados"; needsRestart = false }
        catch { message = "no se pudo guardar el archivo"; needsRestart = false }
    }

    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= SettingsBackup.maxBytes, let data = try? Data(contentsOf: url) else { message = "el archivo es demasiado grande o no se puede leer"; needsRestart = false; return }
        do {
            let report = try SettingsBackup.importing(data, into: .standard)
            let skipped = report.skipped.isEmpty ? "" : " · \(report.skipped.count) descartados"
            message = "\(report.applied) ajustes aplicados\(skipped). reinicia para verlos todos."
            needsRestart = report.applied > 0
        } catch SettingsBackup.Failure.tooLarge { message = "el archivo es demasiado grande"; needsRestart = false }
        catch SettingsBackup.Failure.notSettings { message = "ese archivo no es una copia de ajustes de claude-pet"; needsRestart = false }
        catch { message = "el archivo no es un json válido"; needsRestart = false }
    }

    private func reset() {
        let alert = NSAlert()
        alert.messageText = "¿restablecer todos los ajustes?"
        alert.informativeText = "volverán a sus valores originales y la app se reiniciará. tus estadísticas y reglas no se tocan."
        alert.addButton(withTitle: "restablecer"); alert.addButton(withTitle: "cancelar")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SettingsBackup.reset(in: .standard)
        message = "ajustes restablecidos"; needsRestart = true
    }
}

// MARK: acerca de

struct AcercaPage: View {
    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "desarrollo" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "claude-pet") {
                SRow(title: "versión") { SBadge(text: version) }
                SDivider()
                SRow(title: "código y documentación", detail: "github.com/kisnner26/claude-pet") {
                    SButton(title: "abrir", symbol: "arrow.up.right") { if let url = URL(string: "https://github.com/kisnner26/claude-pet") { NSWorkspace.shared.open(url) } }
                }
            }
            SCard(title: "herramientas relacionadas", footer: "son proyectos aparte que se complementan con claude-pet.") {
                SRow(title: "commitero", detail: "agrupa tus cambios en commits atómicos.") {
                    SBadge(text: CommiteroLauncher.available() ? "instalado" : "no instalado", color: CommiteroLauncher.available() ? SettingsTheme.green : SettingsTheme.mute)
                }
            }
            SCard(title: "dónde vive cada dato") {
                SRow(title: "ajustes", detail: "preferencias de macOS de esta app") { EmptyView() }
                SDivider()
                SRow(title: "~/.claude-pet", detail: "estadísticas, reglas de aprobación, puntos de restauración, registro y sonidos") { EmptyView() }
            }
        }
    }
}
