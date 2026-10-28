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
                .fill(LinearGradient(colors: [SettingsTheme.claude.opacity(0.38), SettingsTheme.violet.opacity(0.22), SettingsTheme.codex.opacity(0.46)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                for i in 0..<46 {
                    let x = CGFloat((i * 7919) % 1000) / 1000 * size.width, y = CGFloat((i * 104729) % 1000) / 1000 * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.14 + Double(i % 5) * 0.06)))
                }
            }
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("claude-pet").font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    Text(store.state == .idle ? "todo tranquilo. tus agentes no están trabajando ahora." : "claude: \(store.state.label.lowercased()) · \(store.sessionSummary)")
                        .font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    HStack(spacing: 8) {
                        SBadge(text: store.claudePresent ? "claude conectado" : "claude sin sesión", color: store.claudePresent ? SettingsTheme.green : SettingsTheme.mute)
                        SBadge(text: store.codexPresent ? "codex conectado" : "codex sin sesión", color: store.codexPresent ? SettingsTheme.green : SettingsTheme.mute)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: -6) {
                    ClaudeSprite(state: store.state, outfits: store.outfitsNow()).frame(width: 104, height: 104).breathing()
                    CodexSprite(face: store.codexPresent && store.codexState != .idle ? .typing(1) : .prompt(cursor: true), skin: store.codexSkin, outfits: store.outfitsNow(for: .codex)).frame(width: 104, height: 104).breathing(delay: 0.5)
                }
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 170)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(SettingsTheme.cardBorder, lineWidth: 1))
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

/// Elegir y ordenar las acciones del dock de la isla.
struct QuickActionsCard: View {
    @ObservedObject var store: PetStore

    private var off: [QuickAction] { QuickActions.allOrdered.filter { !store.quickActions.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) { actionsCard; appCard }
    }

    private var actionsCard: some View {
        SCard(title: "acceso rápido", footer: "en la isla se ven hasta cinco a la vez, según el contexto (sin cambios no hay «commitear»); el resto va en el menú +. pasa el cursor sobre un icono para ver su nombre.") {
            ForEach(Array(store.quickActions.enumerated()), id: \.element) { index, a in
                if index > 0 { SDivider() }
                row(a, on: true, index: index)
            }
            if !store.quickActions.isEmpty && !off.isEmpty { SDivider() }
            ForEach(Array(off.enumerated()), id: \.element) { index, a in
                if index > 0 { SDivider() }
                row(a, on: false, index: -1)
            }
            SDivider()
            SRow(title: "volver a los de siempre") { SButton(title: "restablecer", symbol: "arrow.counterclockwise") { store.quickActions = QuickActions.defaultEnabled } }
        }
    }

    private var appCard: some View {
        SCard(title: "según la app", footer: "como la Touch Bar: el dock enseña primero lo que hace falta en la app donde estás y rellena con tus acciones. solo se lee qué app está al frente (su nombre), nada de su contenido ni de la pantalla.") {
            SToggle(title: "cambiar de herramientas según la app", detail: "un icono de la app aparece al lado del dock para explicar por qué cambió.", isOn: $store.quickAppAware)
            if store.quickAppAware {
                ForEach(AppProfile.allCases.filter { $0 != .other }, id: \.self) { p in
                    SDivider()
                    SRow(title: p.title, detail: p.examples) {
                        HStack(spacing: 6) {
                            ForEach(p.priority.prefix(4), id: \.self) { a in
                                Image(systemName: QuickActions.descriptor(a, QuickContext(frontAppName: "editor")).symbol).font(.system(size: 11)).foregroundStyle(SettingsTheme.duo).frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.white.opacity(0.07))).help(QuickActions.descriptor(a, QuickContext(frontAppName: "editor")).title)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ a: QuickAction, on: Bool, index: Int) -> some View {
        let d = QuickActions.descriptor(a, QuickContext())
        return SRow(title: d.title, detail: "aparece cuando: " + d.when) {
            HStack(spacing: 10) {
                if on {
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plain).disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plain).disabled(index == store.quickActions.count - 1)
                }
                Image(systemName: d.symbol).font(.system(size: 12)).frame(width: 18).foregroundStyle(on ? AnyShapeStyle(SettingsTheme.duo) : AnyShapeStyle(SettingsTheme.mute))
                Toggle(d.title, isOn: Binding(get: { on }, set: { newValue in
                    if newValue { if !store.quickActions.contains(a) { store.quickActions.append(a) } } else { store.quickActions.removeAll { $0 == a } }
                })).labelsHidden().toggleStyle(GlassToggleStyle())
            }
            .foregroundStyle(SettingsTheme.mute)
        }
    }

    private func move(_ i: Int, by d: Int) {
        let j = i + d
        guard store.quickActions.indices.contains(i), store.quickActions.indices.contains(j) else { return }
        store.quickActions.swapAt(i, j)
    }
}

// MARK: comportamiento

struct ComportamientoPage: View {
    @ObservedObject var store: PetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SCard(title: "idioma") {
                SMenu(title: "idioma", detail: "elige el idioma de la interfaz. se aplica al momento.", selection: $store.language,
                      options: Lang.allCases.map { ($0, $0.name) })
            }
            SCard(title: "en el escritorio", footer: "arrastra la mascota fuera de la isla y se queda donde la sueltes (vuelve a su sitio al abrir la app). doble toque, o soltarla sobre la isla, la devuelve.") {
                SToggle(title: "seguir el cursor", detail: "camina hacia el cursor cuando te alejas de ella.", isOn: $store.deskFollow)
                SDivider()
                SRow(title: "claude", detail: store.deskOut.contains(.claude) ? "está en el escritorio" : "en la isla") {
                    SButton(title: store.deskOut.contains(.claude) ? "volver" : "sacar", symbol: store.deskOut.contains(.claude) ? "arrow.uturn.backward" : "arrow.up.right") {
                        if store.deskOut.contains(.claude) { DesktopPets.shared.putBack(.claude) } else { DesktopPets.shared.show(.claude) }
                    }
                }
                SDivider()
                SRow(title: "codex", detail: store.deskOut.contains(.codex) ? "está en el escritorio" : "en la isla") {
                    SButton(title: store.deskOut.contains(.codex) ? "volver" : "sacar", symbol: store.deskOut.contains(.codex) ? "arrow.uturn.backward" : "arrow.up.right") {
                        if store.deskOut.contains(.codex) { DesktopPets.shared.putBack(.codex) } else { DesktopPets.shared.show(.codex) }
                    }
                }
            }
            SCard(title: "genio", footer: "si la golpeas seguido, a veces se enfada, se hace gigante, camina hasta una ventana y la patea. la ventana solo se minimiza (nunca se cierra) y hace falta el permiso de accesibilidad; sin él solo hace la animación. se calma durante un minuto.") {
                SToggle(title: "se enfada si la golpeas", detail: "una patada a una ventana de otra app, sin cerrarla.", isOn: $store.rageEnabled)
                if store.rageEnabled {
                    SDivider()
                    SRow(title: "permiso de accesibilidad", detail: AXIsProcessTrusted() ? "concedido: puede minimizar la ventana" : "sin él la patada es solo la animación") {
                        SButton(title: "pedir permiso", symbol: "lock.open") {
                            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                        }
                    }
                    SDivider()
                    SRow(title: "probar ahora", detail: "lo hace con la ventana de otra app que tengas arriba.") {
                        SButton(title: "probar", symbol: "figure.kickboxing") { RageController.shared.start(agent: .claude, store: store) }
                    }
                }
            }
            SCard(title: "al acercar el cursor", footer: "con un retraso mayor se evitan aperturas por accidente al pasar por la parte de arriba.") {
                SSlider(title: "ancho de la zona", detail: "cuánto mide, en puntos, el área que despierta la isla.", value: $store.islandActivationWidth, range: 120...400, step: 20) { "\(Int($0)) pt" }
                SDivider()
                SSlider(title: "retraso al asomar", value: $store.islandActivationDelay, range: 0...1, step: 0.05) { $0 == 0 ? "ya" : String(format: "%.2f s", $0) }
            }
            SCard(title: "al alejar el cursor") {
                SMenu(title: "plegar la isla", selection: $store.islandCloseDelay,
                      options: [(0.6, "rápido"), (1.2, "normal"), (2.5, "lento"), (0.0, "solo a los 60 s")])
            }
            QuickActionsCard(store: store)
            SCard(title: "visibilidad") {
                SToggle(title: "aparición automática", detail: "la isla se muestra sola cuando un agente empieza a trabajar.", isOn: $store.autoVisibility)
                SDivider()
                SToggle(title: "mantener las mascotas visibles", detail: "no se ocultan al terminar la sesión.", isOn: $store.pinSession)
            }
        }
    }
}

// MARK: agentes

/// Tarjeta de un agente: su mascota, su estado y lo que se puede ajustar de el. El color del agente tiñe la tarjeta.
struct AgentCard<Sprite: View, Content: View>: View {
    let name: String
    let tint: Color
    let status: String
    var statusColor: Color?
    @ViewBuilder var sprite: Sprite
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                sprite.frame(width: 84, height: 84).breathing()
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.system(size: 22, weight: .bold)).tracking(-0.3)
                    SBadge(text: status, color: statusColor ?? tint)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RadialGradient(colors: [tint.opacity(0.24), .clear], center: .topLeading, startRadius: 4, endRadius: 360))
        })
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(LinearGradient(colors: [tint.opacity(0.55), Color.white.opacity(0.06), tint.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

struct AgentesPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var scout: NativeWebScoutController

    init(store: PetStore) {
        self.store = store
        _scout = ObservedObject(wrappedValue: store.webScout)
    }

    private var outfits: Set<Outfit> { store.outfitsNow() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            claudeCard
            codexCard
            SCard(title: "exploración web") {
                SToggle(title: "verificar enlaces rotos", detail: "el explorador comprueba cada enlace que encuentra.", isOn: $scout.verifyLinks)
            }
        }
    }

    private var claudeCard: some View {
        AgentCard(name: "claude", tint: SettingsTheme.claude, status: store.claudePresent ? "sesión activa" : "sin sesión", statusColor: store.claudePresent ? SettingsTheme.green : SettingsTheme.mute,
                  sprite: { ClaudeSprite(state: store.state, outfits: outfits) }) {
            SRow(title: "mostrar en la isla") {
                Toggle("mostrar claude", isOn: Binding(get: { !store.muteClaude }, set: { store.muteClaude = !$0 })).labelsHidden().toggleStyle(GlassToggleStyle())
            }
            SDivider()
            VStack(alignment: .leading, spacing: 8) {
                Text("aspecto").font(.system(size: 13.5, weight: .medium))
                HStack(spacing: 10) {
                    ForEach(Skin.allCases, id: \.self) { skin in
                        SpriteTile(title: skin.title, selected: store.skin == skin, action: { store.skin = skin }) { ClaudeSprite(outfits: skin == .block ? outfits : [], skin: skin).frame(width: 64, height: 64) }
                    }
                }
                if store.skin == .classic { Text("los atuendos están dibujados para el aspecto bloque.").font(.system(size: 11)).foregroundStyle(SettingsTheme.mute) }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            SDivider()
            SToggle(title: "detalle local", detail: "lee el contexto y los archivos de la sesión, solo en este Mac.", isOn: $store.showDetail)
            SDivider()
            SToggle(title: "avisar si parece bloqueado", detail: "una alerta cuando lleva mucho rato sin avanzar.", isOn: $store.stallWatch)
        }
    }

    private var codexCard: some View {
        AgentCard(name: "codex", tint: SettingsTheme.codex, status: store.codexPresent ? "sesión activa" : "sin sesión", statusColor: store.codexPresent ? SettingsTheme.green : SettingsTheme.mute,
                  sprite: { CodexSprite(skin: store.codexSkin, outfits: outfits) }) {
            SRow(title: "mostrar en la isla") {
                Toggle("mostrar codex", isOn: Binding(get: { !store.muteCodex }, set: { store.muteCodex = !$0 })).labelsHidden().toggleStyle(GlassToggleStyle())
            }
            SDivider()
            VStack(alignment: .leading, spacing: 8) {
                Text("aspecto").font(.system(size: 13.5, weight: .medium))
                HStack(spacing: 10) {
                    ForEach(CodexSkin.allCases, id: \.self) { skin in
                        SpriteTile(title: skin.title, selected: store.codexSkin == skin, action: { store.codexSkin = skin }) { CodexSprite(skin: skin, outfits: outfits).frame(width: 64, height: 64) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            SDivider()
            SToggle(title: "gestos", detail: "la mascota de codex reacciona a lo que pasa.", isOn: $store.codexGesturesEnabled)
        }
    }
}
