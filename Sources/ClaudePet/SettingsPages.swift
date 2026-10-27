import SwiftUI
import AppKit

// MARK: resumen

struct ResumenPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            HStack(spacing: 12) {
                SStat(value: "\(store.today.sessions)", label: "sesiones hoy")
                SStat(value: "\(store.today.tools)", label: "herramientas hoy")
                SStat(value: "\(store.today.permissions)", label: "permisos hoy")
                SStat(value: "\(store.today.errors)", label: "errores hoy")
            }
            SCard(title: "esta semana") {
                SRow(title: "nivel \(store.weeklyRecap.level)", detail: "racha de \(store.weeklyRecap.streak) \(store.weeklyRecap.streak == 1 ? "día" : "días") · \(store.weeklyRecap.activeDays) de 7 con actividad") {
                    SBadge(text: "\(store.weeklyRecap.sessions) sesiones")
                }
                SDivider()
                SRow(title: "más usado", detail: store.weeklyRecap.topAgent.map { "agente: \($0)" } ?? "todavía sin datos") {
                    if let p = store.weeklyRecap.topProject { SBadge(text: p, color: SettingsTheme.green) }
                }
                SDivider()
                SRow(title: "compartir la semana") {
                    HStack(spacing: 8) {
                        SButton(title: "copiar", symbol: "doc.on.doc") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.weeklyRecap.markdown(showProject: store.shareProject), forType: .string)
                        }
                        SButton(title: "imagen…", symbol: "photo") {
                            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "mi-semana.png"
                            if panel.runModal() == .OK, let url = panel.url, let data = RecapCard.png(store.weeklyRecap, showProject: false) { try? data.write(to: url) }
                        }
                    }
                }
            }
            SCard(title: "atajos de trabajo") {
                SRow(title: "mission control", detail: "cambios del proyecto, ramas y conflictos") {
                    SButton(title: "abrir", symbol: "square.grid.2x2") { AppController.shared.showMissionDashboard() }
                }
                SDivider()
                SRow(title: "relevo de sesión", detail: "continuar la misma tarea en otro agente") {
                    SButton(title: "abrir", symbol: "arrow.triangle.swap") { AppController.shared.showRelay() }
                }
            }
        }
        .onAppear { store.refreshWeeklyRecap() }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [SettingsTheme.blue.opacity(0.55), Color(hex: 0x1D2547).opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                for i in 0..<46 {
                    let x = CGFloat((i * 7919) % 1000) / 1000 * size.width, y = CGFloat((i * 104729) % 1000) / 1000 * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.18 + Double(i % 5) * 0.07)))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("claude-pet").font(.system(size: 34, weight: .bold)).tracking(-0.6)
                Text(store.state == .idle ? "todo tranquilo. tus agentes no están trabajando ahora." : "claude: \(store.state.label.lowercased()) · \(store.sessionSummary)")
                    .font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.78))
                HStack(spacing: 8) {
                    SBadge(text: store.claudePresent ? "claude conectado" : "claude sin sesión", color: store.claudePresent ? SettingsTheme.green : SettingsTheme.mute)
                    SBadge(text: store.codexPresent ? "codex conectado" : "codex sin sesión", color: store.codexPresent ? SettingsTheme.green : SettingsTheme.mute)
                }
            }
            .padding(26)
        }
        .frame(height: 164)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(SettingsTheme.line, lineWidth: 1))
    }
}

// MARK: apariencia

/// Dibujo esquematico de la pantalla con la isla donde quedara; se mueve al cambiar los ajustes.
struct IslandPreview: View {
    let placement: IslandPlacement
    let activation: Double
    let compact: IslandCompactMode
    let clock: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.55))
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SettingsTheme.line, lineWidth: 1)
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 8).frame(maxHeight: .infinity, alignment: .top).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                zone(w: w, h: h)
                island(w: w, h: h)
            }
        }
        .frame(height: 150)
        .animation(.easeOut(duration: 0.25), value: placement)
        .animation(.easeOut(duration: 0.25), value: activation)
    }

    private func pillSize() -> CGSize {
        switch compact { case .minimal: return CGSize(width: 54, height: 14); case .normal: return CGSize(width: 86, height: 16); case .full: return CGSize(width: 120, height: 18) }
    }

    @ViewBuilder private func island(w: CGFloat, h: CGFloat) -> some View {
        let s = pillSize()
        let pill = ZStack {
            Capsule().fill(Color.black)
            Capsule().stroke(SettingsTheme.blue.opacity(0.7), lineWidth: 1)
            HStack(spacing: 5) {
                Circle().fill(SettingsTheme.green).frame(width: 5, height: 5)
                if compact != .minimal { Capsule().fill(Color.white.opacity(0.5)).frame(width: 26, height: 3) }
                if clock { Text("9:41").font(.system(size: 7, design: .monospaced)).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        switch placement {
        case .top: pill.frame(width: s.width, height: s.height).position(x: w / 2, y: s.height / 2 + 6)
        case .bottom: pill.frame(width: s.width, height: s.height).position(x: w / 2, y: h - s.height / 2 - 8)
        case .side: pill.frame(width: s.width, height: s.height).rotationEffect(.degrees(90)).position(x: w - s.height / 2 - 8, y: h / 2)
        case .floating: pill.frame(width: s.width, height: s.height).position(x: w * 0.7, y: h * 0.4)
        }
    }

    @ViewBuilder private func zone(w: CGFloat, h: CGFloat) -> some View {
        let zw = CGFloat(activation / 400) * w * 0.62
        if placement == .top {
            RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsTheme.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 6).fill(SettingsTheme.blue.opacity(0.1)))
                .frame(width: zw, height: 34).position(x: w / 2, y: 17)
        } else if placement == .bottom {
            RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsTheme.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 6).fill(SettingsTheme.blue.opacity(0.1)))
                .frame(width: zw, height: 34).position(x: w / 2, y: h - 17)
        }
    }
}

struct AparienciaPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "vista previa", footer: "la zona punteada es donde el cursor despierta la isla.") {
                IslandPreview(placement: store.islandPlacement, activation: store.islandActivationWidth, compact: store.islandCompactMode, clock: store.islandShowClock)
                    .padding(.horizontal, 20).padding(.vertical, 14)
            }
            SCard(title: "isla") {
                SSegmented(title: "modo", selection: $store.layout, options: PetLayout.allCases.map { ($0, $0.title) })
                SDivider()
                SSegmented(title: "ubicación", selection: $store.islandPlacement, options: IslandPlacement.allCases.map { ($0, $0.rawValue) })
                SDivider()
                SSegmented(title: "contenido compacto", selection: $store.islandCompactMode, options: IslandCompactMode.allCases.map { ($0, $0.rawValue) })
                SDivider()
                SToggle(title: "reloj en la isla", isOn: $store.islandShowClock)
            }
            SCard(title: "pantalla") {
                SMenu(title: "dónde aparece", detail: "en un Mac sin notch sale una barra pequeña arriba.", selection: $store.islandScreenPreference,
                      options: IslandScreenPreference.allCases.map { ($0, $0.rawValue) })
                if store.islandScreenPreference == .fixed {
                    SDivider()
                    SMenu(title: "pantalla fija", selection: $store.islandFixedScreenID,
                          options: NSScreen.screens.map { (IslandController.screenID($0), $0.localizedName + ($0.safeAreaInsets.top > 0 ? " (con notch)" : "")) })
                }
            }
            SCard(title: "mascotas") {
                SMenu(title: "claude", selection: $store.skin, options: Skin.allCases.map { ($0, $0.title) })
                SDivider()
                SMenu(title: "codex", selection: $store.codexSkin, options: CodexSkin.allCases.map { ($0, $0.title) })
                SDivider()
                SToggle(title: "animaciones", detail: "respiración, parpadeo, saltos y efectos.", isOn: $store.animationsEnabled)
                SDivider()
                SToggle(title: "partido automático", detail: "las mascotas juegan al fútbol cuando no hay trabajo.", isOn: $store.footballEnabled)
                SDivider()
                SToggle(title: "burbuja de actividad", isOn: $store.showBubble)
                SDivider()
                SMenu(title: "avisos visuales", selection: $store.alertDisplayMode, options: AlertDisplayMode.allCases.map { ($0, $0.rawValue) })
            }
        }
    }
}

// MARK: comportamiento

struct ComportamientoPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "al acercar el cursor", footer: "con un retraso mayor se evitan aperturas por accidente al pasar por la parte de arriba.") {
                SSlider(title: "ancho de la zona", detail: "cuánto mide, en puntos, el área que despierta la isla.", value: $store.islandActivationWidth, range: 120...400, step: 20) { "\(Int($0)) pt" }
                SDivider()
                SSlider(title: "retraso al asomar", value: $store.islandActivationDelay, range: 0...1, step: 0.05) { $0 == 0 ? "ya" : String(format: "%.2f s", $0) }
            }
            SCard(title: "al alejar el cursor") {
                SMenu(title: "plegar la isla", selection: $store.islandCloseDelay,
                      options: [(0.6, "rápido"), (1.2, "normal"), (2.5, "lento"), (0.0, "solo a los 60 s")])
            }
            SCard(title: "visibilidad") {
                SToggle(title: "aparición automática", detail: "la isla se muestra sola cuando un agente empieza a trabajar.", isOn: $store.autoVisibility)
                SDivider()
                SToggle(title: "mantener las mascotas visibles", detail: "no se ocultan al terminar la sesión.", isOn: $store.pinSession)
            }
        }
    }
}

// MARK: agentes

struct AgentesPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var scout: NativeWebScoutController

    init(store: PetStore) {
        self.store = store
        _scout = ObservedObject(wrappedValue: store.webScout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "qué agentes se muestran") {
                SRow(title: "claude", detail: store.claudePresent ? "hay una sesión activa" : "sin sesión ahora mismo") {
                    Toggle("", isOn: Binding(get: { !store.muteClaude }, set: { store.muteClaude = !$0 })).labelsHidden().toggleStyle(.switch).tint(SettingsTheme.blue)
                }
                SDivider()
                SRow(title: "codex", detail: store.codexPresent ? "hay una sesión activa" : "sin sesión ahora mismo") {
                    Toggle("", isOn: Binding(get: { !store.muteCodex }, set: { store.muteCodex = !$0 })).labelsHidden().toggleStyle(.switch).tint(SettingsTheme.blue)
                }
                SDivider()
                SToggle(title: "gestos de codex", detail: "la mascota de codex reacciona a lo que pasa.", isOn: $store.codexGesturesEnabled)
            }
            SCard(title: "detalle y vigilancia") {
                SToggle(title: "detalle local de claude", detail: "lee el contexto y los archivos de la sesión, solo en este Mac.", isOn: $store.showDetail)
                SDivider()
                SToggle(title: "avisar si parecen bloqueados", detail: "una alerta cuando un agente lleva mucho rato sin avanzar.", isOn: $store.stallWatch)
            }
            SCard(title: "exploración web") {
                SToggle(title: "verificar enlaces rotos", detail: "el explorador comprueba cada enlace que encuentra.", isOn: $scout.verifyLinks)
            }
        }
    }
}
