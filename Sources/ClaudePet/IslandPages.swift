import SwiftUI
import AppKit

/// Los menus viven dentro de la propia pildora: un riel de iconos a la derecha cambia de pagina sin abrir ventanas.
enum IslandPage: String, CaseIterable, Identifiable {
    case home, changes, music, plan, memory, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: return "inicio"; case .changes: return "cambios"; case .music: return "música"; case .plan: return "plan y datos"; case .memory: return "memoria"; case .settings: return "ajustes" }
    }
    var symbol: String {
        switch self { case .home: return "terminal"; case .changes: return "plus.forwardslash.minus"; case .music: return "music.note"; case .plan: return "chart.xyaxis.line"; case .memory: return "point.3.connected.trianglepath.dotted"; case .settings: return "slider.horizontal.3" }
    }
    /// Una señal común hace que cada panel se lea como parte del mismo instrumento.
    var accent: Color { DashboardTheme.ember }
    /// Que paginas se muestran: la de musica solo con el reproductor activo.
    static func visible(musicPlayer: Bool) -> [IslandPage] { allCases.filter { $0 != .music || musicPlayer } }
}

/// Fondo técnico: carbón, trama de escaneo y señal ámbar de baja intensidad.
struct FiberGlassLayer: View {
    var accent: Color = Color(hex: 0xD6DEF5)
    var animated = true

    var body: some View {
        Canvas { gc, size in
            // velo ámbar hacia abajo: el borde de arriba sigue negro para fundirse con el notch
            gc.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.25), .init(color: DashboardTheme.amber.opacity(0.09), location: 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // reflejo especular suave, como luz sobre cristal curvo
            gc.fill(Path(ellipseIn: CGRect(x: -size.width * 0.15, y: -size.height * 0.9, width: size.width * 0.9, height: size.height * 1.3)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.10), .clear]), center: CGPoint(x: size.width * 0.3, y: 0), startRadius: 0, endRadius: size.width * 0.45))
            // hebras muy finas
            let n = 26
            for i in 0..<n {
                let k = Double(i) / Double(n - 1)
                let y0 = size.height * (0.04 + 0.92 * k), amp = 3 + 7 * FiberGlassLayer.rnd(i + 11), ph = FiberGlassLayer.rnd(i + 29) * 6.28
                var p = Path(); p.move(to: CGPoint(x: -4, y: y0))
                var x = -4.0
                while x <= size.width + 8 { p.addLine(to: CGPoint(x: x, y: y0 + amp * sin(x / (60 + 40 * FiberGlassLayer.rnd(i + 3)) + ph))); x += 16 }
                gc.stroke(p, with: .color(.white.opacity(0.012 + 0.022 * FiberGlassLayer.rnd(i + 47))), lineWidth: 0.6)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    static func rnd(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}

/// Borde de cristal: un hilo de luz blanca fino, mas claro arriba a la izquierda y casi apagado abajo. Fijo y sin color.
struct FiberGlassEdge: View {
    let shape: IslandShape
    var accent: Color
    var animated: Bool
    var body: some View {
        shape.stroke(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.07), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension View {
    /// Tarjeta de fibra de vidrio para el contenido de las paginas.
    func fiberCard(_ accent: Color = .white, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DashboardTheme.surfaceRaised.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DashboardTheme.line, lineWidth: 0.8))
    }
}

/// La vista abierta de la isla: una pagina y, a la derecha, el riel con los menus.
struct IslandShell: View {
    @ObservedObject var store: PetStore
    @ObservedObject var model: IslandModel
    @Binding var agentTab: IslandAgentTab
    @Namespace private var rail
    private var animated: Bool { store.animationsEnabled && !store.reduceMotion && !IslandSnapshot.isRendering }
    private var pages: [IslandPage] { IslandPage.visible(musicPlayer: store.musicPlayer) }
    private var page: IslandPage { pages.contains(model.page) ? model.page : .home }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Group {
                switch page {
                case .home: IslandOverviewView(store: store, model: model, agentTab: $agentTab)
                case .changes: IslandChangesPage(store: store)
                case .music: IslandMusicPage(store: store)
                case .plan: IslandPlanPage(store: store)
                case .memory: PetMemoryView(store: store)
                case .settings: IslandSettingsPage(store: store)
                }
            }
            .id(page)
            .transition(animated ? .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .leading)), removal: .opacity) : .identity)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            railView
        }
        .animation(animated ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: page)
    }

    private var railView: some View {
        VStack(spacing: 3) {
            ForEach(pages) { p in
                Button { model.page = p } label: {
                    Image(systemName: p.symbol).font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(page == p ? .white : .white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .background {
                            if page == p {
                                Circle().fill(Color.white.opacity(0.14)).overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8))
                                    .matchedGeometryEffect(id: "sel", in: rail)
                            }
                        }
                }
                .buttonStyle(.plain).help(p.title).accessibilityLabel(p.title)
                .accessibilityAddTraits(page == p ? .isSelected : [])
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 2)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8))
    }
}

// MARK: paginas

private struct PageHeader: View {
    let page: IslandPage
    var detail: String = ""
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.white.opacity(0.55)).frame(width: 5, height: 5)
            Text(page.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            if !detail.isEmpty { Text(detail).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.45)).lineLimit(1) }
            Spacer(minLength: 0)
        }
    }
}

struct IslandChangesPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var mission: MissionControl
    init(store: PetStore) { self.store = store; _mission = ObservedObject(wrappedValue: store.mission) }
    private let accent = IslandPage.changes.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(page: .changes, detail: mission.workspace.isEmpty ? "sin proyecto" : store.workspaceLabel)
            HStack(spacing: 8) {
                stat(mission.git.available ? mission.git.branch : "sin git", "rama")
                stat("\(mission.git.affected)", "sin commit")
                stat("\(mission.git.conflicts)", "conflictos", warn: mission.git.conflicts > 0)
                stat("\(mission.changes.count)", "del agente")
            }
            VStack(alignment: .leading, spacing: 3) {
                if mission.changes.isEmpty {
                    Text("el agente todavía no ha editado archivos").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(Array(mission.changes.prefix(4).enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 6) {
                            Text(c.name).font(.system(size: 11, design: .monospaced)).foregroundColor(.white).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("+\(c.added)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: 0x6CCB8A))
                            Text("−\(c.deleted)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(hex: 0xD85C5C))
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).fiberCard(accent)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                DockButton(title: "ver cambios", symbol: "plus.forwardslash.minus", prominent: true, badge: mission.changes.count) { store.openLatestDiff() }
                DockButton(title: "mission control", symbol: "square.grid.2x2") { AppController.shared.showMissionDashboard() }
                DockButton(title: "actualizar git", symbol: "arrow.clockwise") { store.mission.refreshGit() }
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ value: String, _ label: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(warn ? Color(hex: 0xD85C5C) : .white).lineLimit(1)
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
        }.frame(maxWidth: .infinity, alignment: .leading).fiberCard(accent, padding: 7)
    }
}

struct IslandMusicPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var music: MusicController
    init(store: PetStore) { self.store = store; _music = ObservedObject(wrappedValue: store.music) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(page: .music, detail: music.nowPlaying == nil ? "nada suena" : "")
            if music.nowPlaying != nil {
                MusicPanelView(music: music, accent: store.musicAccent.map { Color(hex: $0) } ?? IslandPage.music.accent).fiberCard(IslandPage.music.accent)
            } else {
                Text("abre Spotify o Apple Music y suena aquí, con su portada.").font(.system(size: 11)).foregroundColor(.white.opacity(0.55)).fiberCard(IslandPage.music.accent)
            }
            Spacer(minLength: 0)
        }
        .onAppear { music.watching = true }
        .onDisappear { music.watching = false }
    }
}

struct IslandPlanPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var plan: PlanUsageMonitor
    init(store: PetStore) { self.store = store; _plan = ObservedObject(wrappedValue: store.plan) }
    private let accent = IslandPage.plan.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(page: .plan, detail: "nivel \(store.weeklyRecap.level) · racha \(store.weeklyRecap.streak)")
            if let u = plan.usage { PlanUsageRow(usage: u).fiberCard(accent) }
            else { Text("sin datos del plan: se actualiza cuando claude trabaja").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).fiberCard(accent) }
            HStack(spacing: 8) {
                stat("\(store.today.sessions)", "sesiones")
                stat("\(store.today.tools)", "herramientas")
                stat("\(store.today.permissions)", "permisos")
                stat("\(store.today.errors)", "errores")
            }
            HStack(spacing: 8) {
                context("claude", store.contextReading?.remainingPercent)
                context("codex", store.codexContextReading?.remainingPercent)
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white)
            Text(verbatim: L.tr(l) + L.t(" hoy", " today")).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).fiberCard(accent, padding: 7)
    }

    private func context(_ name: String, _ remaining: Int?) -> some View {
        HStack(spacing: 8) {
            Text("contexto \(name)").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            Spacer(minLength: 0)
            if let r = remaining {
                Capsule().fill(Color.white.opacity(0.1)).frame(width: 70, height: 5)
                    .overlay(alignment: .leading) { Capsule().fill(r < 15 ? Color(hex: 0xD85C5C) : r < 35 ? Color(hex: 0xE7B45B) : accent).frame(width: 70 * CGFloat(r) / 100, height: 5).shadow(color: accent.opacity(0.6), radius: 3) }
                Text("\(r)%").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.white)
            } else { Text("—").foregroundColor(.white.opacity(0.4)) }
        }.frame(maxWidth: .infinity).fiberCard(accent, padding: 7)
    }
}

struct IslandSettingsPage: View {
    @ObservedObject var store: PetStore
    private let accent = IslandPage.settings.accent
    private let cols = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PageHeader(page: .settings, detail: "ajustes rápidos")
            LazyVGrid(columns: cols, spacing: 4) {
                chip("sonidos", "speaker.wave.2.fill", $store.soundsEnabled)
                chip("animaciones", "sparkles", $store.animationsEnabled)
                chip("modo foco", "moon.fill", $store.focusManual)
                chip("clima", "cloud.sun.fill", $store.weatherEnabled)
                chip("se enfada", "flame.fill", $store.rageEnabled)
                chip("avisos al móvil", "iphone.radiowaves.left.and.right", $store.phoneAlerts)
                chip("seguir cursor", "cursorarrow.motionlines", $store.deskFollow)
                chip("temporadas", "snowflake", $store.seasonalOutfits)
                chip("sentir entorno", "thermometer.medium", $store.ambientReactions)
            }
            HStack(spacing: 6) {
                ForEach(Lang.allCases) { l in
                    Button { store.language = l } label: {
                        Text(l.name).font(.system(size: 10.5, weight: .medium)).foregroundColor(store.language == l ? .white : .white.opacity(0.5)).padding(.horizontal, 10).frame(height: 22)
                            .background(Capsule().fill(store.language == l ? accent.opacity(0.3) : Color.white.opacity(0.05))).overlay(Capsule().strokeBorder(store.language == l ? accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 0.8))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                DockButton(title: "ajustes completos", symbol: "gearshape") { AppController.shared.showSettings() }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 16)
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(on.wrappedValue ? accent : Color.white.opacity(0.18)).frame(width: 6, height: 6)
            }
            .foregroundColor(on.wrappedValue ? .white : .white.opacity(0.55)).padding(.horizontal, 8).frame(height: 25)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on.wrappedValue ? accent.opacity(0.16) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on.wrappedValue ? accent.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.8))
        }.buttonStyle(.plain)
    }
}
