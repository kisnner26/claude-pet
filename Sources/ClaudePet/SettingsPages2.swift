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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "así se ven ahora") {
                HStack(spacing: 28) {
                    VStack(spacing: 6) {
                        ClaudeSprite(outfits: store.outfitsNow()).frame(width: 120, height: 120).breathing()
                        Text("claude").font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.claude)
                    }
                    VStack(spacing: 6) {
                        CodexSprite(skin: store.codexSkin, outfits: store.outfitsNow()).frame(width: 120, height: 120).breathing(delay: 0.5)
                        Text("codex").font(.system(size: 11, design: .monospaced)).foregroundStyle(SettingsTheme.codexLight)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                if store.skin == .classic {
                    SDivider()
                    SRow(title: "los atuendos están dibujados para el aspecto bloque", detail: "con el aspecto clásico solo los lleva codex.") {
                        SButton(title: "usar bloque", symbol: "square.fill") { store.skin = .block }
                    }
                }
            }
            SCard(title: "atuendos", footer: "se llevan en las dos mascotas. subes de nivel con la actividad de la semana: sesiones, herramientas y racha.") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Outfit.allCases) { outfit in
                        let unlocked = Evolution.isUnlocked(outfit, level: store.weeklyRecap.level)
                        SpriteTile(title: outfit.title, detail: unlocked ? nil : "nivel \(Evolution.unlockLevel(outfit))", selected: store.wardrobe.contains(outfit), locked: !unlocked,
                                   action: { store.toggleOutfit(outfit) }) {
                            HStack(spacing: 2) {
                                ClaudeSprite(outfits: [outfit], skin: .block).frame(width: 46, height: 46)
                                CodexSprite(skin: store.codexSkin, outfits: [outfit]).frame(width: 46, height: 46)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            SCard(title: "temporadas") {
                SToggle(title: "atuendos de temporada", detail: "se visten solos en fechas señaladas: bufanda en invierno y gorro a fin de año.", isOn: $store.seasonalOutfits)
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
                GlassSlider(value: binding, range: 0...1, step: 0.05, width: 170)
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

// MARK: musica

struct MusicaPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var music: MusicController

    init(store: PetStore) {
        self.store = store
        _music = ObservedObject(wrappedValue: store.music)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "reproductor", footer: "lee el título, el artista y la portada de lo que suena en Spotify o Apple Music, solo en este Mac. la primera vez macOS te pide permiso para controlar cada app. la portada de Spotify se descarga de su servidor. nunca se abre una app que no esté ya abierta.") {
                SToggle(title: "reproductor en la isla", detail: "botón de música en la isla abierta, con portada, barra de progreso, anterior, pausa, siguiente y volumen.", isOn: $store.musicPlayer)
                SDivider()
                SRow(title: "ahora suena", detail: status) {
                    if let n = music.nowPlaying { SBadge(text: n.app.title, color: n.isPlaying ? SettingsTheme.green : SettingsTheme.mute) }
                }
            }
            SCard(title: "la mascota reacciona", footer: "no oye el audio: reacciona a lo que dicen las apps (suena o no, qué volumen, cuándo cambia el tema). más volumen, más notas.") {
                if store.musicPlayer {
                    SToggle(title: "reaccionar a la música", detail: "se pone auriculares, baila y suelta notas; al cambiar de tema hay un destello.", isOn: $store.musicReacts)
                } else {
                    SToggle(title: "bailar cuando suena algo", detail: "solo detecta si Spotify o Apple Music están reproduciendo. no lee títulos ni portadas.", isOn: $store.danceToMusic)
                }
            }
        }
        .onAppear { music.watching = store.musicPlayer }
        .onDisappear { music.watching = false }
    }

    private var status: String {
        guard store.musicPlayer else { return "activa el reproductor para verlo aquí" }
        guard let n = music.nowPlaying else { return "nada ahora mismo, o la app no está abierta" }
        return "\(n.title) · \(n.artist)"
    }
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

// MARK: perimetro

/// Un campo de texto con su lista de patrones: se anade con intro o con el boton y se quita uno a uno.
struct GlobListEditor: View {
    let title: String
    let detail: String
    let placeholder: String
    @Binding var globs: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRow(title: title, detail: detail) { EmptyView() }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(globs.enumerated()), id: \.offset) { index, glob in
                    HStack(spacing: 8) {
                        Text(glob).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button { globs.remove(at: index) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.mute) }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                HStack(spacing: 8) {
                    TextField(placeholder, text: $draft).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SettingsTheme.line, lineWidth: 1))
                        .onSubmit(add)
                    SButton(title: "añadir", symbol: "plus", action: add)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= Perimeter.maxGlobLength, globs.count < Perimeter.maxGlobs, !globs.contains(t) else { return }
        globs.append(t); draft = ""
    }
}

struct PerimetroPage: View {
    @ObservedObject var store: PetStore

    /// Solo para las capturas de documentacion: finge un proyecto activo.
    static var previewWorkspace: String?
    private var workspace: String { Self.previewWorkspace ?? store.mission.workspace }
    private var current: Perimeter? { store.perimeters.first { $0.root == workspace } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "cómo funciona", footer: "cubre Edit, Write, MultiEdit y NotebookEdit, que son los que traen la ruta del archivo. los comandos de terminal no se pueden acotar por carpeta.") {
                SRow(title: "el agente no puede salirse de su zona", detail: "cuando pide editar un archivo, claude-pet comprueba la ruta contra tu perímetro. si se sale, el permiso sale en rojo y nunca se aprueba solo; en modo bloquear ni siquiera te molesta: se deniega.") { EmptyView() }
            }
            if workspace.isEmpty {
                SCard(title: "proyecto actual") { SRow(title: "no hay un proyecto activo", detail: "abre una sesión de claude en un proyecto para fijarle un perímetro.") { EmptyView() } }
            } else if let p = current {
                editor(p)
            } else {
                SCard(title: "proyecto actual") {
                    SRow(title: workspace.replacingOccurrences(of: NSHomeDirectory(), with: "~"), detail: "sin perímetro. empieza protegiendo lo delicado (.env, claves, .git) y, si quieres, acota las carpetas permitidas.") {
                        SButton(title: "crear perímetro", symbol: "plus", prominent: true) { _ = PerimeterStore.shared.upsert(Perimeter(root: workspace)) }
                    }
                }
            }
            others
        }
    }

    @ViewBuilder private func editor(_ p: Perimeter) -> some View {
        let allow = Binding(get: { p.allow }, set: { var q = p; q.allow = $0; PerimeterStore.shared.upsert(q) })
        let protect = Binding(get: { p.protect }, set: { var q = p; q.protect = $0; PerimeterStore.shared.upsert(q) })
        let mode = Binding(get: { p.mode }, set: { var q = p; q.mode = $0; PerimeterStore.shared.upsert(q) })
        SCard(title: "proyecto actual") {
            SRow(title: p.root.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                SButton(title: "quitar", symbol: "trash", destructive: true) { PerimeterStore.shared.remove(root: p.root) }
            }
            SDivider()
            SSegmented(title: "si se sale", detail: "avisar: el permiso sale en rojo y decides tú. bloquear: se deniega sin preguntar.", selection: mode, options: Perimeter.Mode.allCases.map { ($0, $0.rawValue) })
        }
        SCard(title: "dónde puede editar", footer: "rutas o patrones relativos al proyecto, por ejemplo Sources/Auth o Tests/**. vacío significa todo el proyecto.") {
            GlobListEditor(title: "carpetas permitidas", detail: allow.wrappedValue.isEmpty ? "todo el proyecto" : "solo estas", placeholder: "Sources/Auth", globs: allow)
        }
        SCard(title: "qué nunca debe tocar", footer: "gana sobre las carpetas permitidas. sin barra, el patrón vale en cualquier carpeta: .env* protege app/.env.local.") {
            GlobListEditor(title: "archivos protegidos", detail: "siempre cuentan como violación", placeholder: "**/secrets/**", globs: protect)
        }
    }

    @ViewBuilder private var others: some View {
        let rest = store.perimeters.filter { $0.root != workspace }
        if !rest.isEmpty {
            SCard(title: "otros perímetros") {
                ForEach(Array(rest.enumerated()), id: \.element.id) { index, p in
                    if index > 0 { SDivider() }
                    SRow(title: p.root.replacingOccurrences(of: NSHomeDirectory(), with: "~"), detail: "\(p.mode.rawValue) · \(p.allow.isEmpty ? "todo el proyecto" : "\(p.allow.count) carpetas") · \(p.protect.count) protegidos") {
                        SButton(title: "quitar", destructive: true) { PerimeterStore.shared.remove(root: p.root) }
                    }
                }
            }
        }
    }
}
