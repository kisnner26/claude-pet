import SwiftUI
import AppKit

/// Los menus viven dentro de la propia pildora: un riel de iconos a la derecha cambia de pagina sin abrir ventanas.
enum IslandPage: String, CaseIterable, Identifiable {
    case home, changes, music, plan, tools, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: return "inicio"; case .changes: return "cambios"; case .music: return "música"; case .plan: return "plan y datos"; case .tools: return "herramientas"; case .settings: return "ajustes" }
    }
    var symbol: String {
        switch self { case .home: return "pawprint.fill"; case .changes: return "plus.forwardslash.minus"; case .music: return "music.note"; case .plan: return "chart.bar.fill"; case .tools: return "square.grid.2x2.fill"; case .settings: return "slider.horizontal.3" }
    }
    /// Cada pagina tiene su luz: el riel y los bordes la toman.
    var accent: Color {
        switch self { case .home: return Color(hex: 0xE0824F); case .changes: return Color(hex: 0x6CCB8A); case .music: return Color(hex: 0xE58BB0); case .plan: return Color(hex: 0x7C93F0); case .tools: return Color(hex: 0x6FD3E8); case .settings: return Color(hex: 0xC4A8FF) }
    }
    /// Que paginas se muestran: la de musica solo con el reproductor activo.
    static func visible(musicPlayer: Bool) -> [IslandPage] { allCases.filter { $0 != .music || musicPlayer } }
}

/// Fibra de vidrio: vidrio oscuro con hebras finas que se ven al trasluz, destellos de luz que viajan por ellas y un borde con brillo especular.
struct FiberGlassLayer: View {
    var accent: Color = Color(hex: 0x7C93F0)
    var animated = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in canvas(t: ctx.date.timeIntervalSinceReferenceDate) }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { gc, size in
            // brillo de la tapa de cristal
            gc.fill(Path(CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height * 0.5))),
                    with: .linearGradient(Gradient(colors: [.white.opacity(0.085), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.5)))
            // hebras: lineas casi horizontales con una ligera ondulacion
            let n = 34
            for i in 0..<n {
                let k = Double(i) / Double(n - 1)
                let y0 = size.height * (0.04 + 0.92 * k), amp = 3 + 7 * FiberGlassLayer.rnd(i + 11), ph = FiberGlassLayer.rnd(i + 29) * 6.28
                var p = Path(); p.move(to: CGPoint(x: -4, y: y0))
                var x = -4.0
                while x <= size.width + 8 { p.addLine(to: CGPoint(x: x, y: y0 + amp * sin(x / (60 + 40 * FiberGlassLayer.rnd(i + 3)) + ph))); x += 12 }
                gc.stroke(p, with: .color(.white.opacity(0.028 + 0.04 * FiberGlassLayer.rnd(i + 47))), lineWidth: 0.6)
            }
            // pulsos de luz que recorren algunas hebras, como en una fibra optica
            for i in 0..<5 {
                let y0 = size.height * (0.12 + 0.76 * FiberGlassLayer.rnd(i + 71)), amp = 3 + 7 * FiberGlassLayer.rnd(i * 2 + 11)
                let speed = 0.10 + 0.12 * FiberGlassLayer.rnd(i + 91), head = ((t * speed) + FiberGlassLayer.rnd(i + 13)).truncatingRemainder(dividingBy: 1.4) - 0.2
                var p = Path(), started = false
                for s in stride(from: 0.0, through: 1.0, by: 0.012) {
                    let x = (head - 0.16 * (1 - s)) * size.width
                    guard x > -2, x < size.width + 2 else { continue }
                    let pt = CGPoint(x: x, y: y0 + amp * sin(x / 70 + Double(i)))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                }
                gc.stroke(p, with: .linearGradient(Gradient(colors: [accent.opacity(0), accent.opacity(0.55), .white.opacity(0.7)]), startPoint: CGPoint(x: (head - 0.16) * size.width, y: y0), endPoint: CGPoint(x: head * size.width, y: y0)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    static func rnd(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }
}

/// Borde de la pildora con un destello especular que da la vuelta despacio.
struct FiberGlassEdge: View {
    let shape: IslandShape
    var accent: Color
    var animated: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 20.0 : 3600)) { ctx in
            let a = animated ? (ctx.date.timeIntervalSinceReferenceDate * 22).truncatingRemainder(dividingBy: 360) : 40
            shape.stroke(AngularGradient(colors: [.white.opacity(0.05), .white.opacity(0.05), accent.opacity(0.55), .white.opacity(0.65), .white.opacity(0.05)], center: .center, angle: .degrees(a)), lineWidth: 2)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension View {
    /// Tarjeta de fibra de vidrio para el contenido de las paginas.
    func fiberCard(_ accent: Color = .white, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [accent.opacity(0.45), Color.white.opacity(0.07), accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
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
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch page {
                case .home: IslandOverviewView(store: store, model: model, agentTab: $agentTab)
                case .changes: IslandChangesPage(store: store)
                case .music: IslandMusicPage(store: store)
                case .plan: IslandPlanPage(store: store)
                case .tools: IslandToolsPage(store: store)
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
        VStack(spacing: 4) {
            ForEach(pages) { p in
                Button { model.page = p } label: {
                    Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold))
                        .foregroundColor(page == p ? .white : .white.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .background {
                            if page == p {
                                Circle().fill(p.accent.opacity(0.28)).overlay(Circle().strokeBorder(p.accent.opacity(0.8), lineWidth: 0.8))
                                    .shadow(color: p.accent.opacity(0.7), radius: 6)
                                    .matchedGeometryEffect(id: "sel", in: rail)
                            }
                        }
                }
                .buttonStyle(.plain).help(p.title).accessibilityLabel(p.title)
                .accessibilityAddTraits(page == p ? .isSelected : [])
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 3)
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
            Circle().fill(page.accent).frame(width: 6, height: 6).shadow(color: page.accent, radius: 4)
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

struct IslandToolsPage: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var music: MusicController
    @ObservedObject private var plugins: PluginHost
    init(store: PetStore) { self.store = store; _music = ObservedObject(wrappedValue: store.music); _plugins = ObservedObject(wrappedValue: store.plugins) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(page: .tools, detail: "todo lo que tienes a mano")
            let dock = QuickDock(store: store, music: music, plugins: plugins, summary: { "\(store.sessionSummary) · \(store.state.label.lowercased())" }, showAll: true)
                .frame(maxWidth: .infinity, alignment: .leading).fiberCard(IslandPage.tools.accent)
            // las capturas no dibujan el contenido de un ScrollView
            if IslandSnapshot.isRendering { dock } else { ScrollView(.vertical, showsIndicators: false) { dock } }
        }
    }
}

struct IslandSettingsPage: View {
    @ObservedObject var store: PetStore
    private let accent = IslandPage.settings.accent
    private let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader(page: .settings, detail: "ajustes rápidos")
            LazyVGrid(columns: cols, spacing: 6) {
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
                        Text(l.name).font(.system(size: 10.5, weight: .medium)).foregroundColor(store.language == l ? .white : .white.opacity(0.5)).padding(.horizontal, 10).frame(height: 24)
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
                Circle().fill(on.wrappedValue ? accent : Color.white.opacity(0.18)).frame(width: 6, height: 6).shadow(color: on.wrappedValue ? accent : .clear, radius: 3)
            }
            .foregroundColor(on.wrappedValue ? .white : .white.opacity(0.55)).padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on.wrappedValue ? accent.opacity(0.16) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on.wrappedValue ? accent.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.8))
        }.buttonStyle(.plain)
    }
}
